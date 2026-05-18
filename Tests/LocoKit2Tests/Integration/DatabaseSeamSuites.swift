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
    }
}
