# Known issues

> Dated review snapshot, 2026-09-27. Verified by reading code (no build or run was
> possible: Linux container). Mark items resolved with the commit; do not delete.
> Items marked (inferred) are behaviour predicted from code, not observed.
> Phase 0 fixes (2026-09-29) were also written without a local build; their
> tests run in CI (`ios.yml`). Phase 1 steps 1, 3, 4 (2026-09-30) were built and
> unit tested locally (simulator), not on a device with an SD card or FlySto.

## Build (blocking)

| # | Issue | Where |
|---|---|---|
| B1 | ~~rzflight pinned at 1.0.4, which lacks `KnownWaypoints` / `RoutePointResolver` used since `a3636bc`~~ Resolved: 1.3.0 (`8cdd2e5`) | `Package.resolved`, `AppDelegate.swift` |
| B2 | ~~rzutils-touch 1.0.7 `Package.swift`: tools 5.5 with `.iOS(.v16)`; current Xcode rejects it~~ Resolved: 1.0.8 (`8cdd2e5`). Only used for `GCSimpleGraph*` and one import | upstream |
| B3 | ~~`RZData` imported by 9 files but not a declared package product~~ Resolved: linked as a product (`60a8949`) | `project.pbxproj` |
| B4 | ~~`Package.resolved` v1 format, no rzutils pin~~ (v3 since `8cdd2e5`). ~~Stale pins (BrightFutures, Erik, FileKit, Kanna, Swifter)~~ Not a bug (2026-09-29): they are dependencies declared by OAuthSwift 2.2.0's `Package.swift` (for its tests), so SPM resolves and pins them; removing them would only be undone by the next resolve. They go when OAuthSwift does | |
| B5 | ~~CI builds for "iPhone 11" on `macOS-latest`, runs no tests, no LFS checkout~~ Resolved 2026-09-28: `ios.yml` runs the unit target | `.github/workflows/main.yml` |
| B6 | ~~Orphan sources not in any target: `DataFrame.swift`, `GroupBy.swift`, `ValueStats.swift`, `CategoricalStats.swift`~~ Resolved: deleted (`c09955d`) | `Source/` |
| B7 | ~~README tells contributors to run `airports.py` (obsolete; nav.db replaced it)~~ Resolved: script deleted, README rewritten (`c09955d`). Still open: `garmin2fdr.py` references undefined names | `README.md`, `python/` |

## Correctness

| # | Issue | Where |
|---|---|---|
| C1 | ~~`FuelTanks.isAlmostEqual` compares self with self (always true)~~ Resolved: per tank against the other, converted (`1474758`) | `FuelTanks.swift` |
| C2 | ~~`Trip` `NmpG` converts distance to `UnitVolume.aviationGallon`~~ Resolved: nautical miles (`93240d9`) | `Trip.swift` |
| C3 | ~~coordinate frame uses raw, un-deduplicated `dates`~~ Resolved: all three frames built from one `keptRows(dates:)` (`ecbd8ee`, tested on the perspective and flight2 logs). The map now drops the rows before a time reset, like the other frames | `FlightData.convertDataFrame` |
| C4 | ~~quoted field containing a space leaves quoted mode; lone `\r` throws~~ Resolved (`efc121a`) | `CsvParser.swift` |
| C5 | ~~date shortcut mis-dates 10/11/12 s gaps; `DateFormatter` without POSIX locale~~ Resolved: exact seconds-of-day offset, POSIX locale; a row whose date format is never identified is no longer kept without a date (`d14c589`). The TBM930 log had a 71 s gap dated +1 s | `FlightData.ParsingState` |
| C6 | wind components computed against CRS rather than TRK | `FieldCalculations.swift` |
| C7 | ~~totaliser integrated per sampled row under quick parse (inferred ~300× low)~~ Resolved: integrated over the elapsed time since the previous parsed row (`3791b73`) | `FieldCalculations.swift` |
| C8 | ~~fuel start/end assumed in gallons, no unit conversion from the log~~ Resolved: converted from the units line to the store unit (`b2c4050`). Litre spellings are guessed (no litre log seen); records parsed before are not re-parsed | `FlightSummary.swift` |
| C9 | `nearestAirport` has no distance cutoff; outside nav.db coverage a wrong airport is recorded | `FlightSummary.swift` |
| C10 | `GpH` divides by moving time | `FlightSummary+Field.swift`, `Trip.swift` |
| C11 | ~~`FuelTanks ==` compares totals only, so `FuelAnalysis.Inputs` equality ignores the left/right split~~ Resolved: per tank (`3f2ab0a`) | `FuelTanks.swift`, `FlightLogViewModel.swift` |

