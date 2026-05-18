import Testing
import Foundation
import CoreLocation
import GRDB
@testable import LocoKit2

// All suites that install the Database injection seam share one global
// (`Database.highlander.injectedPool`). `@Suite(.serialized)` only serializes
// WITHIN a suite — Swift Testing still runs separate top-level suites in
// parallel, so as independent suites they stomped each other's injection
// (seen as "no such table" / fetch -> nil races).
//
// Nesting them under one `.serialized` parent makes the parent and ALL its
// descendants run serially, so only one temp pool owns the singleton at a
// time. Suites that don't touch the seam (pure logic, SampleImportProcessor,
// the smoke suite — all of which pass an explicit `db`) stay parallel.
@Suite(.serialized)
struct DatabaseSeamSuites {

    // MARK: - Step 7: injection seam verification

    @Suite final class InjectionSeamTests {
        let testDB: TestDatabase
        init() throws { testDB = try TestDatabase().installAsSharedPool() }
        deinit { testDB.tearDown() }

        @Test func singletonPoolIsRedirectedToTestPool() throws {
            #expect(Database.pool === testDB.pool)
            #expect(Database.highlander.injectedPool === testDB.pool)
        }

        @Test func productionStyleWriteAndReadHitTheTempDB() throws {
            let place = Place(
                coordinate: CLLocationCoordinate2D(latitude: 1.0, longitude: 2.0),
                name: "Seam Place"
            )
            try Database.pool.write { db in try place.insert(db) }

            let viaSingleton = try Database.pool.read { db in
                try Place.fetchOne(db, key: place.id)
            }
            let viaHarness = try testDB.pool.read { db in
                try Place.fetchOne(db, key: place.id)
            }
            #expect(viaSingleton?.name == "Seam Place")
            #expect(viaHarness?.name == "Seam Place")
        }

        @Test func tearDownResetsTheSeam() throws {
            #expect(Database.highlander.injectedPool != nil)
            testDB.tearDown()
            #expect(Database.highlander.injectedPool == nil)
            testDB.tearDown() // idempotent
        }
    }

    // MARK: - Step 4b: Merge guard / write-path safety

    @Suite final class MergeTests {
        let testDB: TestDatabase
        init() throws { testDB = try TestDatabase().installAsSharedPool() }
        deinit { testDB.tearDown() }

        @Test @TimelineActor
        func nonAdjacentItemsCannotMergeAndDoItIsANoOp() async throws {
            let (idA, idB) = try await testDB.pool.write { db -> (String, String) in
                let a = try Fixtures.insertItem(
                    db, samples: Fixtures.makeCollinearTrack(count: 2), isVisit: true
                )
                let b = try Fixtures.insertItem(
                    db, samples: Fixtures.makeCollinearTrack(count: 2), isVisit: true
                )
                return (a, b)
            }

            let itemA = try #require(
                try await TimelineItem.fetchItem(itemId: idA, includeSamples: true)
            )
            let itemB = try #require(
                try await TimelineItem.fetchItem(itemId: idB, includeSamples: true)
            )

            let list = await TimelineLinkedList(fromItems: [itemA, itemB])
            let merge = await Merge(keeper: itemA, deadman: itemB, in: list)

            // not adjacent -> isValid() fails -> impossible
            #expect(merge.score == .impossible)

            let result = await merge.doIt()
            #expect(result == nil)

