import Testing
import Foundation
import CoreLocation
@testable import LocoKit2

@Suite struct CoordinateMathTests {

    private let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)

    // MARK: - bearing(to:)

    @Test(arguments: [
        (lat: 1.0, lon: 0.0, expected: 0.0),     // due north
        (lat: 0.0, lon: 1.0, expected: 90.0),    // due east
        (lat: -1.0, lon: 0.0, expected: 180.0),  // due south
        (lat: 0.0, lon: -1.0, expected: 270.0),  // due west
    ])
    func bearingForCardinalDirections(_ args: (lat: Double, lon: Double, expected: Double)) {
        let target = CLLocationCoordinate2D(latitude: args.lat, longitude: args.lon)
        let bearing = origin.bearing(to: target)
        #expect(abs(bearing - args.expected) < 1e-6)
    }

    @Test func bearingIsAlwaysInZeroTo360() {
        let b = CLLocationCoordinate2D(latitude: 0, longitude: -0.0001).bearing(to: origin)
        #expect(b >= 0 && b < 360)
    }

    // MARK: - perpendicularDistance(to:)

    @Test func pointOnLineHasNearZeroDistance() {
        let line = (CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    CLLocationCoordinate2D(latitude: 0, longitude: 1))
        let onLine = CLLocationCoordinate2D(latitude: 0, longitude: 0.5)
        #expect(onLine.perpendicularDistance(to: line) < 1.0)
    }

    @Test func pointOffLineMatchesCrossTrackDistance() {
        let line = (CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    CLLocationCoordinate2D(latitude: 0, longitude: 1))
        let offLine = CLLocationCoordinate2D(latitude: 0.01, longitude: 0.5)
        // 0.01° of latitude ≈ 1112 m
        let d = offLine.perpendicularDistance(to: line)
        #expect(abs(d - 1111.95) < 5)
    }

    @Test func perpendicularFootBeforeStartReturnsDistanceToStart() {
        let line = (CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    CLLocationCoordinate2D(latitude: 0, longitude: 1))
        let before = CLLocationCoordinate2D(latitude: 0, longitude: -0.5)
        // 0.5° along the equator ≈ 55,596 m
        #expect(abs(before.perpendicularDistance(to: line) - 55596.5) < 50)
    }

    @Test func perpendicularFootBeyondEndReturnsDistanceToEnd() {
        let line = (CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    CLLocationCoordinate2D(latitude: 0, longitude: 1))
        let beyond = CLLocationCoordinate2D(latitude: 0, longitude: 1.5)
        #expect(abs(beyond.perpendicularDistance(to: line) - 55596.5) < 50)
    }

    // MARK: - usability

    @Test func nullIslandIsNotUsable() {
        let nullIsland = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        #expect(nullIsland.isNullIsland)
        #expect(!nullIsland.isUsable)
    }

    @Test func realCoordinateIsUsable() {
        let sydney = CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)
        #expect(!sydney.isNullIsland)
        #expect(sydney.isValid)
        #expect(sydney.isUsable)
    }

    @Test func invalidCoordinateIsNotUsable() {
        let invalid = CLLocationCoordinate2D(latitude: 200, longitude: 999)
        #expect(!invalid.isValid)
        #expect(!invalid.isUsable)
    }
}
