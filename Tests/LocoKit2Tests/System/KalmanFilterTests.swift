import Testing
import Foundation
import CoreLocation
@testable import LocoKit2

// Step 5 (Tier 3): drive the KalmanFilter actor with hand-built CLLocation
// sequences. The core invariant is "smoothed output stays finite and
// plausible" — no NaN under first-fix, steady input, time gaps, poor
// accuracy, or unusable coordinates. Doubles as the Tier 4 actor/async
// pattern (async suite awaiting an actor).
@Suite struct KalmanFilterTests {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let lat = -33.8688
    private let lon = 151.2093

    private func expectFinite(_ loc: CLLocation) {
        #expect(loc.coordinate.latitude.isFinite)
        #expect(loc.coordinate.longitude.isFinite)
        #expect(loc.horizontalAccuracy.isFinite)
        #expect(loc.speed.isFinite)
        #expect(loc.course.isFinite)
    }

    @Test func firstFixSeedsEstimateToThatCoordinate() async {
        let kalman = KalmanFilter()
        await kalman.add(location: Fixtures.makeCLLocation(
            latitude: lat, longitude: lon, timestamp: t0
        ))
        let est = await kalman.currentEstimatedLocation()
        #expect(abs(est.coordinate.latitude - lat) < 1e-9)
        #expect(abs(est.coordinate.longitude - lon) < 1e-9)
        #expect(est.horizontalAccuracy > 0)
        expectFinite(est)
    }

    @Test func steadyInputStaysNearThatCoordinate() async {
        let kalman = KalmanFilter()
        for i in 0..<10 {
            await kalman.add(location: Fixtures.makeCLLocation(
                latitude: lat, longitude: lon, horizontalAccuracy: 10,
                timestamp: t0.addingTimeInterval(Double(i))
            ))
        }
        let est = await kalman.currentEstimatedLocation()
        // a steady stream at one point must not drift far from it
        #expect(abs(est.coordinate.latitude - lat) < 1e-3)
        #expect(abs(est.coordinate.longitude - lon) < 1e-3)
        expectFinite(est)
    }

    @Test func largeTimeGapProducesNoNaN() async {
        let kalman = KalmanFilter()
        await kalman.add(location: Fixtures.makeCLLocation(
            latitude: lat, longitude: lon, timestamp: t0
        ))
        // hour-long gap then another fix
        await kalman.add(location: Fixtures.makeCLLocation(
            latitude: lat + 0.01, longitude: lon + 0.01,
            timestamp: t0.addingTimeInterval(3600)
        ))
        let est = await kalman.currentEstimatedLocation()
        expectFinite(est)
    }

    @Test func poorAccuracyProducesNoNaN() async {
        let kalman = KalmanFilter()
        for i in 0..<5 {
            await kalman.add(location: Fixtures.makeCLLocation(
                latitude: lat, longitude: lon, horizontalAccuracy: 5000,
                timestamp: t0.addingTimeInterval(Double(i))
            ))
        }
        let est = await kalman.currentEstimatedLocation()
        expectFinite(est)
        #expect(est.horizontalAccuracy > 0)
    }

    @Test func unusableCoordinateIsIgnored() async {
        let kalman = KalmanFilter()
        // null island is not usable -> add() must early-return and not seed
        await kalman.add(location: Fixtures.makeCLLocation(
            latitude: 0, longitude: 0, timestamp: t0
        ))
        // first *usable* fix should still seed the estimate exactly
        await kalman.add(location: Fixtures.makeCLLocation(
            latitude: lat, longitude: lon,
            timestamp: t0.addingTimeInterval(1)
        ))
        let est = await kalman.currentEstimatedLocation()
        #expect(abs(est.coordinate.latitude - lat) < 1e-9)
        #expect(abs(est.coordinate.longitude - lon) < 1e-9)
        expectFinite(est)
    }

    @Test func movingInputYieldsFiniteCourseAndSpeed() async {
        let kalman = KalmanFilter()
        for i in 0..<6 {
            await kalman.add(location: Fixtures.makeMovingLocation(
                latitude: lat + Double(i) * 0.0001,
                longitude: lon,
                course: 0, speed: 11,
                timestamp: t0.addingTimeInterval(Double(i))
            ))
        }
        let est = await kalman.currentEstimatedLocation()
        expectFinite(est)
        #expect(est.speed >= 0)
        #expect(est.course >= 0 && est.course < 360)
    }
}