            let (aDeleted, bDeleted) = try await testDB.pool.read { db -> (Bool, Bool) in
                let a = try TimelineItemBase.fetchOne(db, key: idA)
                let b = try TimelineItemBase.fetchOne(db, key: idB)
                return (a?.deleted ?? true, b?.deleted ?? true)
            }
            #expect(aDeleted == false)
            #expect(bDeleted == false)
        }

        // Circular edges (A -> B and B -> A): isValid() must reject because
        // the merge would create a cycle on the keeper.
        @Test @TimelineActor
        func circularEdgesAreRejected() async throws {
            let (idA, idB) = try await testDB.pool.write { db -> (String, String) in
                let a = try Fixtures.insertItem(
                    db, samples: Fixtures.makeCollinearTrack(count: 2), isVisit: true
                )
                let b = try Fixtures.insertItem(
                    db, samples: Fixtures.makeCollinearTrack(count: 2), isVisit: true
                )
                try Fixtures.linkChain(db, [a, b])          // a -> b
                try db.execute(                              // and b -> a (cycle)
                    sql: "UPDATE TimelineItemBase SET nextItemId = ? WHERE id = ?",
                    arguments: [a, b]
                )
                return (a, b)
            }

            let itemA = try #require(
                try await TimelineItem.fetchItem(itemId: idA, includeSamples: true)
            )
            let itemB = try #require(
                try await TimelineItem.fetchItem(itemId: idB, includeSamples: true)
            )
            let list = await TimelineLinkedList(fromItems: [itemA, itemB])
            let merge = await Merge(keeper: itemA, deadman: itemB, in: list)

            #expect(merge.score == .impossible)   // deadman.next == keeper.id
            #expect(await merge.doIt() == nil)
        }

        // Happy path: P -> K -> D, K and D are visits at the SAME confirmed
        // place, K longer than D. The merge must succeed: K survives, D is
        // deleted, and D's samples are reassigned to K. (The chain has a
        // predecessor P so the nil-edge guard quirk below is not hit.)
        @Test @TimelineActor
        func keeperConsumesAdjacentDeadmanAtSamePlace() async throws {
            let base = Date(timeIntervalSince1970: 1_700_000_000)
            let (kId, dId) = try await testDB.pool.write { db -> (String, String) in
                let place = try Fixtures.insertPlace(db)
                let p = try Fixtures.insertItem(
                    db, samples: Fixtures.makeCollinearTrack(
                        count: 2, start: base, secondsApart: 60,
                        activityType: .stationary), isVisit: true)
                let k = try Fixtures.insertItem(
                    db, samples: Fixtures.makeCollinearTrack(
                        count: 5, start: base.addingTimeInterval(1000),
                        secondsApart: 60, activityType: .stationary), isVisit: true)
                let d = try Fixtures.insertItem(
                    db, samples: Fixtures.makeCollinearTrack(
                        count: 3, start: base.addingTimeInterval(2000),
                        secondsApart: 60, activityType: .stationary), isVisit: true)
                try Fixtures.confirmVisitPlace(db, itemId: k, placeId: place.id)
                try Fixtures.confirmVisitPlace(db, itemId: d, placeId: place.id)
                try Fixtures.linkChain(db, [p, k, d])
                return (k, d)
            }

            let keeper = try #require(
                try await TimelineItem.fetchItem(itemId: kId, includeSamples: true))
            let deadman = try #require(
                try await TimelineItem.fetchItem(itemId: dId, includeSamples: true))
            let list = await TimelineLinkedList(fromItems: [keeper, deadman])
            let merge = await Merge(keeper: keeper, deadman: deadman, in: list)

            #expect(merge.score != .impossible)
            let result = await merge.doIt()
            #expect(result != nil)
            #expect(result?.kept.id == kId)
            #expect(result?.killed.map(\.id).contains(dId) == true)

            let (dDeleted, kDeleted, kSamples, dSamples) =
                try await testDB.pool.read { db -> (Bool, Bool, Int, Int) in
                    let d = try TimelineItemBase.fetchOne(db, key: dId)
                    let k = try TimelineItemBase.fetchOne(db, key: kId)
                    let kc = try LocomotionSample
                        .filter(LocomotionSample.Columns.timelineItemId == kId)
                        .fetchCount(db)
                    let dc = try LocomotionSample
                        .filter(LocomotionSample.Columns.timelineItemId == dId)
                        .fetchCount(db)
                    return (d?.deleted ?? false, k?.deleted ?? true, kc, dc)
                }
            #expect(dDeleted == true)        // deadman removed
            #expect(kDeleted == false)       // keeper survives
            #expect(kSamples == 8)           // 5 (K) + 3 (D) reassigned
            #expect(dSamples == 0)           // none left on deadman
        }

        // KNOWN FAILURE (BUG-004): two adjacent items with no other
        // neighbours should be mergeable, but the same-neighbor guard
        // compares `deadman.nextItemId == keeper.previousItemId`; when both
        // are nil, `nil == nil` is true, so the simplest valid 2-item merge
        // is wrongly rejected as impossible. Pinned so the suite stays green
        // and flips loudly if the guard is fixed.
        @Test @TimelineActor
        func twoItemAdjacentMergeShouldBePossible() async throws {
            let base = Date(timeIntervalSince1970: 1_700_000_000)
            let (kId, dId) = try await testDB.pool.write { db -> (String, String) in
                let place = try Fixtures.insertPlace(db)
                let k = try Fixtures.insertItem(
                    db, samples: Fixtures.makeCollinearTrack(
                        count: 5, start: base, secondsApart: 60,
                        activityType: .stationary), isVisit: true)
                let d = try Fixtures.insertItem(
                    db, samples: Fixtures.makeCollinearTrack(
                        count: 3, start: base.addingTimeInterval(1000),
                        secondsApart: 60, activityType: .stationary), isVisit: true)
                try Fixtures.confirmVisitPlace(db, itemId: k, placeId: place.id)
                try Fixtures.confirmVisitPlace(db, itemId: d, placeId: place.id)
                try Fixtures.linkChain(db, [k, d])   // only K -> D, no predecessor
                return (k, d)
            }
            let keeper = try #require(
                try await TimelineItem.fetchItem(itemId: kId, includeSamples: true))
            let deadman = try #require(
                try await TimelineItem.fetchItem(itemId: dId, includeSamples: true))
            let list = await TimelineLinkedList(fromItems: [keeper, deadman])
            let merge = await Merge(keeper: keeper, deadman: deadman, in: list)

            withKnownIssue("BUG-004: nil == nil same-neighbor guard blocks valid 2-item merge") {
                #expect(merge.score != .impossible)
            }
        }
    }

    // MARK: - Step 4c: trip-sample pruning idempotence

    @Suite final class PruningTests {
        let testDB: TestDatabase
        init() throws { testDB = try TestDatabase().installAsSharedPool() }
        deinit { testDB.tearDown() }

        // static: captures no non-Sendable instance self across the actor hop
        private static func sampleCount(_ itemId: String) async throws -> Int {
            try await TimelineItem
                .fetchItem(itemId: itemId, includeSamples: true)?
                .samples?.count ?? -1
        }

        @Test @TimelineActor
        func tripPruningRemovesRedundantPointsAndIsIdempotent() async throws {
            let track = Fixtures.makeCollinearTrack(count: 6, activityType: .car)

            let itemId = try await testDB.pool.write { db in
                try Fixtures.insertItem(db, samples: track, isVisit: false)
            }

            let original = try await Self.sampleCount(itemId)
            #expect(original == 6)

            let item1 = try #require(
                try await TimelineItem.fetchItem(itemId: itemId, includeSamples: true)
            )
            try await item1.pruneSamples()
            let afterFirst = try await Self.sampleCount(itemId)
            #expect(afterFirst < original)
            #expect(afterFirst >= 2)            // endpoints always survive

            let item2 = try #require(
                try await TimelineItem.fetchItem(itemId: itemId, includeSamples: true)
            )
            try await item2.pruneSamples()
            let afterSecond = try await Self.sampleCount(itemId)
            #expect(afterSecond == afterFirst) // idempotent
        }

        private static func sampleExists(_ db: GRDB.Database, _ id: String) throws -> Bool {
            try LocomotionSample.fetchOne(db, key: id) != nil
        }

        // Visit pruning: a 2-hour stationary visit sampled every 60 s. The
        // interior (outside the 30-min edge windows) collapses via the
        // 3-sample sliding window; re-running is a no-op (the documented
        // idempotence invariant).
        @Test @TimelineActor
        func visitPruningRemovesRedundantSamplesAndIsIdempotent() async throws {
            // 121 samples, 60 s apart -> spans 7200 s (2 h)
            let track = Fixtures.makeCollinearTrack(
                count: 121, secondsApart: 60, activityType: .stationary
            )
            let itemId = try await testDB.pool.write { db in
                try Fixtures.insertItem(db, samples: track, isVisit: true)
            }

            #expect(try await Self.sampleCount(itemId) == 121)

            let item1 = try #require(
                try await TimelineItem.fetchItem(itemId: itemId, includeSamples: true))
            try await item1.pruneSamples()
            let afterFirst = try await Self.sampleCount(itemId)
            #expect(afterFirst < 121)            // interior collapsed

            let item2 = try #require(
                try await TimelineItem.fetchItem(itemId: itemId, includeSamples: true))
            try await item2.pruneSamples()
            let afterSecond = try await Self.sampleCount(itemId)
            #expect(afterSecond == afterFirst)   // idempotent
        }

        // Samples within 30 min of the visit's start/end are protected and
        // must survive pruning even though they are stationary.
        @Test @TimelineActor
        func visitPruningProtectsEdgeSamples() async throws {
            let track = Fixtures.makeCollinearTrack(
                count: 121, secondsApart: 60, activityType: .stationary
            )
            let firstId = try #require(track.first).id
            let lastId = try #require(track.last).id

            let itemId = try await testDB.pool.write { db in
                try Fixtures.insertItem(db, samples: track, isVisit: true)
            }
            let item = try #require(
                try await TimelineItem.fetchItem(itemId: itemId, includeSamples: true))
            try await item.pruneSamples()

            let (firstAlive, lastAlive) = try await testDB.pool.read { db -> (Bool, Bool) in
                (try Self.sampleExists(db, firstId), try Self.sampleExists(db, lastId))
            }
            #expect(firstAlive)   // first sample is in the start edge window
            #expect(lastAlive)    // last sample is in the end edge window
        }
    }
}
