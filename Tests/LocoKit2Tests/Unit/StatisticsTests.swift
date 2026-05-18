import Testing
import Foundation
@testable import LocoKit2

@Suite struct StatisticsTests {

    private let tol = 1e-9

    // MARK: - mean()

    @Test func meanOfEmptyIsZero() {
        #expect([Double]().mean() == 0)
    }

    @Test func meanOfValues() {
        #expect(abs([1.0, 2, 3, 4].mean() - 2.5) < tol)
    }

    @Test func meanOfSingleIsThatValue() {
        #expect([42.0].mean() == 42)
    }

    // MARK: - standardDeviation()

    @Test func standardDeviationOfEmptyIsZero() {
        #expect([Double]().standardDeviation() == 0)
    }

    @Test func standardDeviationOfSingleIsZero() {
        // count <= 1 guard: not enough data for a sample SD
        #expect([5.0].standardDeviation() == 0)
    }

    @Test func standardDeviationUsesSampleDenominator() {
        // [1,2,3,4,5]: mean 3, sum sq diff 10, sample variance 10/(5-1)=2.5
        #expect(abs([1.0, 2, 3, 4, 5].standardDeviation() - sqrt(2.5)) < tol)
    }

    // MARK: - meanAndStandardDeviation()

    @Test func meanAndStandardDeviationTogether() {
        let result = [2.0, 4, 4, 4, 5, 5, 7, 9].meanAndStandardDeviation()
        #expect(abs(result.mean - 5) < tol)
        // sum sq diff 32, sample variance 32/(8-1)
        #expect(abs(result.standardDeviation - sqrt(32.0 / 7.0)) < tol)
    }

    @Test func meanAndStandardDeviationOfSingle() {
        let result = [42.0].meanAndStandardDeviation()
        #expect(result.mean == 42)
        #expect(result.standardDeviation == 0)
    }

    @Test func meanAndStandardDeviationOfEmpty() {
        let result = [Double]().meanAndStandardDeviation()
        #expect(result.mean == 0)
        #expect(result.standardDeviation == 0)
    }

    // MARK: - sum()

    @Test func sumOfEmptyIsZero() {
        #expect([Int]().sum() == 0)
    }

    @Test func sumOfValues() {
        #expect([1, 2, 3, 4].sum() == 10)
    }

    // MARK: - mode()

    @Test func modeReturnsMostCommonElement() {
        #expect([1, 2, 2, 3, 3, 3].mode() == 3)
    }

    @Test func modeOfEmptyIsNil() {
        #expect([Int]().mode() == nil)
    }

    // MARK: - clamped(min:max:)

    @Test(arguments: [
        (value: 5.0, expected: 5.0),    // within range
        (value: -1.0, expected: 0.0),   // below min
        (value: 11.0, expected: 10.0),  // above max
    ])
    func clampedBoundsValue(_ args: (value: Double, expected: Double)) {
        #expect(args.value.clamped(min: 0, max: 10) == args.expected)
    }

    @Test func clampMutatesInPlace() {
        var v = 99.0
        v.clamp(min: 0, max: 10)
        #expect(v == 10)
    }
}
