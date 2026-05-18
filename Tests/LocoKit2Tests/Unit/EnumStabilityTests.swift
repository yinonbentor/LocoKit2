import Testing
import Foundation
@testable import LocoKit2

// These enums are persisted to the database as their Int rawValue. Reordering
// or renumbering a case silently corrupts every existing user's data, so the
// numbers themselves are a contract — pin them.
@Suite struct EnumStabilityTests {

    // MARK: - ActivityType (stored on every LocomotionSample)

    @Test(arguments: [
        (ActivityType.unknown, -1), (.bogus, 0),
        (.stationary, 1), (.walking, 2), (.running, 3),
        (.cycling, 4), (.car, 5), (.airplane, 6),
        (.train, 20), (.bus, 21),                 // transport block starts at 20
        (.skateboarding, 50),                     // active block starts at 50
        (.hiking, 61),                            // current last value
    ])
    func activityTypeRawValuesAreStable(_ pair: (ActivityType, Int)) {
        #expect(pair.0.rawValue == pair.1)
        #expect(ActivityType(rawValue: pair.1) == pair.0)
    }

    @Test func activityTypeRawValuesAreUnique() {
        let raws = ActivityType.allCases.map(\.rawValue)
        #expect(Set(raws).count == raws.count)
    }

    @Test func isMovingTypeMatchesNonMovingList() {
        for type in ActivityType.nonMovingTypes {
            #expect(!type.isMovingType)
        }
        for type in [ActivityType.walking, .car, .hiking, .train] {
            #expect(type.isMovingType)
        }
    }

    @Test(arguments: [
        (ActivityType.stationary, ActivityType?.some(.stationary)),
        (.walking, .some(.walking)), (.hiking, .some(.walking)),
        (.golf, .some(.walking)), (.running, .some(.running)),
        (.skateboarding, .some(.cycling)), (.taxi, .some(.car)),
        (.metro, .some(.train)), (.hotAirBalloon, .some(.airplane)),
        (.swimming, .none), (.wheelchair, .none),
    ])
    func bd0BucketMapping(_ pair: (ActivityType, ActivityType?)) {
        #expect(pair.0.bd0Bucket == pair.1)
    }

    // MARK: - MovingState (stored on every LocomotionSample)

    @Test func movingStateRawValues() {
        #expect(MovingState.uncertain.rawValue == -1)
        #expect(MovingState.stationary.rawValue == 0)
        #expect(MovingState.moving.rawValue == 1)
        for s in [MovingState.uncertain, .stationary, .moving] {
            #expect(MovingState(rawValue: s.rawValue) == s)
        }
    }

    @Test func movingStateStringValueInit() {
        #expect(MovingState(stringValue: "uncertain") == .uncertain)
        #expect(MovingState(stringValue: "stationary") == .stationary)
        #expect(MovingState(stringValue: "moving") == .moving)
        #expect(MovingState(stringValue: "garbage") == nil)
    }

    // MARK: - RecordingState

    @Test(arguments: [
        (RecordingState.off, 0), (.recording, 1), (.sleeping, 2),
        (.deepSleeping, 3), (.wakeup, 4), (.standby, 5),
    ])
    func recordingStateRawValues(_ pair: (RecordingState, Int)) {
        #expect(pair.0.rawValue == pair.1)
        #expect(RecordingState(rawValue: pair.1) == pair.0)
    }
}
