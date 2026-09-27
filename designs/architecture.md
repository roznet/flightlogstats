# Architecture

> As-built overview of FlightLogStats (reviewed 2026-09-27): a UIKit iPad/iPhone/Mac
> Catalyst app that imports Garmin G1000 / Perspective CSV logs, keeps them in
> iCloud Drive, derives per-flight summaries into Core Data, and uploads logs to
> FlySto and Savvy Aviation.

## What the app is

- **Input**: `log_*.csv` flight logs, `rpt_*.csv` aircraft reports and derived
  `sys_*.json` avionics files, picked from the avionics SD card.
- **Library**: every log the pilot has ever imported, synced as files through
  iCloud Drive, summarised into Core Data for the list and statistics.
- **Per-flight views**: summary tables, fuel refill calculator, graphs + map of
  the flown track with legs by waypoint / phase / comms / autopilot mode.
- **Corpus views**: trips (away-from-base grouping) and monthly statistics.
- **Upload**: FlySto (OAuth2) and Savvy (API token) per log, manual or batch.
- **Lab**: `python/flightreconcile/` is where new analyses are prototyped
  (plan vs actual, corridor comparison, frequency prediction) before any Swift.

## Layers

```
 UIKit (Main.storyboard, one file)                     ui-map-graphs.md
   MainSplitViewController
     ├─ LogListTableViewController   list, import, menu
     └─ LogTabBarController (Summary | Fuel | Graphs)  or  StatsTabBarController
          │ FlightLogViewModel, DisplayContext, TableDataSource subclasses
 ─────────┼────────────────────────────────────────────────────────────────
 Library  │ FlightLogOrganizer (singleton)                log-import-sync.md
          │   Core Data (NSPersistentContainer, local only)
          │   Documents/ <-> iCloud Drive Documents (NSMetadataQuery copy)
          │ RequestQueue -> FlyStoRequest / SavvyRequest   remote-upload.md
 ─────────┼────────────────────────────────────────────────────────────────
 Parsing  │ CsvParser -> FlightData -> RZData DataFrame   log-parsing.md
 Analysis │ FlightSummary, FlightLeg, Trips, FuelAnalysis  analysis.md
 ─────────┼────────────────────────────────────────────────────────────────
 Packages │ RZData / RZUtils* (rzutils, rzutils-touch), RZFlight (nav.db,
          │ KnownAirports, KnownWaypoints, Route), OAuthSwift, ZIPFoundation,
          │ KDTree, DeviceGuru
```

All Swift lives flat in `flightlogstats/Source/` (81 files, ~13.7k lines, four of them not compiled). There is
no module boundary between UI, storage and analysis: analysis types read
`AppDelegate.knownAirports` and `Settings.shared` directly.

## Targets and build

| Item | Value |
|---|---|
| App target | `FlightLogStats`, iOS **18.6**, `SUPPORTS_MACCATALYST`, devices 1,2, version 3.0 |
| Unit tests | `FlightLogStatsTests`, iOS 16.0, **hosted in the app** (`TEST_HOST`), XCTest |
| UI tests | template stubs only |
| Swift | `SWIFT_VERSION = 5.0`, no strict-concurrency flags |
| Secrets | `flightlogstats/secrets.json` (gitignored, bundled); a build phase copies `secrets.sample.json` if missing |
| Bundled data | `python/nav.db` (FMDB, airports + European waypoints, built by `make_nav_db.py`), `python/logFileFields.json` (field metadata) |
| LFS | `*.db` and `log_*.csv` are Git LFS. Without `git lfs pull` the fixtures and nav.db are 130-byte pointers |
| CI | `.github/workflows/main.yml`: `xcodebuild build` on "iPhone 11", no tests, no LFS |

## Concurrency model

GCD only, no async/await, no actors.

| Queue | Owner | Used for |
|---|---|---|
| `AppDelegate.worker` | serial | de facto Core Data queue, full parses, nav.db load |
| `FlightLogOrganizer.scheduler` | serial | adding new records (`addMinimum`) |
| `FlightLogOrganizer.queue` | `OperationQueue` | `NSFileCoordinator` callbacks |
| `RequestQueue.operationQueue` | `OperationQueue`, unbounded | uploads |
| main | | UI, `NSMetadataQuery`, document picker import (synchronous) |

`dispatchPrecondition(.onQueue(AppDelegate.worker))` guards many mutators, but
the context is the main-queue `viewContext`, so the Core Data threading contract
is violated by design. Change notification is `NotificationCenter` throughout
(`.logFileRecordUpdated`, `.newLocalFilesDiscovered`, `.newFileUploaded`, ...).

## Dependencies that matter

| Package | Why | State |
|---|---|---|
| **rzutils** (`RZUtils`, `RZUtilsSwift`, `RZUtilsUniversal`, `RZData`) | `DataFrame`, `ValueStats`, `GCUnit`, logging | `RZData` is imported by 9 files but is not a declared product in the pbxproj |
| **rzutils-touch** (`RZUtilsTouch`) | `GCSimpleGraphView` charts (ObjC) | 1.0.7's `Package.swift` declares tools 5.5 with `.iOS(.v16)`; current Xcode rejects it |
| **rzflight** (`RZFlight`) | `KnownAirports`, `KnownWaypoints`, `RoutePointResolver`, `RunwayWindModel` | pinned **1.0.4**, which predates `KnownWaypoints`/`RoutePointResolver`; needs a re-resolve to >= 1.3.0 (and main has the `Airport(db:ident:)` schema fix) |
| OAuthSwift | FlySto OAuth2 | |
| ZIPFoundation | zip before FlySto upload, bug report | |

`Package.resolved` is in the old v1 format, has no pin for rzutils, and still pins
packages nothing references (BrightFutures, Erik, FileKit, Kanna, Swifter).

**The app does not build as checked in** (see `known-issues.md` §Build).

## Key exports

| File | What |
|---|---|
| `AppDelegate.swift` | `AppDelegate.worker`, `.db`, `.knownAirports`, `.knownWaypoints`; nav.db load at launch |
| `SceneDelegate.swift` | `syncCloud()` on activation, OAuth callback |
| `FlightLogOrganizer.swift` | the library singleton; see `log-import-sync.md` |
| `Settings.swift` | `Settings.shared`, UserDefaults property wrappers incl. credentials |
| `Log.swift` | `Logger.app/ui/sync/net` (RZLogger) |

## Design docs map

- `log-import-sync.md`: SD card to Core Data, iCloud, record versioning.
- `remote-upload.md`: FlySto / Savvy upload.
- `log-parsing.md`: CSV parser, fields, calculated fields, DataFrames.
- `analysis.md`: summaries, legs, trips, fuel.
- `ui-map-graphs.md`: screens, map overlay, graphs, table data sources.
- `flightreconcile.md`: the Python lab (reconcile, corridor, freq).
- `known-issues.md`: dated list of verified bugs.
- `plans/modernisation.md`: the roadmap. Sub-plans for upload and plan-vs-actual.
