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
SD card to library: the `+` import off main (`LogLibrary`: discovery, selection, coordinated copy holding the security scope), one library folder (iCloud Drive container, local only without iCloud; old local copies moved or removed at launch), iCloud Drive watcher (download, record), quick then batched full parse on worker, Core Data model (derived vs user fields, version 3), record versioning. Core Data is local only (CloudKit user state is step 2).
Key exports: `LogLibrary`, `LogLibrary.Selection`, `ImportProgress`, `FlightLogOrganizer`, `importLogs(from:selection:)`, `openLibrary`, `watchLibrary`, `addMissingRecordsFromLocal`, `updateRecords(count:force:)`, `FlightLogFileRecord`, `ProgressReport`
→ Full doc: log-import-sync.md

### remote-upload
FlySto upload through a serial, persisted queue: `UploadCoordinator` over an `UploadService`, state in `FlightFlyStoRecord` (attempts, last error, next retry), failure classes (duplicate, auth pauses, transient backs off 1/5/30 min, permanent), triggers (after import, launch, network back, batch, per log; never on display), single-flight token refresh, Keychain credential, `ASWebAuthenticationSession` sign in. Savvy removed 2026-09-29.
Key exports: `Uploads`, `UploadCoordinator`, `UploadService`, `UploadFailure`, `RecordUploadStore`, `UploadActivity`, `FlyStoService`, `FlyStoSignIn`, `KeychainStore`, `FlightFlyStoRecord`, `RemoteServiceRecord.Status`
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
Screen map (split view, log tab bar, stats tab bar), map track overlay and graphs (`GCSimpleGraphView`), one-way leg → map/graph linking, the SwiftUI Frequencies tab (per-flight COM1 timeline from the Bingo index, numbered handoff markers), the Frequency Bingo screen (modal, `BingoLaunch`; plan mode, and live mode on the locate toggle), the post-flight import sheet and the Uploads screen (SwiftUI), per-row FlySto status, reusable live position (GPS locate toggle, aircraft icon, one-minute lead vector), `FlightLogViewModel` / `TableDataSource` / `DisplayContext` presentation pattern, observer leaks, accessibility gaps.
Key exports: `MainSplitViewController`, `PostFlightImportViewController`, `PostFlightImportModel`, `UploadsViewController`, `UploadsModel`, `LogTabBarController`, `LogMapGraphsViewController`, `FrequencyTimelineViewController`, `FrequencyTimelineViewModel`, `FrequencyBingoViewController`, `FrequencyBingoViewModel`, `BingoLaunch`, `LiveLocation`, `OwnshipMapContent`, `FlightDataMapOverlay`, `FlightDataMapOverlayView`, `FlightLogViewModel`, `TableDataSource`, `DisplayContext`
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
- `plans/upload-and-import.md`: phase 1; steps 1 (LogLibrary, one iCloud location), 3 (upload queue) and 4 (`+` sheet, Uploads screen) built 2026-09-30; step 2 (CloudKit user state, tombstones) next.
- `plans/plan-vs-actual.md`: position relative to the plan; one `RouteTracker`, log replay and live GPS sources, Route tab; ForeFlight navlog deferred.
- `future/frequency-bingo.md`: ATC frequency prediction from the pilot's own logs; index, model, per-flight timeline, plan mode and live mode built (standalone tool, `RZFlight.Route` / `FlightExchange` routes, current / previous / next radio, GPS ladder with handoff distance/ETA); confirmation taps next.
