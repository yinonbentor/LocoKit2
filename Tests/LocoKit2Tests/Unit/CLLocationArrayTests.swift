import Testing
import Foundation
import CoreLocation
@testable import LocoKit2

// Covers Array<CLLocation>.distance() and usableLocations() — the siblings
// of weightedCenter()/radius() that were not yet pinned. Same branch shape:
// nil/empty, single -> 0, null-island filtering, cumulative sum.
@Suite struct CLLocationArrayTests {

    private func loc(_ lat: Double, _ lon: Double) -> CLLocation {
        Fixtures.makeCLLocation(latitude: lat, longitude: lon)
    }

    private let a = CLLocation(latitude: -33.86, longitude: 151.20)
    private let b = CLLocation(latitude: -33.87, longitude: 151.21)
    private let c = CLLocation(latitude: -33.88, longitude: 151.22)

    // MARK: - usableLocations()

    @Test func usableLocationsFiltersNullIslandAndInvalid() {
        let invalid = CLLocation(latitude: 999, longitude: 999)   // not valid
        let nullIsland = CLLocation(latitude: 0, longitude: 0)
        let good = loc(-33.86, 151.20)
        let usable = [invalid, nullIsland, good].usableLocations()
        #expect(usable.count == 1)
        #expect(usable.first?.coordinate.latitude == -33.86)
    }

    // MARK: - distance()

    @Test func distanceOfEmptyIsNil() {
        #expect([CLLocation]().distance() == nil)
    }

    @Test func distanceOfSingleIsZero() {
        #expect([a].distance() == 0)
    }

    @Test func distanceIsCumulativePairwiseSum() {
        // mirror distance()'s exact calls: it sums current.distance(from:
        // previous) over consecutive pairs. CLLocation.distance is geodesic
        // and not bit-symmetric, so the call direction must match; tolerance
        // is mm, not µm (km-scale geodesic FP noise is ~cm).
        let reference = b.distance(from: a) + c.distance(from: b)
        let result = [a, b, c].distance()
        #expect(result != nil)
        #expect(abs((result ?? -1) - reference) < 1e-3)
    }

    @Test func distanceSkipsNullIslandBetweenPoints() {
        let nullIsland = CLLocation(latitude: 0, longitude: 0)
        // null island is dropped, so distance is measured a -> c directly
        // (implementation calls c.distance(from: a))
        let reference = c.distance(from: a)
        let result = [a, nullIsland, c].distance()
        #expect(abs((result ?? -1) - reference) < 1e-3)
    }

    @Test func distanceOfOnlyUnusableIsNil() {
        let nullIsland = CLLocation(latitude: 0, longitude: 0)
        #expect([nullIsland, nullIsland].distance() == nil)
    }

    @Test func distanceWithOneUsableAfterFilteringIsZero() {
        let nullIsland = CLLocation(latitude: 0, longitude: 0)
        #expect([nullIsland, a].distance() == 0)
    }
}
