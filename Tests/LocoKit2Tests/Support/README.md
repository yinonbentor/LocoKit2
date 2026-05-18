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

**Singleton-bound code** (anything that reaches the DB as `Database.pool`,
e.g. `Merge`, pruning) is testable via the injection seam: call
`installAsSharedPool()` so `Database.pool` is routed at the temp pool for
the suite. `tearDown()` resets it (identity-checked, so serialized siblings
can't clobber each other). Always inject *before* the first `Database.pool`
access — touching it uninjected would lazily create the real app database.

```swift
@Suite(.serialized) final class MyMergeTests {
    let testDB: TestDatabase
    init() throws { testDB = try TestDatabase().installAsSharedPool() }
    deinit { testDB.tearDown() }

    @Test func reproducesBug() throws {
        try Database.pool.write { db in /* seed */ }     // -> temp DB
        ...
    }
}
```

The seam itself (`Database.injectedPool`, `internal`, nil in production) is
verified by `Integration/DatabaseInjectionSeamTests.swift`.

## Step 4b / 4c — landed; deeper branches remaining

Built on the Step 7 seam (`installAsSharedPool()`), using
`Fixtures.insertItem` / `makeCollinearTrack`:

- **`Integration/PruningTests.swift` (4c).** Trip-sample pruning:
  redundant collinear points are removed and re-pruning is idempotent
  (the source-documented invariant). *Remaining:* visit pruning, and
  protected-edge-sample survival.
- **`Integration/MergeTests.swift` (4b).** Non-adjacent items score
  `.impossible` and `doIt()` is a safe no-op (guard + write-path safety).
  *Remaining:* the happy-path merge and the explicit circular /
  same-neighbor branches — these need a linked-timeline fixture (items
  with `nextItemId`/`previousItemId` edges, a shared confirmed `Place`,
  and valid date ranges) plus correct merge scoring; deferred as a
  focused follow-up.
- **MergeScores classifier-score thresholds (75 / 50 / 25 / 10%) and
  percent-inside buckets.** Still need a `TimelineItem` with samples +
  classifier results. `Unit/MergeScoresTests.swift` covers the pure
  `ConsumptionScore` semantics now and points here.

Each needs the same prerequisite: a fixture that builds a small linked
`TimelineItem` timeline in the temp DB (via `TimelineItem.createItem(... db:)`
or equivalent). That builder is the next concrete step.

## Known issues (surfaced by tests, not yet triaged)

Full write-ups (root cause, impact, reproduction, suggested fix) live in
[`known-issues/`](known-issues/):

- [BUG-001](known-issues/BUG-001-perpendicular-distance-dead-before-start-branch.md)
  — `perpendicularDistance(to:)` dead "before start" branch
- [BUG-002](known-issues/BUG-002-histogram-probability-nan-single-value.md)
  — `Histogram.probability(for:)` returns `NaN` for single-value data
- [BUG-003](known-issues/BUG-003-chunked-unguarded-size.md)
  — `Array.chunked(into:)` unguarded `size`

Summaries:

- **`Array.chunked(into:)` — unguarded `size`.** A `size` of `0` (or
  negative) is not rejected. On current Swift toolchains the underlying
  `stride(from:to:by:)` yields an empty sequence, so `chunked(into: 0)`
  silently returns `[]` — every element is dropped instead of trapping or
  returning the input as one chunk. There is intentionally no executable
  test (the behaviour is Swift-stride-version-dependent and a trap on some
  toolchain would abort the suite); `ArrayHelpersTests` pins only the
  well-defined `size >= 1` behaviour. A one-line `precondition(size > 0)`
  or an early guard would close this.

- **`CLLocationCoordinate2D.perpendicularDistance(to:)` — dead "before start"
  branch.** `alongTrackDistance` is derived from `acos(...) * earthRadius`,
  which is never negative, so the `if alongTrackDistance < 0` branch is
  unreachable. A point projecting *before* a segment's start returns ≈0
  instead of the distance to the start, which can let Douglas-Peucker
  over-simplify such paths. Pinned via `withKnownIssue` in
  `CoordinateMathTests.perpendicularFootBeforeStartReturnsDistanceToStart`;
  that test will fail loudly if the source is ever fixed (delete the wrapper
  then).
