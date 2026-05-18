# BUG-004 — Merge same-neighbor guard misfires when edges are `nil`

| | |
|---|---|
| **Status** | Open, pinned via `withKnownIssue` |
| **Severity** | Medium (blocks the simplest valid merge; timeline can't consolidate a lone adjacent pair) |
| **Component** | `Sources/LocoKit2/Managers/Merge.swift` |
| **Location** | `Merge.isValid(keeper:betweener:deadman:in:)`, the `else` (no-betweener) branch |
| **Surfaced by** | `DatabaseSeamSuites.MergeTests.twoItemAdjacentMergeShouldBePossible` |

## Summary

Two timeline items that are directly adjacent (`keeper -> deadman`) and have
**no other neighbours** cannot be merged: `Merge.isValid` rejects them as a
"same-neighbor" situation and the merge scores `.impossible`. This is the
simplest possible valid merge, and it is silently blocked.

## Root cause

In the no-betweener `keeper -> deadman` branch:

```swift
if keeper.base.nextItemId == deadman.id {
    if deadman.base.nextItemId == keeper.id { return false }                 // cycle
    if deadman.base.nextItemId == keeper.base.previousItemId {               // <-- here
        Log.error("Merge rejected: would create same-neighbor edges on keeper")
        return false
    }
    return true
}
```

The intent of the second check: after the merge, `keeper` inherits
`deadman.nextItemId`. If that equals `keeper.previousItemId`, the keeper would
end up pointing at the same item on both sides (a degenerate 2-cycle), so the
merge is refused.

The defect: when `deadman` has no following item **and** `keeper` has no
preceding item, both sides are `nil`. In Swift, `Optional.none ==
Optional.none` is `true`, so `deadman.base.nextItemId == keeper.base.previousItemId`
evaluates to `nil == nil == true`. The guard concludes "same neighbor" when in
reality there is *no* neighbor on either side — a perfectly safe merge.

The same `nil == nil` flaw exists in the symmetric `deadman -> keeper` branch
(`deadman.base.previousItemId == keeper.base.nextItemId`) and in both betweener
branches.

## How it is surfaced

`twoItemAdjacentMergeShouldBePossible` builds two visits at the same confirmed
place, linked `K -> D` with no predecessor, and asserts the merge *should* be
possible:

```swift
withKnownIssue("BUG-004: nil == nil same-neighbor guard blocks valid 2-item merge") {
    #expect(merge.score != .impossible)
}
```

`merge.score` is `.impossible` today (guard misfires), so the expectation is
recorded as a known issue. The companion happy-path test
(`keeperConsumesAdjacentDeadmanAtSamePlace`) deliberately adds a predecessor
`P -> K -> D` purely to dodge this bug so the real merge path can be tested.

## Potential impact

`Merge.isValid` gates every merge. A timeline that has been reduced to exactly
two adjacent items with no surrounding items (e.g. early in recording, after
heavy pruning/deletion, or a short isolated segment) cannot consolidate those
two items even when they are the same confirmed place and obviously should
merge. The failure is silent: the merge is simply never offered (`.impossible`),
so duplicate/adjacent items persist. With longer timelines the outer edges are
usually non-nil so the bug is masked, which is why it has gone unnoticed.

## Suggested fix (for triage, not applied here)

Only treat it as a same-neighbor collision when the shared id actually exists:

```swift
if let n = deadman.base.nextItemId, n == keeper.base.previousItemId {
    Log.error("Merge rejected: would create same-neighbor edges on keeper")
    return false
}
```

Apply the equivalent `if let` guard to the other three occurrences
(`deadman -> keeper`, and both betweener branches). Existing non-nil behaviour
is unchanged; only the `nil == nil` false-positive is removed.

## Verifying a fix

Remove the `withKnownIssue` wrapper in
`twoItemAdjacentMergeShouldBePossible`; it should then score non-`.impossible`
and could be extended to assert `doIt()` succeeds (mirroring
`keeperConsumesAdjacentDeadmanAtSamePlace`). The circular-edge and non-adjacent
rejection tests must stay green.
