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
