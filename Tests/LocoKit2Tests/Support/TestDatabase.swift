import Foundation
import GRDB
@testable import LocoKit2

/// A clean, isolated, on-disk GRDB database for a single test.
///
/// LocoKit2's production `Database` is a singleton that opens a fixed file in
/// the app container and has no in-memory mode. We don't touch it. Instead we
/// build our own `DatabasePool` against a unique temp-directory file and run
/// the *same* migrations the app runs (registered via the internal
/// `Database` migration methods, exposed through `@testable`). The migration
/// registration closures only touch the `db` they're given, never singleton
/// state, so this is fully isolated from `Database.highlander`.
///
/// Usage (see Support/README.md): make a `@Suite(.serialized) final class`,
/// build a `TestDatabase` in `init()`, and call `tearDown()` from `deinit`.
final class TestDatabase {

    let pool: DatabasePool
    let directoryURL: URL
    var databaseFileURL: URL { directoryURL.appendingPathComponent("test.sqlite") }

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocoKit2Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true
        )

        // computed via directoryURL directly (databaseFileURL accesses self,
        // which isn't allowed until `pool` is also initialized)
        let fileURL = directoryURL.appendingPathComponent("test.sqlite")

        var config = Configuration()
        config.busyMode = .timeout(30)
        pool = try DatabasePool(path: fileURL.path, configuration: config)

        // register and run the exact app migration set, in app order
        var migrator = DatabaseMigrator()
        let database = Database.highlander
        database.addInitialSchema(to: &migrator)
        database.addLastSavedTriggers(to: &migrator)
        database.addEdgeTriggers(to: &migrator)
        database.addSampleTriggers(to: &migrator)
        database.addRTreeTriggers(to: &migrator)
        try migrator.migrate(pool)
    }

    /// Idempotent. Safe to call explicitly and again from `deinit`.
    func tearDown() {
        // close the pool BEFORE unlinking. Removing the sqlite/-wal/-shm
        // files while GRDB still holds their fds is an API violation that
        // SQLite detects ("vnode unlinked while in use"). close() is
        // idempotent enough here (a second close throws and is ignored).
        try? pool.close()
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    deinit {
        tearDown()
    }
}
