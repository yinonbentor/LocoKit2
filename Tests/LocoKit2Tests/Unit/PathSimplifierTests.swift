import Testing
import Foundation
import CoreLocation
@testable import LocoKit2

@Suite struct PathSimplifierTests {

    private typealias Point = (coordinate: CLLocationCoordinate2D, date: Date, index: Int)

    private func points(
        _ coords: [(lat: CLLocationDegrees, lon: CLLocationDegrees)],
        intervalSeconds: TimeInterval = 0
    ) -> [Point] {
        let start = Date(timeIntervalSince1970: 0)
        return coords.enumerated().map { i, c in
            (CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon),
             start.addingTimeInterval(Double(i) * intervalSeconds),
             i)
        }
    }

    // MARK: - Index-aware variant

    @Test func returnsAllIndicesWhenTwoOrFewerPoints() {
        #expect(PathSimplifier.simplify(coordinates: points([]), maxInterval: 60, epsilon: 1) == Set<Int>())
        #expect(PathSimplifier.simplify(coordinates: points([(0, 0)]), maxInterval: 60, epsilon: 1) == Set([0]))
        #expect(PathSimplifier.simplify(coordinates: points([(0, 0), (1, 0)]), maxInterval: 60, epsilon: 1) == Set([0, 1]))
    }

    @Test func collinearPointsCollapseToEndpoints() {
        // five points on one meridian; middle points lie on the start–end line
        let pts = points([(0, 0), (1, 0), (2, 0), (3, 0), (4, 0)])
        let kept = PathSimplifier.simplify(coordinates: pts, maxInterval: 3600, epsilon: 1)
        #expect(kept == Set([0, 4]))
    }

    @Test func deviatingMidpointIsKept() {
        let pts = points([(0, 0), (2, 5), (0, 10)])
        let kept = PathSimplifier.simplify(coordinates: pts, maxInterval: 3600, epsilon: 1)
        #expect(kept == Set([0, 1, 2]))
    }

    @Test func timeIntervalForcesRetentionOfCollinearPoints() {
        // geometry alone would drop the middles, but 60s spacing > 30s maxInterval keeps them
        let pts = points([(0, 0), (1, 0), (2, 0), (3, 0), (4, 0)], intervalSeconds: 60)
        let kept = PathSimplifier.simplify(coordinates: pts, maxInterval: 30, epsilon: 1)
        #expect(kept == Set([0, 1, 2, 3, 4]))
    }

    // MARK: - Coordinate-only variant

    @Test func coordinateOnlyReturnsInputWhenTwoOrFewerPoints() {
        let two = [CLLocationCoordinate2D(latitude: 0, longitude: 0),
                   CLLocationCoordinate2D(latitude: 1, longitude: 0)]
        let result = PathSimplifier.simplify(coordinates: two, epsilon: 1)
        #expect(result.count == 2)
    }

    @Test func coordinateOnlyCollapsesCollinearToEndpoints() {
        let coords = [(0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (3.0, 0.0), (4.0, 0.0)]
            .map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }
        let result = PathSimplifier.simplify(coordinates: coords, epsilon: 1)
        #expect(result.count == 2)
        #expect(result.first?.latitude == 0)
        #expect(result.last?.latitude == 4)
    }

    @Test func coordinateOnlyKeepsDeviatingMidpoint() {
        let coords = [(0.0, 0.0), (2.0, 5.0), (0.0, 10.0)]
            .map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }
        let result = PathSimplifier.simplify(coordinates: coords, epsilon: 1)
        #expect(result.count == 3)
    }
}
