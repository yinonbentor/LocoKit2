# LocoKit2 test target

Tests use Apple's **Swift Testing** framework (`import Testing`, `@Test`,
`#expect`). Run from Xcode (`⌘U`) or:

```
xcodebuild test -scheme LocoKit2 -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

Layout:

- `Support/` — shared helpers: `TestDatabase` (temp-file DB harness).
- `Unit/` — pure-logic tests (no DB, no system frameworks). Fast.
- `Integration/` — tests over a temporary database.
- `System/` — tests of logic fed fabricated CoreLocation/CoreMotion input.
- `Concurrency/` — actor / async patterns.

## Adding a regression test for a reported bug

**Pure-logic bug (most common).** Copy any file in `Unit/`, e.g.
`Unit/StatisticsTests.swift`. One `@Suite struct`, one `@Test func`, drive the
function with the inputs from the bug report, `#expect` the correct result.
No harness, no setup. If the bug isn't fixed yet, wrap the assertion in
`withKnownIssue("…")` so the suite stays green and fails loudly when fixed
(see `CoordinateMathTests.perpendicularFootBeforeStartReturnsDistanceToStart`).

**Bug that needs the database.** Use the `TestDatabase` harness — each
instance is a clean, isolated, migrated temp-file DB:

```swift
@Suite(.serialized) final class MyBugTests {
    let testDB: TestDatabase
    init() throws { testDB = try TestDatabase() }
    deinit { testDB.tearDown() }

    @Test func reproducesBug() throws {
        try testDB.pool.write { db in /* seed rows */ }
        let result = try testDB.pool.read { db in /* exercise code */ }
        #expect(result == expected)
    }
}
```

`@Suite(.serialized)` is required for DB suites (shared global state must not
interleave). `init` per test = fresh DB; `deinit` cleans the temp files.
Target code paths that take a `db`/pool parameter; singleton-bound paths
(`Database.pool`) need an injection seam first — a deferred follow-up, not
done in this stage.

## Deferred tests (blocked on the temp-DB harness)

- **MergeScores classifier-score thresholds (75 / 50 / 25 / 10%) and
  percent-inside buckets.** Prime parameterized-boundary candidates, but the
  logic lives in `private @TimelineActor async` methods reachable only with a
  fully built `TimelineItem` (samples + classifier results). The
  `TestDatabase` harness now exists; the remaining blocker is a
  `TimelineItem`/sample fixture builder. Add these as an Integration suite
  alongside the Step 4 fixtures. `Unit/MergeScoresTests.swift` covers the
  pure `ConsumptionScore` semantics now and points here.

## Known issues (surfaced by tests, not yet triaged)

- **`CLLocationCoordinate2D.perpendicularDistance(to:)` — dead "before start"
  branch.** `alongTrackDistance` is derived from `acos(...) * earthRadius`,
  which is never negative, so the `if alongTrackDistance < 0` branch is
  unreachable. A point projecting *before* a segment's start returns ≈0
  instead of the distance to the start, which can let Douglas-Peucker
  over-simplify such paths. Pinned via `withKnownIssue` in
  `CoordinateMathTests.perpendicularFootBeforeStartReturnsDistanceToStart`;
  that test will fail loudly if the source is ever fixed (delete the wrapper
  then).
