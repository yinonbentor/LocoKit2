import Testing
import Foundation
@testable import LocoKit2

@Suite struct ArrayHelpersTests {

    // MARK: - chunked(into:)
    //
    // Only the well-defined size >= 1 behaviour is exercised. The `size`
    // parameter is unguarded and `chunked(into: 0)` / negative sizes have
    // Swift-stride-version-dependent behaviour (silent empty result rather
    // than a trap on current toolchains) — see Support/README.md known
    // issues. It is deliberately not called here: pinning version-dependent
    // semantics would make the suite brittle, and a stride trap on some
    // toolchain would abort the whole run.

    @Test func chunkedSplitsWithRemainder() {
        #expect([1, 2, 3, 4, 5].chunked(into: 2) == [[1, 2], [3, 4], [5]])
    }

    @Test func chunkedExactMultiple() {
        #expect([1, 2, 3, 4].chunked(into: 2) == [[1, 2], [3, 4]])
    }

    @Test func chunkedSizeAtOrAboveCountIsSingleChunk() {
        #expect([1, 2, 3].chunked(into: 3) == [[1, 2, 3]])
        #expect([1, 2, 3].chunked(into: 10) == [[1, 2, 3]])
    }

    @Test func chunkedEmptyIsEmpty() {
        #expect([Int]().chunked(into: 3) == [])
    }

    // MARK: - second / secondToLast / penultimate

    @Test func secondElement() {
        #expect([Int]().second == nil)
        #expect([1].second == nil)
        #expect([1, 2, 3].second == 2)
    }

    @Test func secondToLastAndPenultimate() {
        #expect([Int]().secondToLast == nil)
        #expect([1].secondToLast == nil)
        #expect([1, 2, 3].secondToLast == 2)
        #expect([1, 2, 3].penultimate == [1, 2, 3].secondToLast)
    }

    // MARK: - safe subscript

    @Test func safeSubscriptBoundsCheck() {
        let a = [10, 20, 30]
        #expect(a[safe: 0] == 10)
        #expect(a[safe: 2] == 30)
        #expect(a[safe: 3] == nil)
        #expect(a[safe: -1] == nil)
        #expect([Int]()[safe: 0] == nil)
    }
}
