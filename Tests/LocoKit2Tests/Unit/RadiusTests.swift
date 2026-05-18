import Testing
import Foundation
import CoreLocation
@testable import LocoKit2

@Suite struct RadiusTests {

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

    // MARK: - Radius value type

    @Test func zeroRadiusIsAllZero() {
        #expect(Radius.zero.mean == 0)
        #expect(Radius.zero.sd == 0)
    }

    @Test func sdMultipliers() {
        let r = Radius(mean: 100, sd: 25)
        #expect(r.with0sd == 100)
        #expect(r.with1sd == 125)
        #expect(r.with2sd == 150)
        #expect(r.with3sd == 175)
        #expect(r.withSD(4) == 200)
    }

    // MARK: - Array<CLLocation>.radius(from:)

    @Test func radiusOfEmptyIsZero() {
        let center = location(lat: 1, lon: 1)
        let result = [CLLocation]().radius(from: center)
        #expect(result.mean == 0)
        #expect(result.sd == 0)
    }

    @Test func radiusOfSingleUsesItsAccuracyAsMean() {
        let single = [location(lat: 1, lon: 1, accuracy: 25)]
        let result = single.radius(from: location(lat: 1, lon: 1))
        #expect(result.mean == 25)
        #expect(result.sd == 0)
    }

    @Test func radiusOfSingleWithNegativeAccuracyIsZero() {
        // location is still coordinate-usable, so it reaches the single-item
        // branch, but a negative accuracy is not meaningful -> .zero
        let single = [location(lat: 1, lon: 1, accuracy: -1)]
        let result = single.radius(from: location(lat: 1, lon: 1))
        #expect(result.mean == 0)
        #expect(result.sd == 0)
    }

    @Test func radiusOfIdenticalPointsAtCenterIsZero() {
        let coord = (lat: 1.5, lon: 2.5)
        let locs = [
            location(lat: coord.lat, lon: coord.lon),
            location(lat: coord.lat, lon: coord.lon),
            location(lat: coord.lat, lon: coord.lon),
        ]
        let result = locs.radius(from: location(lat: coord.lat, lon: coord.lon))
        #expect(result.mean < 1e-6)
        #expect(result.sd < 1e-6)
    }

    @Test func radiusFiltersNullIslandPoints() {
        // null island is not usable and must be dropped before stats
        let coord = (lat: 1.5, lon: 2.5)
        let locs = [
            location(lat: 0, lon: 0),                       // filtered
            location(lat: coord.lat, lon: coord.lon),
            location(lat: coord.lat, lon: coord.lon),
        ]
        let result = locs.radius(from: location(lat: coord.lat, lon: coord.lon))
        #expect(result.mean < 1e-6)
        #expect(result.sd < 1e-6)
    }

    @Test func radiusMeanAndSdAreNonNegative() {
        let center = location(lat: 10, lon: 10)
        let locs = [
            location(lat: 10.0, lon: 10.0),
            location(lat: 10.001, lon: 10.0),
            location(lat: 10.0, lon: 10.002),
            location(lat: 9.999, lon: 10.001),
        ]
        let result = locs.radius(from: center)
        #expect(result.mean >= 0)
        #expect(result.sd >= 0)
    }
}
