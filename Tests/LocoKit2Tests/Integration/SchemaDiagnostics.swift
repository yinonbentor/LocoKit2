import Testing
import Foundation
import GRDB
@testable import LocoKit2

// TEMPORARY diagnostics — delete once MergeTests/PruningTests are green.
// Prints the migrated schema and pinpoints where the trip path fails.
@Suite(.serialized) struct SchemaDiagnostics {

    @Test func dumpSchemaAndTripPath() throws {
        let testDB = try TestDatabase()
        defer { testDB.tearDown() }

        // 1. every table/trigger the migrations actually created
        let names = try testDB.pool.read { db in
            try String.fetchAll(db, sql: """
                SELECT type || ' ' || name FROM sqlite_master
                WHERE type IN ('table','trigger') ORDER BY type, name
                """)
        }
        print("=== DIAG sqlite_master ===")
        for n in names { print("DIAG  \(n)") }

        // 2. what table names GRDB's records resolve to
        print("DIAG TimelineItemBase.databaseTableName = \(TimelineItemBase.databaseTableName)")
        print("DIAG TimelineItemTrip.databaseTableName = \(TimelineItemTrip.databaseTableName)")
        print("DIAG TimelineItemVisit.databaseTableName = \(TimelineItemVisit.databaseTableName)")
        print("DIAG LocomotionSample.databaseTableName = \(LocomotionSample.databaseTableName)")

        // 3. tableExists under both casings
        try testDB.pool.read { db in
            print("DIAG tableExists TimelineItemTrip = \(try db.tableExists("TimelineItemTrip"))")
            print("DIAG tableExists timelineItemTrip = \(try db.tableExists("timelineItemTrip"))")
            print("DIAG tableExists TimelineItemVisit = \(try db.tableExists("TimelineItemVisit"))")
        }

        // 4. run the exact trip-creation path and capture the precise error
        let track = Fixtures.makeCollinearTrack(count: 3, activityType: .car)
        do {
            try testDB.pool.write { db in
                for s in track { try s.insert(db) }
                let item = try TimelineItem.createItem(
                    from: track, isVisit: false, db: db
                )
                print("DIAG createItem(trip) OK id=\(item.id)")
            }
        } catch {
            print("DIAG createItem(trip) FAILED: \(error)")
        }

        // 5. and the visit path, for comparison with MergeTests
        let vtrack = Fixtures.makeCollinearTrack(count: 2)
        do {
            try testDB.pool.write { db in
                for s in vtrack { try s.insert(db) }
                let item = try TimelineItem.createItem(
                    from: vtrack, isVisit: true, db: db
                )
                print("DIAG createItem(visit) OK id=\(item.id)")
            }
        } catch {
            print("DIAG createItem(visit) FAILED: \(error)")
        }

        #expect(Bool(true)) // diagnostics only; never fails
    }
}
