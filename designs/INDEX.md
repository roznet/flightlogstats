# FlightLogStats

> iPad / iPhone / Mac Catalyst app for Garmin G1000 / Perspective flight logs:
> import from the SD card, iCloud library, per-flight analysis, trips, fuel,
> upload to FlySto. Plus `python/flightreconcile`, the analysis lab.

Build: Xcode project `flightlogstats.xcodeproj`, needs `git lfs pull` (nav.db and
fixtures) and `flightlogstats/secrets.json` (copied from the sample on first build).

Headings are presentational; discovery matches on each entry's description and
doc link.

## App core

### architecture
Overview: layers, targets, deployment, packages (rzutils, rzutils-touch, rzflight) and their current build breakage, GCD queue model, where each concern is documented.
Key exports: `AppDelegate.worker`, `AppDelegate.knownAirports`, `AppDelegate.knownWaypoints`, `FlightLogOrganizer.shared`, `Settings.shared`
→ Full doc: architecture.md

### log-import-sync
SD card to library: document picker, discovery and dedupe by file name, copy into `Documents/`, quick then batched full parse, Core Data model (derived vs user fields), record versioning, iCloud Drive two-way copy via `NSMetadataQuery`. Core Data is local only (CloudKit disabled).
Key exports: `FlightLogOrganizer`, `search(in:)`, `importAndAddRecordsForFiles`, `addMissingRecordsFromLocal`, `updateRecords(count:force:)`, `syncCloudLogic`, `FlightLogFileRecord`, `LogSelectionMethod`, `ProgressReport`
→ Full doc: log-import-sync.md

### remote-upload
FlySto (OAuth2, zipped POST) upload, per-log status records, the `RequestQueue`, triggers (manual, batch, "automatic" on display), error mapping, and why the queue actually runs in parallel. Savvy removed 2026-09-29 (stored token cleared at launch).
Key exports: `RequestQueue`, `FlyStoRequest`, `FlyStoUploadRequest`, `FlyStoLogFilesRequest`, `FlightFlyStoRecord`, `RemoteServiceRecord.Status`, `Settings.removeObsoleteKeys`
→ Full doc: remote-upload.md

## Parsing & analysis

### log-parsing
Byte-level CSV parser into `FlightData` (row-major, lazily column-major via RZData `DataFrame`, all frames on the same kept rows), field enum + `logFileFields.json` metadata, calculated fields (wind, time-integrated totaliser, flight phase), exact date shortcut, quick vs full parse.
Key exports: `CsvParser`, `BufferedStreamReader`, `FlightData`, `FlightData.keptRows`, `FlightLogFile`, `FlightLogFile.Field`, `FieldCalculation`, `AvionicsSystem`
→ Full doc: log-parsing.md

### analysis
Flight summary (engine/moving/flying times, fuel, airports), legs by categorical change (waypoint, phase, comms, autopilot), trips and visits with base detection, fuel refill calculator, disabled aggregated store.
Key exports: `FlightSummary`, `FlightLeg.legs(byfields:)`, `TimeRange`, `Trips`, `Trip`, `Visit`, `FuelTanks`, `FuelAnalysis`, `AircraftPerformance`, `AggregatedDataOrganizer`
→ Full doc: analysis.md

## UI

### ui-map-graphs
Screen map (split view, log tab bar, stats tab bar), map track overlay and graphs (`GCSimpleGraphView`), one-way leg → map/graph linking, the SwiftUI Frequencies tab (per-flight COM1 timeline from the Bingo index, numbered handoff markers), reusable live position (GPS locate toggle, aircraft icon, one-minute lead vector), `FlightLogViewModel` / `TableDataSource` / `DisplayContext` presentation pattern, observer leaks, accessibility gaps.
Key exports: `MainSplitViewController`, `LogTabBarController`, `LogMapGraphsViewController`, `FrequencyTimelineViewController`, `FrequencyTimelineViewModel`, `LiveLocation`, `OwnshipMapContent`, `FlightDataMapOverlay`, `FlightDataMapOverlayView`, `FlightLogViewModel`, `TableDataSource`, `DisplayContext`
→ Full doc: ui-map-graphs.md

## Python lab

### flightreconcile [project]
Reference implementations validated on the real corpus: ForeFlight navlog vs G1000 reconciliation (layers A/B/C), corridor routing comparison, frequency prediction. Models graduate to Swift with parity fixtures.
Key exports: `Navlog`, `PlannedWaypoint`, `Reconciliation`, `find_logs`, `FreqModel`, `route_progress`, `rejoin_index`
→ Full doc: flightreconcile.md

## Tracking

### known-issues
Dated (2026-09-27) inventory of verified bugs: build (B), correctness (C), import/sync (I), upload (U), UI (X). Referenced by id from the plans.
→ Full doc: known-issues.md

## Plans and proposals

Not INDEX modules; linked here for discovery.

- `plans/modernisation.md`: roadmap ordered by the app's core jobs (post-flight import + FlySto upload, fuel, frequencies): build/CI, import + upload, FlightLogKit, frequency review + Bingo, fuel check, plan vs actual, UI migration.
- `plans/upload-and-import.md`: LogLibrary actor, derived vs CloudKit user-state stores, tombstones, FlySto-only `UploadCoordinator`, Mac Catalyst as the iCloud Drive hub.
- `plans/plan-vs-actual.md`: position relative to the plan; one `RouteTracker`, log replay and live GPS sources, Route tab; ForeFlight navlog deferred.
- `future/frequency-bingo.md`: ATC frequency prediction from the pilot's own logs; index, model and per-flight timeline built, plan mode next.
