# BUG-001 — `perpendicularDistance(to:)` "before start" branch is dead code

| | |
|---|---|
| **Status** | Open, pinned via `withKnownIssue` |
| **Severity** | Medium (silent path-geometry error; no crash) |
| **Component** | `Sources/LocoKit2/Extensions/CoreLocation+LocoKit.swift` |
| **Location** | `CLLocationCoordinate2D.perpendicularDistance(to:)`, lines ~100–107 |
| **Surfaced by** | `Unit/CoordinateMathTests.perpendicularFootBeforeStartReturnsDistanceToStart` |

## Summary

`perpendicularDistance(to:)` computes the distance from a point to a great-circle
segment. It has three intended cases:

1. perpendicular foot **before** the segment start → return distance to start
2. perpendicular foot **beyond** the segment end → return distance to end
3. perpendicular foot **within** the segment → return cross-track distance

Case 1 is **unreachable dead code**. A point that projects behind the segment
start is handled by case 3 instead, returning a near-zero cross-track distance
rather than the true (large) distance to the start point.

## Root cause

```swift
let alongTrackAngle = acos(cos(delta13) / cos(crossTrackAngle))
let alongTrackDistance = alongTrackAngle * earthRadius   // line ~100

if alongTrackDistance < 0 {                               // line ~104  <-- never true
    let distanceToStart = delta13 * earthRadius
    return distanceToStart
} else if alongTrackDistance > totalDistance {
    ...
}
```

`alongTrackDistance = acos(...) * earthRadius`. `acos` always returns a value in
`[0, π]`, and `earthRadius` is a positive constant (`6_371_000`). The product is
therefore **always ≥ 0**, so `alongTrackDistance < 0` can never be true and the
"before start" branch never executes.

The correct test for "foot falls before the start" is a **signed** along-track
distance (the sign comes from `cos(theta13 - theta12)`), or an explicit bearing
comparison. The current code threw the sign away by taking `acos`, which is
non-negative by definition.

## How it is surfaced

`Unit/CoordinateMathTests.swift`:

```swift
@Test func perpendicularFootBeforeStartReturnsDistanceToStart() {
    let line = (CLLocationCoordinate2D(latitude: 0, longitude: 0),
                CLLocationCoordinate2D(latitude: 0, longitude: 1))
    let before = CLLocationCoordinate2D(latitude: 0, longitude: -0.5)
    withKnownIssue("perpendicularDistance 'before start' branch is unreachable dead code") {
        // 0.5° along the equator ≈ 55,596 m
        #expect(abs(before.perpendicularDistance(to: line) - 55596.5) < 50)
    }
}
```

A point 0.5° **west** of the start of an eastward equatorial segment is ~55.6 km
"before" the start. The correct answer is ~55,596 m. The function instead
returns ≈0 (it treats the point as essentially on the line, because its
cross-track offset is ~0). The assertion is wrapped in `withKnownIssue`, so the
suite stays green today and will **fail loudly** if the source is ever fixed —
that failure is the signal to delete the wrapper.

## Potential impact

`perpendicularDistance(to:)` is the point-to-segment metric used by the
Douglas–Peucker path simplifier (`PathSimplifier.swift`). Douglas–Peucker keeps
a point only if its distance from the candidate segment exceeds `epsilon`.

When an intermediate point projects *before* its segment's start (common at
sharp direction reversals — e.g. an out-and-back, a U-turn, a switchback, GPS
jitter that briefly doubles back), the function under-reports its distance as
~0 instead of the true large value. Douglas–Peucker then **discards a point it
should have kept**, over-simplifying the path:

- out-and-back legs can collapse toward a straight line
- hairpins / switchbacks lose their apex
- recorded trip geometry and derived distance can be subtly shortened

It is silent: no crash, no log, just slightly-wrong simplified geometry that is
hard to notice without specifically looking for it.

## Suggested fix (for triage, not applied here)

Compute a *signed* along-track distance and compare against `0` and
`totalDistance`, e.g. keep the sign via `cos(theta13 - theta12)`:

```swift
let signedAlong = delta13 * cos(theta13 - theta12) * earthRadius
if signedAlong < 0 { return delta13 * earthRadius }                 // before start
if signedAlong > totalDistance { return delta23 * earthRadius }     // beyond end
return crossTrackDistance
```

Any fix must keep the existing "beyond end" and "within segment" results, which
are correct today and covered by sibling tests.

## Verifying a fix

Remove the `withKnownIssue` wrapper in
`perpendicularFootBeforeStartReturnsDistanceToStart` and confirm it passes,
alongside the existing `perpendicularFootBeyondEndReturnsDistanceToEnd` and
within-segment cases, plus the `PathSimplifierTests` suite (to confirm no
regression in the common in-segment path).
