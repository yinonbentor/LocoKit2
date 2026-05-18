import Testing
import Foundation
import CoreLocation
@testable import LocoKit2

@Suite struct WeightedCenterTests {

    private let tol = 1e-6

    private func location(
        lat: Double, lon: Double, accuracy: CLLocationAccuracy = 10
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            timestamp: Date()
        )
    }

    @Test func emptyIsNil() {
        #expect([CLLocation]().weightedCenter() == nil)
    }

    @Test func singleReturnsItsCoordinate() {
        let c = [location(lat: 1.5, lon: 2.5)].weightedCenter()
        #expect(c != nil)
        #expect(abs((c?.latitude ?? 0) - 1.5) < tol)
        #expect(abs((c?.longitude ?? 0) - 2.5) < tol)
    }

    @Test func nullIslandIsFilteredOut() {
        // one null-island point + one real -> only the real one is usable,
        // so the single-location path returns it exactly
        let locs = [location(lat: 0, lon: 0), location(lat: 3.0, lon: 4.0)]
        let c = locs.weightedCenter()
        #expect(abs((c?.latitude ?? 0) - 3.0) < tol)
        #expect(abs((c?.longitude ?? 0) - 4.0) < tol)
    }

    @Test func identicalPointsReturnSameCoordinate() {
        let locs = [
            location(lat: 12.34, lon: 56.78),
            location(lat: 12.34, lon: 56.78),
            location(lat: 12.34, lon: 56.78),
        ]
        let c = locs.weightedCenter()
        #expect(abs((c?.latitude ?? 0) - 12.34) < tol)
        #expect(abs((c?.longitude ?? 0) - 56.78) < tol)
    }

    @Test func centerPulledTowardMoreAccuratePoint() {
        // A is precise (accuracy 5), B is imprecise (accuracy 100).
        // Weight is 1 / accuracy^2, so the center should sit far closer to A
        // than to the geometric midpoint at longitude 0.05.
        let a = location(lat: 0.02, lon: 0.0, accuracy: 5)
        let b = location(lat: 0.02, lon: 0.10, accuracy: 100)
        let c = [a, b].weightedCenter()
        #expect(c != nil)
        #expect(abs((c?.latitude ?? 0) - 0.02) < 1e-4)
        #expect((c?.longitude ?? 1) < 0.005)
    }

    @Test func swappingAccuracyMovesCenterToOtherPoint() {
        // mirror image of the previous test: now B is the precise one
        let a = location(lat: 0.02, lon: 0.0, accuracy: 100)
        let b = location(lat: 0.02, lon: 0.10, accuracy: 5)
        let c = [a, b].weightedCenter()
        #expect(c != nil)
        #expect((c?.longitude ?? 0) > 0.095)
    }
}
