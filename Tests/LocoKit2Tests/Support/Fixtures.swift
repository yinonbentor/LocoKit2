import Foundation
import CoreLocation
import GRDB
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
        id: String = UUID().uuidString,
        date: Date = .now,
        movingState: MovingState = .stationary,
        recordingState: RecordingState = .recording,
        disabled: Bool = false,
        timelineItemId: String? = nil,
        location: CLLocation? = nil
    ) -> LocomotionSample {
        var sample = LocomotionSample(
            id: id,
            date: date,
            movingState: movingState,
            recordingState: recordingState,
            location: location
        )
        sample.disabled = disabled
        sample.timelineItemId = timelineItemId
        return sample
    }

    /// Inserts a minimal valid `TimelineItemBase` row (satisfies every
    /// NOT NULL column) so deferred FK references from samples resolve at
    /// commit and the BEFORE-INSERT disabled/deleted check triggers can see a
    /// parent. `isVisit` is arbitrary here; callers that care should build a
    /// real item instead.
    static func insertTimelineItemBase(
        _ db: GRDB.Database, id: String, disabled: Bool = false
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO TimelineItemBase
                    (id, isVisit, source, sourceVersion,
                     disabled, deleted, locked, samplesChanged)
                VALUES (?, 1, 'test', 'test', ?, 0, 0, 0)
                """,
            arguments: [id, disabled]
        )
    }
}