## Import and sync

| # | Issue |
|---|---|
| I1 | ~~deleted logs are restored from iCloud on next sync~~ Resolved for deletions: one library folder, a delete removes the iCloud Drive file, stale local copies removed at launch (`d6dec18`). Still open: an SD card that has the file imports it again (tombstones, step 2) |
| I2 | ~~import (search, coordinate, copy) runs synchronously on main~~ Resolved: `importLogs` async, off main (`d6dec18`) |
| I3 | ~~security scope released before the ">150 files" deferred copy~~ Resolved: the scope is held for the whole import, the confirmation happens inside it (`d6dec18`) |
| I4 | ~~files found twice; completion per picked URL~~ Resolved: one deep enumeration, deduplicated (`d6dec18`) |
| I5 | ~~`.selectedFile` with a folder picked imports nothing~~ Resolved: a picked folder selects the logs under it (`26d469b`) |
| I6 | ~~`NSMetadataQuery` observer added on every activation, no live updates~~ Resolved: one query started once, gathering and updates observed (`d6dec18`) |
| I7 | ~~`updateRecords` resets its state right after scheduling the next batch~~ Resolved: one chain of batches at a time (`d6dec18`) |
| I8 | main-queue `viewContext` used from 4 queues; unsynchronised `managedFlightLogs`. Partly resolved (`d6dec18`, `f1419fd`): writes on `worker` only (scheduler and request queues gone), record maps locked. Still open: screens read managed objects on main |
| I9 | ~~DEBUG "Delete last" / "Reset Database" trap on `dispatchPrecondition`~~ Resolved: run on worker (`d6dec18`) |
| I10 | Core Data not synced: user inputs and upload status are per device |

## Upload

| # | Issue |
|---|---|
| U1 | ~~`RequestQueue.Item` is a synchronous `Operation`: batch runs in parallel~~ Resolved: serial `UploadCoordinator` (`f1419fd`) |
| U2 | ~~parallel FlySto token refresh on one refresh token~~ Resolved: refresh only when expired or after a 401, one at a time (`f1419fd`) |
| U3 | ~~HTTP 400 classed as `denied`, wipes credentials~~ Resolved: permanent failure for that log, credential kept (`f1419fd`) |
| U4 | ~~tokens in UserDefaults~~ Resolved: Keychain (`f1419fd`). A random state is sent, but a missing state is still allowed (FlySto's behaviour not verified). ~~Savvy token logged~~ (Savvy removed, `00c0366`) |
| U5 | ~~Savvy: no retry, no token invalidation, no `.newFileUploaded` post~~ Resolved: Savvy removed (`00c0366`) |
| U6 | ~~viewing a log in automatic mode can open an auth screen unprompted~~ Resolved: no upload on display; sign in only from a button (`f1419fd`) |
| U7 | ~~`.csv.zip` files left in `Documents/`~~ Resolved: zipped in a temporary folder; old ones removed at launch (`d6dec18`, `f1419fd`) |
| U8 | ~~`secrets.sample.json` lacks `flysto.logFilesUrl`, `flightlogstats.bugreport`~~ Resolved (`c09955d`) |

## UI

| # | Issue |
|---|---|
| X1 | block-based `NotificationCenter` observers never removed; accumulate per appearance / cell display |
| X2 | ~~`StatsTabBarController` casts the wrong tab index~~ Resolved: the dead cast is removed, the trips tab keeps opening on `.trips` (`75902d3`) |
| X3 | no accessibility, no Dynamic Type |
| X4 | map renderer draws all points per tile; zoom reset on every record update |
| X5 | `ErrorManager` never receives errors; failures only reach the log |
