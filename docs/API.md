# LocoKit2 API Guide

LocoKit2 is a modern Swift framework for recording and processing location/motion
timeline data. It records raw GPS and motion samples, organises them into a
semantic timeline of **Visits** (time spent at **Places**) and **Trips** (movement
with a classified **activity type**), and provides import/export, activity-type
machine learning, and reactive observation APIs.

This guide documents the public API surface. It is organised by subsystem:

1. [Concepts & Architecture](#1-concepts--architecture)
2. [Getting Started: Recording](#2-getting-started-recording)
3. [LocomotionManager](#3-locomotionmanager)
4. [TimelineRecorder](#4-timelinerecorder)
5. [Data Models](#5-data-models)
6. [Database Access](#6-database-access)
7. [Timeline Processing](#7-timeline-processing)
8. [Observation & Reactive UI](#8-observation--reactive-ui)
9. [Activity Type Classification](#9-activity-type-classification)
10. [Places](#10-places)
11. [Health Data](#11-health-data)
12. [Import / Export](#12-import--export)
13. [Background Tasks](#13-background-tasks)
14. [Concurrency Model](#14-concurrency-model)

> **Requirements:** iOS 18+, Swift 6.0+. Dependencies: GRDB 7.1+, Surge 2.3+.
> Current `LocomotionManager.locoKitVersion` is `"9.0.0"`.

---

## 1. Concepts & Architecture

| Concept | Type | Description |
|---|---|---|
| **Sample** | `LocomotionSample` | A single timestamped reading: location, moving state, acceleration, steps, heart rate. |
| **Timeline Item** | `TimelineItem` | A composite of a `TimelineItemBase` plus either a `TimelineItemVisit` or `TimelineItemTrip`. |
| **Visit** | `TimelineItemVisit` | A period spent stationary in one area, optionally linked to a `Place`. |
| **Trip** | `TimelineItemTrip` | A period of movement, with a classified/confirmed `ActivityType`. |
| **Place** | `Place` | A reusable point of interest with visit statistics and time histograms. |
| **Segment** | `ItemSegment` | A contiguous run of samples sharing one activity type. |

Timeline items form a doubly linked list via `previousItemId` / `nextItemId`.
Items are **soft-deleted** (`deleted = true`) rather than removed.

**Singletons** use the `.highlander` naming convention
(`LocomotionManager.highlander`, `Database.highlander`,
`TimelineObserver.highlander`).

**Global actors** isolate subsystems for data-race safety: `@TimelineActor`,
`@PlacesActor`, `@ActivityTypesActor`, `@HealthActor`, `@ImportExportActor`.

---

## 2. Getting Started: Recording

```swift
import LocoKit2

// 1. Register database transaction observers (once, at app startup)
TimelineRecorder.startup()

// 2. Check / request permissions
let loco = LocomotionManager.highlander
if !loco.hasNecessaryPermissions {
    loco.requestLocationAuthorization()
    await loco.requestMotionAuthorization()
}

// 3. Start recording (drives LocomotionManager + writes samples + builds timeline)
try await TimelineRecorder.startRecording()

// 4. Observe state and locations
Task {
    for await state in loco.stateUpdates() {
        print("Recording state: \(state.displayName)")
    }
}
Task {
    for await location in loco.locationUpdates() {
        print("Filtered location: \(location.coordinate)")
    }
}

// 5. Read the current timeline item
if let item = TimelineRecorder.currentItem(includeSamples: true, includePlaces: true) {
    print(try item.description)
}

// 6. Stop
await TimelineRecorder.stopRecording()
```

`LocomotionManager` is the low-level location/motion engine.
`TimelineRecorder` orchestrates recording: it drives `LocomotionManager`, writes
samples to the database, and builds the timeline. **Most apps should use
`TimelineRecorder` for start/stop**, not `LocomotionManager` directly.

---

## 3. LocomotionManager

`@Observable public final class LocomotionManager` — the raw location/motion
engine. Access via the singleton:

```swift
public static let highlander = LocomotionManager()
public static let locoKitVersion = "9.0.0"
```

### Recording control (`@MainActor`)

```swift
public func startRecording()      // full location + motion updates
public func stopRecording()       // stop everything; recordingState = .off
public func startStandby()        // low-power; significant-change only
public private(set) var recordingState: RecordingState   // .off by default
```

### State & location streams

```swift
public func stateUpdates() -> AsyncStream<RecordingState>
public func locationUpdates() -> AsyncStream<CLLocation>   // Kalman-filtered

public private(set) var lastUpdated: Date?
public private(set) var lastRawLocation: CLLocation?
public private(set) var lastFilteredLocation: CLLocation?
```

### Permissions

```swift
public var locationAuthorizationStatus: CLAuthorizationStatus
public var motionAuthorizationStatus: CMAuthorizationStatus
public var hasNecessaryPermissions: Bool   // location + motion both granted

public func requestLocationAuthorization()           // requestAlwaysAuthorization
public func requestMotionAuthorization() async
```

### Configuration

```swift
public private(set) var sleepCycleDuration: TimeInterval   // default 30
public func setSleepCycleDuration(_ duration: TimeInterval) // @MainActor
public var recordRawLocations: Bool          // dump raw GPS to CSV (debug)
public var standbyCycleDuration: TimeInterval // default 120
public var fallbackUpdateDuration: TimeInterval // default 6
```

### Inspecting current state

```swift
public func createASample() async -> LocomotionSample
public func sleepDetectorState() async -> SleepDetectorState?
public func movingStateDetails() async -> MovingStateDetails
```

`MovingStateDetails` exposes `movingState`, `n`, `timestamp`, `meanAccuracy`,
`meanSpeed`, `sdSpeed`, `rawInvalidVelocityRate`.

### Multi-recorder coordination

```swift
public var appGroup: AppGroup?
public func becomeTheActiveRecorder() async
```

### `RecordingState`

`public enum RecordingState: Int` — `.off`, `.recording`, `.sleeping`,
`.deepSleeping`, `.wakeup`, `.standby`. Helpers: `isSleeping`,
`isCurrentRecorder`, `displayName`, `stringValue`, `init?(stringValue:)`.

### `MovingState`

`public enum MovingState: Int` — `.uncertain (-1)`, `.stationary (0)`,
`.moving (1)`. Helpers: `stringValue`, `init?(stringValue:)`.

---

## 4. TimelineRecorder

`@TimelineActor public enum TimelineRecorder` — the recording orchestrator.
All members are `static` and isolated to `@TimelineActor`.

```swift
public static func startup()                       // register DB observers; call once
public static func startRecording() async throws   // throws if import in progress
public static func stopRecording() async
public static var isRecording: Bool { get async }
```

### Current item / sample access

```swift
public static private(set) var currentItemId: String?
public static func currentItem(includeSamples: Bool = false,
                               includePlaces: Bool = false) -> TimelineItem?
public static func updateCurrentItemId()

public static private(set) var latestSampleId: String?
public static func latestSample() -> LocomotionSample?
```

### Drift profile context (GPS trust window)

```swift
public struct DriftContext: Sendable {
    public let itemId: String
    public let placeId: String
    public let centroid: CLLocation
    public let profile: DriftProfile
}
public static func currentDriftContext(for location: CLLocation) -> DriftContext?
```

`startRecording()` throws `ImportExportError.partialImportInProgress` if an
import is pending. The recorder automatically tunes
`LocomotionManager.sleepCycleDuration` based on the current place's
leaving-probability.

---

## 5. Data Models

All models are GRDB records (`FetchableRecord` / `PersistableRecord`),
`Codable`, `Hashable`, `Sendable`.

### TimelineItem (composite)

`public struct TimelineItem: FetchableRecord, Codable, Identifiable, Hashable, Sendable`

Composed of:

```swift
public var base: TimelineItemBase       // required
public var visit: TimelineItemVisit?    // present iff isVisit
public var trip: TimelineItemTrip?      // present iff isTrip
public var place: Place?                // via visit, if requested
public internal(set) var samples: [LocomotionSample]?
public internal(set) var segments: [ItemSegment]?
```

Convenience accessors: `id`, `isVisit`, `isTrip`, `dateRange`, `source`,
`disabled`, `deleted`, `locked`, `samplesChanged`, `coordinates`,
`startTimeZone`, `endTimeZone`, `debugShortId`.

Throwing validation: `isValid`, `isInvalid`, `isWorthKeeping`, `isDataGap`,
`isNolo`, `isBogus`.

Key methods:

```swift
public static func createItem(from samples: [LocomotionSample], isVisit: Bool,
    disabled: Bool = false, source: String? = nil, locked: Bool = false,
    db: GRDB.Database) throws -> TimelineItem

public static func fetchItem(itemId: String, includeSamples: Bool,
    includePlace: Bool = false) async throws -> TimelineItem?

public static func itemRequest(includeSamples: Bool, includePlaces: Bool = false,
    includeHistograms: Bool = true) -> QueryInterfaceRequest<TimelineItem>

public mutating func fetchSamples(forceFetch: Bool = false) async
public mutating func copyMetadata(from otherItem: TimelineItem, db: GRDB.Database) throws
public func hasChanged(from other: TimelineItem?) -> Bool

@TimelineActor public func previousItem(in list: TimelineLinkedList) async -> TimelineItem?
@TimelineActor public func nextItem(in list: TimelineLinkedList) async -> TimelineItem?

public func predictedLeavingTimes() -> [LeavingTime]?   // LeavingTime { date, probability }
```

Activity-type extension:

```swift
public mutating func classifySamples() async
public mutating func changeActivityType(to confirmedType: ActivityType) async throws
public func cleanupSamples() async
public var haveSamplesForCleanup: Bool { get async }
```

Strings extension:

```swift
public var title: String
public var typeString: String { get throws }     // "datagap" | "nolo" | "visit" | "trip"
public var description: String { get throws }
public func startString(dateStyle:timeStyle:relative:format:) -> String?
public func endString(dateStyle:timeStyle:relative:format:) -> String?
public static func dateString(for:timeZone:dateStyle:timeStyle:relative:format:) -> String?
```

### TimelineItemBase

`public struct TimelineItemBase` — core record. Notable fields: `id`,
`isVisit`, `startDate`, `endDate`, `source`, `sourceVersion`, `disabled`,
`deleted`, `locked`, `samplesChanged`, `previousItemId`, `nextItemId`, plus
health fields (`stepCount`, `floorsAscended`, `floorsDescended`,
`averageAltitude`, `activeEnergyBurned`, `averageHeartRate`, `maxHeartRate`).
GRDB associations: `visit`, `trip`, `samples`.

### TimelineItemVisit

Key fields: `itemId`, `latitude`, `longitude`, `radiusMean`, `radiusSD`,
`placeId`, `confirmedPlace`, `uncertainPlace`, `customTitle`, `streetAddress`.
Computed: `center`, `radius`, `hasConfirmedPlace`.

```swift
public func overlaps(_ other: TimelineItemVisit) -> Bool
public func distance(from other: TimelineItemVisit) -> CLLocationDistance?
public func distance(from other: TimelineItem) throws -> CLLocationDistance?
public func contains(_ location: CLLocation, sd: Double) -> Bool
public func hasSamePlaceAs(_ other: TimelineItemVisit) -> Bool
public func assignPlace(_ place: Place, confirm: Bool = false, uncertain: Bool = false) async
public mutating func setUncertainty(_ uncertain: Bool)
public mutating func update(from samples: [LocomotionSample]) async
public mutating func copyMetadata(from other: TimelineItemVisit)
```

Constants: `minimumKeeperDuration` (2 min), `minimumValidDuration` (10 s),
`minRadius` (10 m), `maxRadius` (150 m).

### TimelineItemTrip

Key fields: `itemId`, `distance`, `speed`, `classifiedActivityType`,
`confirmedActivityType`, `uncertainActivityType`. Computed `activityType`
returns `confirmedActivityType ?? classifiedActivityType`.

```swift
public mutating func update(from samples: [LocomotionSample]) async
public mutating func updateUncertainty(from results: ClassifierResults)
```

### LocomotionSample

`public struct LocomotionSample` — core fields: `id`, `date`,
`secondsFromGMT`, `movingState`, `recordingState`, `disabled`,
`timelineItemId`; location fields (`latitude`, `longitude`, `altitude`,
`horizontalAccuracy`, `verticalAccuracy`, `speed`, `course`); motion
(`stepHz`, `xyAcceleration`, `zAcceleration`); `heartRate`;
`classifiedActivityType`, `confirmedActivityType`.

```swift
public init(id: String = UUID().uuidString, date: Date,
    secondsFromGMT: Int? = TimeZone.current.secondsFromGMT(),
    movingState: MovingState, recordingState: RecordingState,
    location: CLLocation? = nil)
public static func dataGap(date: Date) -> LocomotionSample

public var location: CLLocation?
public var coordinate: CLLocationCoordinate2D?
public var hasUsableCoordinate: Bool
public var activityType: ActivityType?           // confirmed ?? classified
public var classifierResults: ClassifierResults? { get async }
```

`[LocomotionSample]` extension: `dateRange()`, `usableLocations()`,
`haveAnyUsableCoordinates()`, `weightedCenter()`, `radius(from:)`,
`weightedRadius(from:)`.

### ItemSegment

`public struct ItemSegment` — a contiguous same-activity-type run.

```swift
public init?(samples: [LocomotionSample], manualActivityType: ActivityType? = nil,
             tag: Int? = nil)
public var coordinates: [CLLocationCoordinate2D]
public var center: CLLocationCoordinate2D?
public var radius: Radius?
public var distance: CLLocationDistance
public var isDataGap: Bool
public var isNolo: Bool
public var activityType: ActivityType?
public func validateIsContiguous() async throws -> Bool
public func confirmActivityType(_ confirmedType: ActivityType) async
```

### TimelineLinkedList

`@TimelineActor public final class TimelineLinkedList: AsyncSequence` —
navigable cache of items via edges.

```swift
public init?(fromItemId seedItemId: String) async
public convenience init(fromItems: [TimelineItem]) async
public init(fromItemIds: [String]) async
public func itemFor(itemId: String) async -> TimelineItem?
public func previousItem(for item: TimelineItem) async -> TimelineItem?
public func nextItem(for item: TimelineItem) async -> TimelineItem?
public func invalidate(itemId: String)
```

---

## 6. Database Access

`public final class Database` — GRDB-backed SQLite store.

```swift
public static let highlander = Database()
public static var pool: DatabasePool { highlander.pool }   // shared connection pool
public private(set) lazy var pool: DatabasePool
```

The pool: 30 s busy timeout, up to 12 concurrent readers, stored at the app
group container if available, else the app container (`LocoKit2.sqlite`).

```swift
// Reads
let items = try await Database.pool.read { db in
    try TimelineItem.itemRequest(includeSamples: true)
        .filter(Column("deleted") == false)
        .order(Column("startDate"))
        .fetchAll(db)
}

// Writes
try await Database.pool.write { db in
    try item.base.updateChanges(db) { $0.disabled = true }
}

// Uncancellable variants (imports/migrations)
try Database.pool.uncancellableRead  { db in ... }
try Database.pool.uncancellableWrite { db in ... }
```

**Schema highlights:** `Place`, `TimelineItemBase`, `TimelineItemVisit`,
`TimelineItemTrip`, `LocomotionSample`, `DriftProfile`, `ActivityTypesModel`,
`TaskStatus`, `ImportState`. Spatial lookups use R-tree virtual tables
(`PlaceRTree`, `SampleRTree`). Edges are deferred foreign keys with
constraints preventing self/circular references.

Prefer SQL-level batch updates over read-modify-write to avoid stale snapshots:

```swift
try LocomotionSample
    .filter(Column("timelineItemId") == oldId)
    .updateAll(db, Column("timelineItemId").set(to: newId))
```

---

## 7. Timeline Processing

`@TimelineActor public enum TimelineProcessor` — turns raw items into a clean
semantic timeline (merging, edge healing, sanitisation).

```swift
public static func processFrom(itemId: String) async
public static func process(items: [TimelineItem]) async
public static func process(itemIds: [String]) async
public static func process(_ list: TimelineLinkedList) async
```

The processing loop repeatedly: sanitises edges (move misclassified boundary
samples), heals edges (reconnect broken links / insert data-gap items for gaps
> 15 min), collects candidate merges (adjacent / betweener / bridge), scores
them, and executes the best-scoring merge until stable.

### Extraction

```swift
@discardableResult
public static func extractVisit(for segment: ItemSegment, placeId: String,
    confirmedPlace: Bool) async throws -> TimelineItem?
@discardableResult
public static func extractVisit(for segment: ItemSegment,
    customTitle: String) async throws -> TimelineItem?
@discardableResult
public static func extractItem(for segment: ItemSegment, isVisit: Bool,
    placeId: String? = nil, confirmedPlace: Bool = true,
    customTitle: String? = nil) async throws -> TimelineItem?
```

### Delete & enabled-state

```swift
public static func safeDeleteVisit(_ deadman: TimelineItem) async
public static func enableItem(itemId: String) async throws
public static func disableItem(itemId: String) async throws
```

`enableItem` / `disableItem` correctly split and re-link overlapping items so
the timeline stays continuous (used e.g. for workout overlays).

---

## 8. Observation & Reactive UI

### TimelineObserver

`public final class TimelineObserver: TransactionObserver, Sendable`

```swift
public static let highlander = TimelineObserver()
public var enabled: Bool { get set }
public func changesStream() -> AsyncStream<DateInterval>
```

Batches table changes per transaction and yields the affected date ranges.
Disable it to pause the stream while backgrounded.

### TimelineItemObserver

```swift
public static let highlander = TimelineItemObserver()
public func changesStream() -> AsyncStream<Set<String>>   // changed item IDs
```

### TimelineSegment (observable UI window)

`@MainActor @Observable public final class TimelineSegment`

```swift
public init(dateRange: DateInterval, shouldReprocessOnUpdate: Bool = false)
public let dateRange: DateInterval
public var shouldReprocessOnUpdate: Bool
public private(set) var timelineItems: [TimelineItem]?
public func cancelProcessing()
public func resumeProcessingIfNeeded()
public func pruneSamples(excluding prunedItemIds: inout Set<String>) async
```

Bind `timelineItems` directly in SwiftUI. The segment debounces DB changes
(~1 s), refetches its date range, and (optionally) reprocesses — skipping
re-processing when only the actively-recording item changed.

---

## 9. Activity Type Classification

### ActivityType

`public enum ActivityType: Int, CaseIterable, Codable, Hashable, Sendable` —
43 cases including `.unknown (-1)`, `.bogus (0)`, base types
(`.stationary`, `.walking`, `.running`, `.cycling`, `.car`, `.airplane`),
extended transport (`.train`, `.bus`, `.tram`, `.metro`, …) and active types
(`.hiking`, `.swimming`, `.skiing`, …).

Collections: `baseTypes`, `extendedTypes`, `movingTypes`, `nonMovingTypes`,
`stepsTypes`, `workoutTypes`. Members: `isMovingType`, `bd0Bucket`,
`displayName`, `init?(stringValue:)`.

### ActivityClassifier

`@ActivityTypesActor public enum ActivityClassifier`

```swift
public static func canClassify(_ coordinate: CLLocationCoordinate2D? = nil) -> Bool
public static func results(for sample: LocomotionSample) async -> ClassifierResults?
public static func results(for samples: [LocomotionSample],
    timeout: TimeInterval? = nil) async
    -> (combinedResults: ClassifierResults?,
        perSampleResults: [String: ClassifierResults])?
public static func invalidateModel(geoKey: String)
public static func clearModels()
public private(set) static var models: [Int: ActivityTypesModel]
```

Classification combines nested geographic models (CD2 → CD1 → CD0 → bundled
BD0) with weighted averaging; results are cached per sample ID.

### ClassifierResults / ClassifierResultItem

```swift
public final class ClassifierResults: Sendable {
    public init(resultItems: [ClassifierResultItem])     // auto-sorted by score
    public let resultItems: [ClassifierResultItem]
    public var bestMatch: ClassifierResultItem?
    public var scoresTotal: Double
    public subscript(activityType: ActivityType) -> ClassifierResultItem?
    public func merging(_ other: ClassifierResults, withWeight: Double) -> ClassifierResults
}

public struct ClassifierResultItem: Equatable, Identifiable, Sendable {
    public init(name: ActivityType, score: Double)
    public let activityType: ActivityType
    public let score: Double
    public func normalisedScore(in: ClassifierResults) -> Double
    public func normalisedScoreGroup(in: ClassifierResults) -> ClassifierResultScoreGroup
}
```

Usage:

```swift
guard ActivityClassifier.canClassify() else { return }
if let results = await ActivityClassifier.results(for: sample),
   let best = results.bestMatch {
    print("\(best.activityType.displayName) — \(best.normalisedScore(in: results))")
}
```

### ActivityTypesManager (model training)

`@ActivityTypesActor public enum ActivityTypesManager`

```swift
public static func queueUpdatesForModelsContaining(_ samples: [LocomotionSample])
@MainActor public static func registerModelUpdatesTask()   // call at startup
public static func updateModel(geoKey: String) async
public static func fetchPendingModelGeoKeys() async throws -> [String]
public static func deleteAllModels() async throws
public static func trainBD0() async throws -> URL          // device only
```

Confirming an activity type on samples and calling
`queueUpdatesForModelsContaining` flags the relevant models for retraining;
training happens in a registered background task.

---

## 10. Places

`public struct Place` — a reusable POI with statistics.

Key fields: `id`, `latitude`, `longitude`, `radiusMean`, `radiusSD`, `name`,
`streetAddress`, `countryCode`, `locality`, `isStale`, external IDs
(`mapboxPlaceId`, `googlePlaceId`, `foursquarePlaceId`, …), stats
(`visitCount`, `visitDays`, `lastVisitDate`) and histograms (`arrivalTimes`,
`leavingTimes`, `visitDurations`, `occupancyTimes`).

```swift
public init(coordinate: CLLocationCoordinate2D, name: String,
    streetAddress: String? = nil, countryCode: String? = nil,
    locality: String? = nil, secondsFromGMT: Int? = nil, /* external IDs… */)

public var center: CLLocationCoordinate2D
public var radius: Radius
public var isPrivate: Bool
public var needsReverseGeocode: Bool

@PlacesActor @discardableResult
public func updateFromReverseGeocode() async throws -> Bool
@PlacesActor public func markStale() async
@PlacesActor public func updateVisitStats() async
public func computeDisplayHistograms() async throws -> DisplayHistograms
public func leavingProbabilityFor(duration: TimeInterval, date: Date = .now) -> Double?
```

Constants: `minimumPlaceRadius` (8 m), `maximumPlaceRadius` (2000 m),
`minimumNewPlaceRadius` (60 m). `PlaceSource` enum: `.google`, `.foursquare`,
`.mapbox`.

Assign a place to a visit via `TimelineItemVisit.assignPlace(_:confirm:uncertain:)`
or extract one via `TimelineProcessor.extractVisit(for:placeId:confirmedPlace:)`.

---

## 11. Health Data

`@HealthActor public enum HealthManager`

```swift
public static let healthStore: HKHealthStore
public private(set) static var healthKitEnabled: Bool
public static func enableHealthKit()
public static func disableHealthKit()
public static func requestAuthorization() async
public static func haveAnyReadAccess() async throws -> Bool
public static func checkReadPermission(for type: HKObjectType) async throws -> Bool
public static func updateHealthData(for item: TimelineItem, force: Bool = false) async
public static func heartRateSamples(for item: TimelineItem) async throws -> [HKQuantitySample]
```

Reads step count, flights climbed, active energy, and heart rate, writing
aggregates onto `TimelineItemBase`. Updates are throttled (15 min per item
unless `force: true`) and only run in the foreground. `heartRateSamples`
throws `TimelineError.backgroundRestriction` when backgrounded.

---

## 12. Import / Export

Both are isolated to `@ImportExportActor`. Export schema version `"2.2.0"`.

### ExportManager

```swift
public private(set) static var exportInProgress: Bool
public private(set) static var currentPhase: ExportPhase?   // connecting / places / items / samples
public private(set) static var progress: Double             // 0…1

public static func export(to baseURL: URL, type: ExportType = .full,
    extensions: [ExportExtensionHandler] = [],
    appMetadata: [String: String]? = nil) async throws
```

`.full` creates a dated `export-YYYY-MM-DD-HHmmss/` directory;
`.incremental` writes into `baseURL` and exports only records changed since
the previous backup (with 6-month catch-up chunking for first runs).

Output: `metadata.json`, `places/` (16 hex buckets), `items/` (monthly JSON),
`samples/` (weekly gzipped JSON).

### ImportManager

```swift
public private(set) static var importInProgress: Bool
public private(set) static var currentPhase: ImportPhase?
public private(set) static var progress: Double

public static func startImport(from sourceURL: URL,
    extensions: [ImportExtensionHandler] = []) async throws
public static func resumeImport(extensions: [ImportExtensionHandler] = []) async throws
```

Import disables the recorder/observer, copies the source locally (handling
iCloud downloads), validates, then imports places → items → samples →
restores edges → adopts orphaned samples, and finally restores recorder state.
Uses `INSERT OR IGNORE` (designed for restores into an empty DB); missing
references are nulled and preserved as orphans for later adoption.

### Extension protocols

```swift
public protocol ExportExtensionHandler: Sendable {
    var identifier: String { get }
    func export(to directory: URL, type: ExportType, lastBackupDate: Date?) async throws -> Int
}
public protocol ImportExtensionHandler: Sendable {
    var identifier: String { get }
    func `import`(from directory: URL) async throws -> Int
}
```

### Legacy LocoKit import

`OldLocoKitImporter` migrates databases from the original LocoKit:

```swift
public static func startImport(dateRange: DateInterval? = nil) async throws
public static func resumeImport(dateRange: DateInterval? = nil) async throws
```

### Errors

`public enum ImportExportError: Error` — including `exportInProgress`,
`importInProgress`, `missingMetadata`, `missing{Places,Items,Samples}Directory`,
`partialImportInProgress`, `exportIdMismatch`, `iCloudNotAvailable`,
`missingEdgeRecords`, plus legacy-import cases.

See `docs/export/` (`README.md`, `FORMAT.md`, `IMPORT.md`) for the full format
specification.

---

## 13. Background Tasks

`@MainActor public enum BackgroundTasksManager`

```swift
public static func add(task: BackgroundTaskDefinition)
public static func scheduleTasks()
public static func hasOverdueForegroundTasks() async -> Bool
public static func runOverdueTasks(
    onTaskStarted: (@MainActor (String) -> Void)? = nil) async
```

Register `BackgroundTaskDefinition`s (work handler, minimum delay, optional
foreground threshold) at startup. `runOverdueTasks` runs overdue work in the
foreground only when not recording, not in low-power mode, and thermal state
is below `.serious`. Task state is tracked in the `TaskStatus` table.

---

## 14. Concurrency Model

LocoKit2 is built for Swift 6 strict concurrency. Subsystem isolation is
enforced by global actors — annotate your interacting code accordingly or hop
via `await`:

| Actor | Guards |
|---|---|
| `@TimelineActor` | `TimelineRecorder`, `TimelineProcessor`, `TimelineLinkedList`, item graph ops |
| `@PlacesActor` | place reverse-geocoding & stats |
| `@ActivityTypesActor` | classification & model training |
| `@HealthActor` | all `HealthManager` access |
| `@ImportExportActor` | `ExportManager` / `ImportManager` |

Each has a `static let shared` instance. `LocomotionManager` recording-control
methods are `@MainActor`. Models are `Sendable` value types; cross-actor data
flow uses `AsyncStream` (state, locations, DB-change streams). Database access
goes through the shared `Database.pool` (GRDB `DatabasePool`); prefer
SQL-level batch updates inside `write {}` transactions over read-modify-write.

---

*Generated from the LocoKit2 source tree. Signatures reflect the public API at
`LocomotionManager.locoKitVersion` `9.0.0`.*
