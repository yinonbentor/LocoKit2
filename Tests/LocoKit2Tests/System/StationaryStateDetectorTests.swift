import Testing
import Foundation
import CoreLocation
@testable import LocoKit2

// Step 5 (Tier 3): drive StationaryStateDetector with fabricated CLLocation
// input. No system framework is mocked — we feed plain locations and assert
// our own decision logic. Also serves as an actor/async pattern example
// (the suite is async and awaits actor-isolated calls).
@Suite struct StationaryStateDetectorTests {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func emptyDetectorIsUncertain() async {
        let detector = StationaryStateDetector()
        let state = await detector.currentState()
        #expect(state.movingState == .uncertain)
        #expect(state.n == 0)
    }

    @Test func singleSlowSampleIsStationary() async {
        let detector = StationaryStateDetector()
        await detector.add(location: Fixtures.makeMovingLocation(speed: 0, timestamp: t0))
        let state = await detector.currentState()
        #expect(state.movingState == .stationary)
        #expect(state.n == 1)
    }

    @Test func singleFastSampleIsMoving() async {
        let detector = StationaryStateDetector()
        await detector.add(location: Fixtures.makeMovingLocation(speed: 12, timestamp: t0))
        let state = await detector.currentState()
        #expect(state.movingState == .moving)
    }

    @Test func multipleSlowAccurateSamplesAreStationary() async {
        let detector = StationaryStateDetector()
        for i in 0..<5 {
            await detector.add(location: Fixtures.makeMovingLocation(
                horizontalAccuracy: 10, speed: 0.1,
                timestamp: t0.addingTimeInterval(Double(i))
            ))
        }
        let state = await detector.currentState()
        #expect(state.movingState == .stationary)
        #expect(state.n > 1)
    }

    @Test func multipleFastAccurateSamplesAreMoving() async {
        let detector = StationaryStateDetector()
        for i in 0..<5 {
            await detector.add(location: Fixtures.makeMovingLocation(
                horizontalAccuracy: 10, speed: 15,
                timestamp: t0.addingTimeInterval(Double(i))
            ))
        }
        let state = await detector.currentState()
        #expect(state.movingState == .moving)
    }

    @Test func poorAccuracyIsUncertain() async {
        let detector = StationaryStateDetector()
        for i in 0..<3 {
            await detector.add(location: Fixtures.makeMovingLocation(
                horizontalAccuracy: 500, speed: 0,
                timestamp: t0.addingTimeInterval(Double(i))
            ))
        }
        let state = await detector.currentState()
        #expect(state.movingState == .uncertain)
    }

    // The raw speed=-1 override: Kalman-smoothed samples say "moving" (fast,
    // accurate), but a high rate of raw fixes with invalid velocity means iOS
    // is honestly reporting "I don't know", which only happens when actually
    // stationary — so the result is overridden to .stationary.
    @Test func highRawInvalidVelocityRateOverridesMovingToStationary() async {
        let detector = StationaryStateDetector()
        for i in 0..<4 {
            let ts = t0.addingTimeInterval(Double(i))
            await detector.add(location: Fixtures.makeMovingLocation(
                horizontalAccuracy: 10, speed: 15, timestamp: ts
            ))
            // plain makeCLLocation has speedAccuracy -1 -> invalidVelocity true
            await detector.addRaw(location: Fixtures.makeCLLocation(timestamp: ts))
        }
        let state = await detector.currentState()
        #expect(state.movingState == .stationary)         // overridden
        #expect((state.rawInvalidVelocityRate ?? 0) >= 0.5)
    }

    @Test func lowRawInvalidVelocityRateDoesNotOverride() async {
        let detector = StationaryStateDetector()
        for i in 0..<4 {
            let ts = t0.addingTimeInterval(Double(i))
            await detector.add(location: Fixtures.makeMovingLocation(
                horizontalAccuracy: 10, speed: 15, timestamp: ts
            ))
            // valid-velocity raws -> low invalidVelocity rate
            await detector.addRaw(location: Fixtures.makeMovingLocation(
                speed: 15, timestamp: ts
            ))
        }
        let state = await detector.currentState()
        #expect(state.movingState == .moving)             // not overridden
        #expect((state.rawInvalidVelocityRate ?? 1) < 0.5)
    }
}
