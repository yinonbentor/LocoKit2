import Testing
import Foundation
@testable import LocoKit2

@Suite struct HistogramTests {

    // MARK: - init?(values:)

    @Test func emptyValuesProducesNil() {
        #expect(Histogram(values: []) == nil)
    }

    @Test func allEqualValuesProduceSingleZeroWidthBin() {
        let h = Histogram(values: [5, 5, 5])
        #expect(h != nil)
        #expect(h?.bins.count == 1)
        #expect(h?.binWidth == 0)
        let bin = h?.bins.first
        #expect(bin?.start == 5)
        #expect(bin?.end == 5)
        #expect(bin?.count == 3)
    }

    // Strong invariant: bucketing must never lose or invent a value, so the
    // sum of all bin counts always equals the input count. Covers the
    // value == maxValue edge case (which is folded into the last bin) and
    // the IQR == 0 bin-width fallback path.
    @Test(arguments: [
        [1.0, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        [0.0, 0, 0, 0, 10],                       // IQR == 0, min != max
        [-5.0, -1, 0, 0.5, 3, 3, 3, 100],
        [1.0, 1, 1, 1, 1, 1, 1, 2],               // value == maxValue edge
    ])
    func totalCountEqualsInputCount(_ values: [Double]) {
        let h = Histogram(values: values)
        #expect(h?.totalCount == values.count)
    }

    // MARK: - derived properties

    @Test func maxCountAndMostCommonBin() {
        // cluster heavily around the low end
        let h = Histogram(values: [0, 0, 0, 0, 0, 1, 2, 9])
        #expect(h != nil)
        #expect(h?.maxCount == h?.bins.map(\.count).max())
        let common = h?.mostCommonBin
        #expect(common != nil)
        #expect(common?.count == h?.maxCount)
        // the densest bin should sit at the low end where the cluster is
        #expect((common?.start ?? 99) < 1)
    }

    @Test func valueRangeSpansFirstStartToLastEnd() {
        let h = Histogram(values: [2, 4, 6, 8, 10])
        let range = h?.valueRange
        #expect(range?.lowerBound == h?.bins.first?.start)
        #expect(range?.upperBound == h?.bins.last?.end)
        #expect(range?.lowerBound == 2)
    }

    @Test func binMiddleAndWidthAreConsistent() {
        let bin = Histogram.Bin(start: 10, end: 20, count: 3)
        #expect(bin.width == 10)
        #expect(bin.middle == 15)
    }

    // MARK: - probability(for:)

    @Test func probabilityIsNilForEmptyHistogram() {
        #expect(Histogram().probability(for: 1) == nil)
    }

    @Test func probabilityIsNilOutsideValueRange() {
        let h = Histogram(values: [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(h?.probability(for: -1000) == nil)
        #expect(h?.probability(for: 1000) == nil)
    }

    @Test func probabilityIsFinitePositiveInsideRange() {
        let h = Histogram(values: [1, 2, 2, 3, 3, 3, 4, 4, 5, 6, 7, 8])
        let p = h?.probability(for: 3)
        #expect(p != nil)
        #expect((p ?? -1) > 0)
        #expect(p?.isFinite == true)
    }

    // KNOWN FAILURE — documents a real bug, intentionally not fixed yet.
    //
    // A single-value (or all-equal) data set yields a histogram with one
    // zero-width bin and totalCount == 1. probability(for:) estimates the SD
    // with `sqrt(weightedSqSum / Double(totalCount - 1))`, i.e. a division by
    // zero when totalCount == 1, which makes the bandwidth and every kernel
    // term NaN. The function therefore returns NaN instead of a finite
    // probability for a value that is squarely inside the (degenerate) range.
    //
    // Pinned via withKnownIssue so the suite stays green while recording the
    // expected (finite) behaviour. Delete the wrapper if the source is fixed.
    @Test func probabilityOnSingleValueHistogramIsFinite() {
        let h = Histogram(values: [10])
        withKnownIssue("KDE divides by totalCount - 1, which is 0 for single-value histograms") {
            let p = h?.probability(for: 10)
            #expect(p?.isFinite == true)
        }
    }

    // MARK: - factory helpers

    @Test func forDurationsNilForEmpty() {
        #expect(Histogram.forDurations(intervals: []) == nil)
    }

    @Test func forTimeOfDayNilForEmpty() {
        #expect(Histogram.forTimeOfDay(dates: []) == nil)
    }

    @Test func forDurationsBucketsIntervals() {
        let h = Histogram.forDurations(intervals: [10, 20, 20, 30, 40, 60, 90, 120])
        #expect(h != nil)
        #expect(h?.totalCount == 8)
    }
}
