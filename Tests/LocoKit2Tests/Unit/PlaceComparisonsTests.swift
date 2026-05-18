import Testing
import Foundation
import CoreLocation
@testable import LocoKit2

@Suite struct PlaceComparisonsTests {

    private let tol = 1e-6

    private func place(
        lat: Double, lon: Double,
        mean: CLLocationDistance, sd: CLLocationDistance
    ) -> Place {
        var p = Place(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            name: "test"
        )
        p.radiusMean = mean
        p.radiusSD = sd
        return p
    }

    // MARK: - distance(from: Place)

    // The center-to-center geodesic is delegated to CLLocation.distance; this
    // test pins the *composition* (subtract both places' 3-SD radii), using
    // the same primitive for the reference so it stays deterministic.
    @Test func placeDistanceSubtractsBoth3SDRadii() {
        let a = place(lat: 1.0, lon: 1.0, mean: 50, sd: 10)   // with3sd = 80
        let b = place(lat: 1.01, lon: 1.0, mean: 30, sd: 5)    // with3sd = 45
        let centerDistance = a.center.location.distance(from: b.center.location)
        #expect(abs(a.distance(from: b) - (centerDistance - 80 - 45)) < tol)
    }

    @Test func placeDistanceIsSymmetric() {
        let a = place(lat: 2.0, lon: 3.0, mean: 40, sd: 8)
        let b = place(lat: 2.05, lon: 3.1, mean: 70, sd: 0)
        #expect(abs(a.distance(from: b) - b.distance(from: a)) < tol)
    }

    @Test func overlapsIsExactlyDistanceBelowZero() {
        let a = place(lat: 5.0, lon: 5.0, mean: 40, sd: 5)
        let near = place(lat: 5.0, lon: 5.0, mean: 10, sd: 0)   // same center
        let far = place(lat: 6.0, lon: 6.0, mean: 10, sd: 0)
        #expect(a.overlaps(near) == (a.distance(from: near) < 0))
        #expect(a.overlaps(far) == (a.distance(from: far) < 0))
        #expect(a.overlaps(near))       // overlapping circles -> negative gap
        #expect(!a.overlaps(far))       // far apart, tiny radii -> positive gap
    }

    // MARK: - distance(from: center, radius:)  — asymmetric SD multipliers

    // Documents a deliberate asymmetry that is easy to regress: the
    // Place<-Place form subtracts the OTHER place's 3-SD radius, while the
    // Place<-(center,radius) form subtracts the argument's 2-SD radius. With
    // an identical center/radius the two results therefore differ by exactly
    // one SD of the argument.
    @Test func centerRadiusFormUses2SDWhilePlaceFormUses3SD() {
        let a = place(lat: 10.0, lon: 10.0, mean: 60, sd: 12)
        let b = place(lat: 10.02, lon: 10.0, mean: 25, sd: 9)

        let viaPlace = a.distance(from: b)
        let viaCenter = a.distance(from: b.center, radius: b.radius)

        // viaPlace subtracts b.with3sd, viaCenter subtracts b.with2sd,
        // so viaPlace is smaller by exactly b.radius.sd
        #expect(abs((viaCenter - viaPlace) - b.radius.sd) < tol)
    }

    @Test func overlapsCenterRadiusMatchesDistanceSign() {
        let a = place(lat: 0.5, lon: 0.5, mean: 100, sd: 20)
        let sameCenter = CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5)
        #expect(a.overlaps(center: sameCenter, radius: Radius(mean: 5, sd: 0)))
        let farCenter = CLLocationCoordinate2D(latitude: 1.5, longitude: 1.5)
        #expect(!a.overlaps(center: farCenter, radius: Radius(mean: 5, sd: 0)))
    }

    // MARK: - contains(_:sd:)

    // contains is `pointDistance <= radius.withSD(sd)`. Verify that identity
    // holds across a spread of SD multipliers using the same distance
    // primitive for the reference.
    @Test(arguments: [0.0, 1.0, 2.0, 3.0])
    func containsMatchesRadiusAtSD(_ sd: Double) {
        let p = place(lat: 12.0, lon: 34.0, mean: 100, sd: 15)
        let probe = CLLocation(latitude: 12.001, longitude: 34.0)
        let d = probe.distance(from: p.center.location)
        #expect(p.contains(probe, sd: sd) == (d <= p.radius.withSD(sd)))
    }

    @Test func containsIsTrueAtExactCenter() {
        let p = place(lat: 7.0, lon: 7.0, mean: 30, sd: 0)
        #expect(p.contains(p.center.location, sd: 0))
    }
}
