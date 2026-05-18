import Testing
import Foundation
import GRDB
@testable import LocoKit2

// Step 4c: trip-sample pruning over the temp DB (via the Step 7 seam, since
// pruneSamples() writes to Database.pool). The source documents pruning as
// idempotent — this pins that invariant and that it actually removes
// redundant collinear points.
@Suite(.serialized) final class PruningTests {

    let testDB: TestDatabase

    init() throws {
        testDB = try TestDatabase().installAsSharedPool()
    }

    deinit {
        testDB.tearDown()
    }

    private func sampleCount(_ itemId: String) async throws -> Int {
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

        let original = try await sampleCount(itemId)
        #expect(original == 6)

        // first prune: collinear interior points are redundant -> dropped
        let item1 = try #require(
            try await TimelineItem.fetchItem(itemId: itemId, includeSamples: true)
        )
        try await item1.pruneSamples()
        let afterFirst = try await sampleCount(itemId)
        #expect(afterFirst < original)
        #expect(afterFirst >= 2)            // endpoints always survive

        // second prune on already-pruned data: no further change
        let item2 = try #require(
            try await TimelineItem.fetchItem(itemId: itemId, includeSamples: true)
        )
        try await item2.pruneSamples()
        let afterSecond = try await sampleCount(itemId)
        #expect(afterSecond == afterFirst)  // idempotent
    }
}
