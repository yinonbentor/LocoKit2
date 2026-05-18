import Testing
import Foundation
import GRDB
@testable import LocoKit2

// Step 4a: SampleImportProcessor.processBatch over the temp-DB harness.
// processBatch takes a `db` directly, so no singleton seam is needed.
@Suite(.serialized) struct SampleImportProcessorTests {

    @Test func emptyBatchProducesEmptyResultAndNoRows() throws {
        let testDB = try TestDatabase()
        defer { testDB.tearDown() }

        let result = try testDB.pool.write { db in
            try SampleImportProcessor.processBatch(
                samples: [],
                validItemIds: [],
                itemDisabledStates: [:],
                db: db
            )
        }

        #expect(result.orphanCount == 0)
        #expect(result.scenario1Count == 0)
        #expect(result.scenario2Count == 0)
        #expect(result.orphans.isEmpty)
        #expect(result.scenario2.isEmpty)

        let count = try testDB.pool.read { try LocomotionSample.fetchCount($0) }
        #expect(count == 0)
    }

    // Scenario 1: parent item disabled, incoming sample enabled. The sample
    // must be forced to disabled and KEEP its (valid) parent reference. The
    // BEFORE-INSERT disabled_check trigger would abort if processBatch failed
    // to normalize, so a clean commit is itself part of the assertion.
    @Test func itemDisabledSampleEnabledForcesSampleDisabled() throws {
        let testDB = try TestDatabase()
        defer { testDB.tearDown() }

        let itemId = "item-1"
        try testDB.pool.write { db in
            try Fixtures.insertTimelineItemBase(db, id: itemId, disabled: true)
        }

        let sample = Fixtures.makeSample(
            id: "s1", disabled: false, timelineItemId: itemId
        )

        let result = try testDB.pool.write { db in
            try SampleImportProcessor.processBatch(
                samples: [sample],
                validItemIds: [itemId],
                itemDisabledStates: [itemId: true],
                db: db
            )
        }

        #expect(result.scenario1Count == 1)
        #expect(result.orphanCount == 0)
        #expect(result.scenario2Count == 0)

        let stored = try testDB.pool.read { try LocomotionSample.fetchOne($0, key: "s1") }
        #expect(stored?.disabled == true)            // normalized
        #expect(stored?.timelineItemId == itemId)    // reference preserved
    }

    // Scenario 2: parent item enabled, incoming sample disabled. The sample
    // is collected for preserved-parent creation and orphaned from its
    // current parent (timelineItemId nulled), keeping its disabled state.
    @Test func itemEnabledSampleDisabledCollectsAndDetaches() throws {
        let testDB = try TestDatabase()
        defer { testDB.tearDown() }

        let itemId = "item-2"
        let sample = Fixtures.makeSample(
            id: "s2", disabled: true, timelineItemId: itemId
        )

        let result = try testDB.pool.write { db in
            try SampleImportProcessor.processBatch(
                samples: [sample],
                validItemIds: [itemId],
                itemDisabledStates: [itemId: false],
                db: db
            )
        }

        #expect(result.scenario2Count == 1)
        #expect(result.scenario2[itemId]?.count == 1)
        #expect(result.orphanCount == 0)
        #expect(result.scenario1Count == 0)

        let stored = try testDB.pool.read { try LocomotionSample.fetchOne($0, key: "s2") }
        #expect(stored?.timelineItemId == nil)   // detached from current parent
        #expect(stored?.disabled == true)        // disabled state preserved
    }

    // Orphan: sample references an item id not in validItemIds. It is
    // collected under its original id and the reference is nulled for DB
    // compliance, then inserted.
    @Test func unknownParentIsCollectedAsOrphanAndNulled() throws {
        let testDB = try TestDatabase()
        defer { testDB.tearDown() }

        let sample = Fixtures.makeSample(
            id: "s3", timelineItemId: "ghost-item"
        )

        let result = try testDB.pool.write { db in
            try SampleImportProcessor.processBatch(
                samples: [sample],
                validItemIds: [],
                itemDisabledStates: [:],
                db: db
            )
        }

        #expect(result.orphanCount == 1)
        #expect(result.orphans["ghost-item"]?.count == 1)
        #expect(result.scenario1Count == 0)
        #expect(result.scenario2Count == 0)

        let stored = try testDB.pool.read { try LocomotionSample.fetchOne($0, key: "s3") }
        #expect(stored != nil)
        #expect(stored?.timelineItemId == nil)
    }

    // orphanOnlyIfEnabled (legacy importer behavior): a disabled sample with
    // a missing parent is NOT collected as an orphan, but its dangling
    // reference is still nulled and the row still inserted.
    @Test func orphanOnlyIfEnabledSkipsDisabledSampleButStillNulls() throws {
        let testDB = try TestDatabase()
        defer { testDB.tearDown() }

        let sample = Fixtures.makeSample(
            id: "s4", disabled: true, timelineItemId: "ghost-item"
        )

        let result = try testDB.pool.write { db in
            try SampleImportProcessor.processBatch(
                samples: [sample],
                validItemIds: [],
                itemDisabledStates: [:],
                orphanOnlyIfEnabled: true,
                db: db
            )
        }

        #expect(result.orphanCount == 0)        // skipped because disabled
        #expect(result.orphans.isEmpty)

        let stored = try testDB.pool.read { try LocomotionSample.fetchOne($0, key: "s4") }
        #expect(stored != nil)
        #expect(stored?.timelineItemId == nil)  // still nulled for DB compliance
    }
}
