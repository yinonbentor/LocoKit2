# BUG-002 — `Histogram.probability(for:)` returns `NaN` for single-value data

| | |
|---|---|
| **Status** | Open, pinned via `withKnownIssue` |
| **Severity** | Medium (poisons probability comparisons with `NaN`) |
| **Component** | `Sources/LocoKit2/Models/Histogram.swift` |
| **Location** | `Histogram.probability(for:)`, line ~123 |
| **Surfaced by** | `Unit/HistogramTests.probabilityOnSingleValueHistogramIsFinite` |

## Summary

`Histogram.probability(for:)` performs a kernel-density estimate to return a
smoothed probability for a value. For a histogram built from a **single value**
(or any data set where every value is identical), it returns `NaN` instead of a
finite probability, even though the queried value is squarely inside the
histogram's (degenerate) range.

## Root cause

When all input values are equal, `Histogram.init?(values:)` deliberately creates
a single zero-width bin with `count == values.count`:

```swift
if minValue == maxValue {
    bins = [Bin(start: minValue, end: minValue, count: values.count)]
    return
}
```

For a single value, `totalCount == 1`. Inside `probability(for:)`:

```swift
let weightedSqSum = bins.reduce(0.0) { ... }              // == 0 (one bin, mean == middle)
let sd = sqrt(weightedSqSum / Double(totalCount - 1))     // line ~123: 0.0 / 0.0  -> NaN
```

`totalCount - 1 == 0`, and `weightedSqSum == 0`, so this is `sqrt(0.0 / 0.0)` =
`sqrt(NaN)` = `NaN`. The `NaN` then propagates:

- bandwidth `h = max(binWidth, sd * pow(...))` → `binWidth` is also `0` for a
  zero-width bin, so `h` ends up `0` (or `NaN`)
- the kernel exponent `z = (value - bin.middle) / h` → `0 / 0` = `NaN`
- the returned `kernelSum / normalizationFactor` = `NaN`

The sample-variance denominator (`totalCount - 1`, i.e. Bessel's correction) is
correct for multi-sample data but undefined for `n == 1`, and the single-bin
degenerate case is never special-cased.

## How it is surfaced

`Unit/HistogramTests.swift`:

```swift
@Test func probabilityOnSingleValueHistogramIsFinite() {
    let h = Histogram(values: [10])
    withKnownIssue("KDE divides by totalCount - 1, which is 0 for single-value histograms") {
        let p = h?.probability(for: 10)
        #expect(p?.isFinite == true)
    }
}
```

`probability(for: 10)` on a histogram of `[10]` returns `NaN` (not `nil`, not a
finite number). The expectation that the result `.isFinite` fails, recorded as a
known issue. The non-single-value path is covered and passing by
`probabilityIsFinitePositiveInsideRange`.

## Potential impact

`Histogram` backs `Place` visit statistics — `arrivalTimes`, `leavingTimes`,
`visitDurations`, `occupancyTimes` (see `Place.swift`). `probability(for:)` is
used to score how typical a given time/duration is for a place.

A place with **exactly one recorded visit** (or many visits that all share an
identical bucketed value) produces a single-value histogram. Any
`probability(for:)` query against it returns `NaN`. `NaN` is pathological in
comparisons — `NaN > x`, `NaN < x`, and `NaN == x` are all `false` — so any
ranking, thresholding, or "best place" selection that compares these
probabilities can:

- silently rank a brand-new place last (or arbitrarily), regardless of input
- make `max(by:)` / sort results order-dependent and unstable
- defeat threshold gates (`probability > someCutoff` is always `false`)

New or rarely-visited places are exactly the ones most affected, and the failure
is silent (no crash, no log).

## Suggested fix (for triage, not applied here)

Special-case the degenerate distribution before the KDE math. Options:

- if `totalCount <= 1` or all bins collapse to one zero-width bin, return a
  defined probability (e.g. `1.0` when `value` equals the single observed value
  and `0.0`/`nil` otherwise), or
- guard the SD denominator: `let denom = max(1, totalCount - 1)` and floor the
  bandwidth `h` with a sensible minimum so the kernel stays finite.

Any fix must preserve the existing multi-sample KDE output (covered by
`probabilityIsFinitePositiveInsideRange` and the range/`nil` tests).

## Verifying a fix

Remove the `withKnownIssue` wrapper in
`probabilityOnSingleValueHistogramIsFinite`; it should pass (finite, and ideally
a sensible value). Re-run the rest of `HistogramTests` to confirm the
multi-sample KDE and range handling are unchanged.
