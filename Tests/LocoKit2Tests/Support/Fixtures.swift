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

    /// A location with a *valid* velocity (course/speed plus their
    /// accuracies set), so `CLLocation.invalidVelocity` is false. The plain
    /// `makeCLLocation` leaves speedAccuracy at -1, which is always invalid.
    static func makeMovingLocation(
        latitude: CLLocationDegrees = -33.8688,
        longitude: CLLocationDegrees = 151.2093,
        horizontalAccuracy: CLLocationAccuracy = 10,
        course: CLLocationDirection = 90,
        speed: CLLocationSpeed = 10,
        timestamp: Date
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: 10,
            course: course,
            courseAccuracy: 5,
            speed: speed,
            speedAccuracy: 5,
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
        classifiedActivityType: ActivityType? = nil,
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
        sample.classifiedActivityType = classifiedActivityType
        return sample
    }

    /// Inserts the samples, then builds a real `TimelineItem` from them via
    /// the production `createItem` path (base/visit/trip rows + sample
    /// reassignment + edge triggers). Returns the new item id. Must be called
    /// inside a `pool.write`.
    @discardableResult
    static func insertItem(
        _ db: GRDB.Database, samples: [LocomotionSample], isVisit: Bool
    ) throws -> String {
        for sample in samples {
            try sample.insert(db)
        }
        let item = try TimelineItem.createItem(
            from: samples, isVisit: isVisit, db: db
        )
        return item.id
    }

    /// A straight, evenly-timed, collinear track of `count` samples — dense
    /// enough that Douglas–Peucker drops the interior points. Each sample
    /// carries `activityType` as its classified type so a trip built from
    /// them has a non-nil `activityType` (required by trip pruning).
    static func makeCollinearTrack(
        count: Int,
        start: Date = Date(timeIntervalSince1970: 1_700_000_000),
        secondsApart: TimeInterval = 1,
        metresApart: Double = 1,
        activityType: ActivityType = .car
    ) -> [LocomotionSample] {
        let metresPerDegLon = 111_320.0
        return (0..<count).map { i in
            let lon = 0.001 + (Double(i) * metresApart / metresPerDegLon)
            let ts = start.addingTimeInterval(Double(i) * secondsApart)
            let loc = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 0.001, longitude: lon),
                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                course: 90, courseAccuracy: 5, speed: 10, speedAccuracy: 5,
                timestamp: ts
            )
            return makeSample(
                date: ts,
                movingState: .moving,
                classifiedActivityType: activityType,
                location: loc
            )
        }
    }

    /// Inserts a private Place and returns it (id is a UUID).
    static func insertPlace(
        _ db: GRDB.Database, lat: Double = 0.001, lon: Double = 0.001
    ) throws -> Place {
        let place = Place(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            name: "Fixture Place"
        )
        try place.insert(db)
        return place
    }

    /// Marks a visit's place as confirmed (raw update; avoids the
    /// @PlacesActor assignPlace path). The Place row must already exist.
    static func confirmVisitPlace(
        _ db: GRDB.Database, itemId: String, placeId: String
    ) throws {
        try db.execute(
            sql: """
                UPDATE TimelineItemVisit
                SET placeId = ?, confirmedPlace = 1, uncertainPlace = 0
                WHERE itemId = ?
                """,
            arguments: [placeId, itemId]
        )
    }

    /// Links ids into a forward chain (ids[0] -> ids[1] -> ...). Setting
    /// nextItemId fires the edge triggers that maintain previousItemId.
    static func linkChain(_ db: GRDB.Database, _ ids: [String]) throws {
        for i in 0 ..< (ids.count - 1) {
            try db.execute(
                sql: "UPDATE TimelineItemBase SET nextItemId = ? WHERE id = ?",
                arguments: [ids[i + 1], ids[i]]
            )
        }
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
