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

    // KNOWN FAILURE — documents a real bug, intentionally not fixed yet.
    //
    // perpendicularDistance() has a `if alongTrackDistance < 0` branch meant
    // to return the distance to the segment start when the perpendicular foot
    // falls before it. But `alongTrackDistance = acos(...) * earthRadius`, and
    // acos() is always in [0, π] with earthRadius > 0, so that value is never
    // negative — the branch is unreachable dead code. A point lying directly
    // behind the start (here 0.5° west of it on the equator) has a cross-track
    // angle of 0, so the function returns ≈0 instead of the ≈55,596 m distance
    // to the start. Practical impact: Douglas-Peucker can over-simplify paths
    // when intermediate points project behind their segment's start.
    //
    // Wrapped in withKnownIssue so the suite stays green while pinning the
    // expected (correct) behaviour. If the source is ever fixed this test will
    // start failing loudly, which is the signal to delete this wrapper.
    @Test func perpendicularFootBeforeStartReturnsDistanceToStart() {
        let line = (CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    CLLocationCoordinate2D(latitude: 0, longitude: 1))
        let before = CLLocationCoordinate2D(latitude: 0, longitude: -0.5)
        withKnownIssue("perpendicularDistance 'before start' branch is unreachable dead code") {
            // 0.5° along the equator ≈ 55,596 m
            #expect(abs(before.perpendicularDistance(to: line) - 55596.5) < 50)
        }
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
