# LocoKit2 test target

Tests use Apple's **Swift Testing** framework (`import Testing`, `@Test`,
`#expect`). Run from Xcode (`⌘U`) or:

```
xcodebuild test -scheme LocoKit2 -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

Layout:

- `Support/` — shared builders (`Fixtures`) and the DB harness (added in a
  later step).
- `Unit/` — pure-logic tests (no DB, no system frameworks). Fast.
- `Integration/` — tests over a temporary database.
- `System/` — tests of logic fed fabricated CoreLocation/CoreMotion input.
- `Concurrency/` — actor / async patterns.

> The "how to add a regression test for a reported bug" recipe will be filled
> in here once the test suites and DB harness are in place.

## Deferred tests (blocked on the temp-DB harness)

- **MergeScores classifier-score thresholds (75 / 50 / 25 / 10%) and
  percent-inside buckets.** Prime parameterized-boundary candidates, but the
  logic lives in `private @TimelineActor async` methods reachable only with a
  fully built `TimelineItem` (samples + classifier results). Add these as an
  Integration suite once `Support/TestDatabase.swift` (Step 3) exists.
  `Unit/MergeScoresTests.swift` covers the pure `ConsumptionScore` semantics
  now and carries a pointer to this note.

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
