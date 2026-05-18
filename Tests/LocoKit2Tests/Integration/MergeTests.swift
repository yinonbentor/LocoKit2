import Testing
import Foundation
import GRDB
@testable import LocoKit2

// Step 4b: Merge over the temp DB (via the Step 7 seam — Merge.doIt() writes
// to Database.pool). Focuses on the guard logic: two items that are not in a
// valid adjacency pattern must score .impossible and doIt() must be a safe
// no-op (nothing deleted). The deep happy-path / same-neighbor branches need
// a richer linked-timeline fixture and are noted in Support/README.md.
@Suite(.serialized) final class MergeTests {

    let testDB: TestDatabase

    init() throws {
        testDB = try TestDatabase().installAsSharedPool()
    }

    deinit {
        testDB.tearDown()
    }

    @Test @TimelineActor
    func nonAdjacentItemsCannotMergeAndDoItIsANoOp() async throws {
        // two independent visits with no edges linking them
        let (idA, idB) = try testDB.pool.write { db -> (String, String) in
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

        // not adjacent -> isValid() fails -> score is impossible
        #expect(merge.score == .impossible)

        // doIt() must bail safely and change nothing
        let result = await merge.doIt()
        #expect(result == nil)

        let (aDeleted, bDeleted) = try testDB.pool.read { db -> (Bool, Bool) in
            let a = try TimelineItemBase.fetchOne(db, key: idA)
            let b = try TimelineItemBase.fetchOne(db, key: idB)
            return (a?.deleted ?? true, b?.deleted ?? true)
        }
        #expect(aDeleted == false)
        #expect(bDeleted == false)
    }
}
