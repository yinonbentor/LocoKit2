import Foundation
import CoreLocation
@testable import LocoKit2

/// Shared test data builders.
///
/// Only builders that can be constructed purely in memory live here.
/// `TimelineItem` has no in-memory initialiser (it is created via
/// `TimelineItem.createItem(... db:)` or JSON decoding), so a
/// `makeTimelineItem` helper belongs with the DB harness (Step 3),
/// not here.
enum Fixtures {

    static func makeCLLocation(
        latitude: CLLocationDegrees = -33.8688,
        longitude: CLLocationDegrees = 151.2093,
        altitude: CLLocationDistance = 0,
        horizontalAccuracy: CLLocationAccuracy = 10,
        verticalAccuracy: CLLocationAccuracy = 10,
        course: CLLocationDirection = -1,
        speed: CLLocationSpeed = -1,
        timestamp: Date = .now
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: course,
            speed: speed,
            timestamp: timestamp
        )
    }

    static func makeSample(
        date: Date = .now,
        movingState: MovingState = .stationary,
        recordingState: RecordingState = .recording,
        location: CLLocation? = nil
    ) -> LocomotionSample {
        LocomotionSample(
            date: date,
            movingState: movingState,
            recordingState: recordingState,
            location: location
        )
    }
}
