# BUG-003 — `Array.chunked(into:)` has an unguarded `size` parameter

| | |
|---|---|
| **Status** | Open, documented only (intentionally not executed) |
| **Severity** | Low–Medium (silent data loss on misuse; toolchain-dependent) |
| **Component** | `Sources/LocoKit2/Extensions/Foundation+LocoKit.swift` |
| **Location** | `Array.chunked(into:)`, lines ~14–18 |
| **Surfaced by** | Code review during `Unit/ArrayHelpersTests` authoring |

## Summary

`Array.chunked(into:)` splits an array into sub-arrays of length `size`. The
`size` parameter is **not validated**. A `size` of `0` (or negative) does not
trap or get rejected — on current Swift toolchains it silently returns `[]`,
discarding every element, instead of failing fast or degrading sensibly.

## Root cause

```swift
func chunked(into size: Int) -> [[Element]] {
    return stride(from: 0, to: count, by: size).map {
        Array(self[$0 ..< Swift.min($0 + size, count)])
    }
}
```

The implementation delegates bounds to `stride(from: 0, to: count, by: size)`.
With `size == 0` (or negative) and a non-empty array, `stride(from:to:by:)`
produces an **empty sequence** on current Swift standard-library versions (the
stride never advances toward `to`, so iteration yields nothing). `.map` over an
empty sequence returns `[]`. The result: `[1, 2, 3].chunked(into: 0) == []` —
all three elements vanish with no error.

There is no `precondition(size > 0)` and no early-return guard.

## How it is surfaced

Found by inspection while writing `Unit/ArrayHelpersTests.swift`. It is
**deliberately not exercised by an executable test**:

- the exact behaviour of `stride(from:to:by:)` with a zero/negative stride is
  not contractually guaranteed and has varied across Swift standard-library
  versions (empty sequence on current toolchains; a hard trap is plausible on
  others)
- a stride trap inside a test would `fatalError`-abort the **entire test
  process**, not record a catchable issue (`withKnownIssue` cannot trap
  Swift runtime preconditions), making the suite brittle

`ArrayHelpersTests` therefore pins only the well-defined `size >= 1` behaviour
(remainder, exact multiple, `size >= count`, empty input). This bug is recorded
in `Support/README.md` and here.

## Potential impact

Impact depends entirely on call sites. `chunked(into:)` is used to batch work
(e.g. splitting samples/records into write or processing batches). The danger is
a **silent empty result**: if a batch size is ever computed (rather than a
literal) and can reach `0` — an empty-derived size, an integer division that
floors to zero, a misconfigured constant — then:

- the loop over chunks does zero iterations
- the operation appears to "succeed" (no error thrown) while processing **no
  data at all**
- e.g. an import/migration/prune that quietly becomes a no-op

With literal, always-positive sizes (the current usage) there is no impact
today. The risk is latent: a future caller passing a dynamic size, with no
compiler or runtime signal that `0` is invalid.

## Suggested fix (for triage, not applied here)

Fail fast, or define the degenerate case explicitly:

```swift
func chunked(into size: Int) -> [[Element]] {
    precondition(size > 0, "chunk size must be positive")
    return stride(from: 0, to: count, by: size).map {
        Array(self[$0 ..< Swift.min($0 + size, count)])
    }
}
```

(or, if a non-trapping contract is preferred, `guard size > 0 else { return
isEmpty ? [] : [self] }` — return the whole array as one chunk). The choice is a
product/API decision for the maintainer; the key point is that `size <= 0`
should not silently drop data.

## Verifying a fix

Add an executable test once the contract is defined:

```swift
// if the fix uses precondition(), assert the positive path is unchanged and
// document that size <= 0 is now a programmer error (not unit-testable safely).

// if the fix uses a guard with a defined return, then:
@Test func chunkedWithNonPositiveSizeDoesNotDropData() {
    #expect([1, 2, 3].chunked(into: 0) == [[1, 2, 3]])   // or whatever contract is chosen
    #expect([1, 2, 3].chunked(into: -1) == [[1, 2, 3]])
}
```

and keep the existing `size >= 1` assertions in `ArrayHelpersTests` green.
