import Testing
import Foundation
import CoreLocation
import GRDB
@testable import LocoKit2

// Proves the temp-DB harness before any real integration tests are built on
// it: migrations apply, a row round-trips, triggers fire, and the temp file
// is created then fully cleaned up with no leftovers.
@Suite(.serialized) struct TestDatabaseSmokeTests {

    @Test func harnessMigratesRoundTripsAndCleansUp() throws {
        let testDB = try TestDatabase()

        // file actually exists on disk after migration
        #expect(FileManager.default.fileExists(atPath: testDB.databaseFileURL.path))

        // schema applied: a known table from the initial migration is present
        let hasPlaceTable = try testDB.pool.read { db in
            try db.tableExists("Place")
        }
        #expect(hasPlaceTable)

        // insert + read back through GRDB record types
        let place = Place(
            coordinate: CLLocationCoordinate2D(latitude: 1.0, longitude: 2.0),
            name: "Smoke Test Place"
        )
        try testDB.pool.write { db in try place.insert(db) }

        let fetched = try testDB.pool.read { db in
            try Place.fetchOne(db, key: place.id)
        }
        #expect(fetched?.name == "Smoke Test Place")

        // RTree trigger fired: Place_AFTER_INSERT back-fills rtreeId
        #expect(fetched?.rtreeId != nil)

        // explicit teardown removes everything, no leftovers
        let dir = testDB.directoryURL
        testDB.tearDown()
        #expect(!FileManager.default.fileExists(atPath: dir.path))

        // teardown is idempotent
        testDB.tearDown()
    }

    @Test func eachInstanceIsIsolated() throws {
        let a = try TestDatabase()
        let b = try TestDatabase()
        defer { a.tearDown(); b.tearDown() }

        #expect(a.databaseFileURL.path != b.databaseFileURL.path)

        let place = Place(
            coordinate: CLLocationCoordinate2D(latitude: 0.1, longitude: 0.2),
            name: "Only In A"
        )
        try a.pool.write { db in try place.insert(db) }

        let countInB = try b.pool.read { db in try Place.fetchCount(db) }
        #expect(countInB == 0)   // b must not see a's writes
    }
}
