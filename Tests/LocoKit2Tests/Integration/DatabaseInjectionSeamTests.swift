import Testing
import Foundation
import CoreLocation
import GRDB
@testable import LocoKit2

// Step 7: verifies the Database injection seam. Production code reaches the
// database as `Database.pool.write { ... }` / `.read { ... }`; this proves
// that, once a test pool is installed, those exact singleton accesses are
// redirected to the temp DB and never the on-disk app database — and that
// teardown fully resets the seam.
//
// NOTE: must inject BEFORE any Database.pool access. Reading Database.pool
// without an injected pool would lazily create the real app database file.
@Suite(.serialized) final class DatabaseInjectionSeamTests {

    let testDB: TestDatabase

    init() throws {
        testDB = try TestDatabase().installAsSharedPool()
    }

    deinit {
        testDB.tearDown()
    }

    @Test func singletonPoolIsRedirectedToTestPool() throws {
        #expect(Database.pool === testDB.pool)
        #expect(Database.highlander.injectedPool === testDB.pool)
    }

    // Exercises the singleton exactly the way production code does, and
    // confirms the write landed in the temp DB (visible via the harness's
    // own handle to the same pool).
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
        // tearDown is idempotent; deinit will call it again safely
        testDB.tearDown()
    }
}
