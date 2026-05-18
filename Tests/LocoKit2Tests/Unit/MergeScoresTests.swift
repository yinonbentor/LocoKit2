import Testing
import Foundation
@testable import LocoKit2

@Suite struct MergeScoresTests {

    // MARK: - ConsumptionScore semantics

    // ConsumptionScore is the public vocabulary the whole merge system speaks
    // in. Its raw values encode strength ordering (impossible = 0 ... perfect
    // = 5) and are persisted/compared as Ints, so pin them.
    @Test func rawValuesEncodeStrengthOrdering() {
        #expect(ConsumptionScore.impossible.rawValue == 0)
        #expect(ConsumptionScore.veryLow.rawValue == 1)
        #expect(ConsumptionScore.low.rawValue == 2)
        #expect(ConsumptionScore.medium.rawValue == 3)
        #expect(ConsumptionScore.high.rawValue == 4)
        #expect(ConsumptionScore.perfect.rawValue == 5)
    }

    @Test func strongerScoresHaveHigherRawValue() {
        let ascending: [ConsumptionScore] = [
            .impossible, .veryLow, .low, .medium, .high, .perfect
        ]
        let raws = ascending.map(\.rawValue)
        #expect(raws == raws.sorted())
        #expect(Set(raws).count == raws.count)   // no duplicate ranks
    }

    @Test func roundTripsThroughRawValue() {
        for score in [ConsumptionScore.impossible, .veryLow, .low,
                      .medium, .high, .perfect] {
            #expect(ConsumptionScore(rawValue: score.rawValue) == score)
        }
        #expect(ConsumptionScore(rawValue: 6) == nil)
        #expect(ConsumptionScore(rawValue: -1) == nil)
    }

    // MARK: - Deferred: classifier-score threshold mapping
    //
    // The 75 / 50 / 25 / 10 percentage thresholds in
    // MergeScores.consumptionScoreFor(trip:toConsumeTrip:) — and the
    // percent-inside buckets in the visit<-trip path — are exactly the kind
    // of boundary logic worth parameterized tests (74 vs 75 vs 76, etc).
    //
    // They are intentionally NOT tested here: that code is `private`,
    // `@TimelineActor`-isolated, `async`, and reachable only with a fully
    // built TimelineItem (samples + classifierResults). Driving it requires
    // the temp-DB harness from Step 3 of the test plan. Adding these belongs
    // in an Integration suite once the harness exists; see Support/README.md.
}
