# Known issues

> Dated review snapshot, 2026-09-27. Verified by reading code (no build or run was
> possible: Linux container). Mark items resolved with the commit; do not delete.
> Items marked (inferred) are behaviour predicted from code, not observed.

## Build (blocking)

| # | Issue | Where |
|---|---|---|
| B1 | rzflight pinned at 1.0.4, which lacks `KnownWaypoints` / `RoutePointResolver` used since `a3636bc` | `Package.resolved`, `AppDelegate.swift` |
| B2 | rzutils-touch 1.0.7 `Package.swift`: tools 5.5 with `.iOS(.v16)`; current Xcode rejects it. Only used for `GCSimpleGraph*` and one import | upstream |
| B3 | `RZData` imported by 9 files but not a declared package product | `project.pbxproj` |
| B4 | `Package.resolved` v1 format, no rzutils pin, stale pins (BrightFutures, Erik, FileKit, Kanna, Swifter) | |
| B5 | CI builds for "iPhone 11" on `macOS-latest`, runs no tests, no LFS checkout | `.github/workflows/main.yml` |
| B6 | Orphan sources not in any target: `DataFrame.swift`, `GroupBy.swift`, `ValueStats.swift`, `CategoricalStats.swift` | `Source/` |
| B7 | README tells contributors to run `airports.py` (obsolete; nav.db replaced it). `garmin2fdr.py` references undefined names | `README.md`, `python/` |

## Correctness

| # | Issue | Where |
|---|---|---|
| C1 | `FuelTanks.isAlmostEqual` compares self with self (always true). Latent: its only caller chain (`AircraftRecord.isAlmostEqual`) has no live caller | `FuelTanks.swift` |
| C2 | `Trip` `NmpG` converts distance to `UnitVolume.aviationGallon` | `Trip.swift` |
| C3 | categorical pass resets `builtValues` not `builtCategorical`; coordinate frame uses raw `dates`; `lastindex` not reset | `FlightData.convertDataFrame` |
| C4 | quoted field containing a space leaves quoted mode; lone `\r` throws | `CsvParser.swift` |
| C5 | date shortcut mis-dates 10/11/12 s gaps; `DateFormatter` without POSIX locale | `FlightData.ParsingState` |
| C6 | wind components computed against CRS rather than TRK | `FieldCalculations.swift` |
| C7 | totaliser integrated per sampled row under quick parse (inferred ~300× low) | `FieldCalculations.swift` |
| C8 | fuel start/end assumed in gallons, no unit conversion from the log | `FlightSummary.swift` |
| C9 | `nearestAirport` has no distance cutoff; outside nav.db coverage a wrong airport is recorded | `FlightSummary.swift` |
| C10 | `GpH` divides by moving time | `FlightSummary+Field.swift`, `Trip.swift` |
| C11 | `FuelTanks ==` compares totals only, so `FuelAnalysis.Inputs` equality ignores the left/right split: moving fuel between tanks does not trigger `didWrite`, so the fuel table is not rebuilt (inferred) | `FuelTanks.swift`, `FlightLogViewModel.swift` |

## Import and sync

| # | Issue |
|---|---|
| I1 | deleted logs are restored from iCloud on next sync |
| I2 | import (search, coordinate, copy) runs synchronously on main |
| I3 | security scope released before the ">150 files" deferred copy (inferred failure on device) |
| I4 | files found twice (deep enumerator + explicit `data_log` recursion); completion per picked URL |
| I5 | `.selectedFile` with a folder picked imports nothing |
| I6 | `NSMetadataQuery` observer added on every activation, query never stopped, no live updates |
| I7 | `updateRecords` resets its state right after scheduling the next batch |
| I8 | main-queue `viewContext` used from 4 queues; unsynchronised `managedFlightLogs` |
| I9 | DEBUG "Delete last" / "Reset Database" trap on `dispatchPrecondition` |
| I10 | Core Data not synced: user inputs and upload status are per device |

## Upload

| # | Issue |
|---|---|
| U1 | `RequestQueue.Item` is a synchronous `Operation` wrapping async work: batch runs in parallel, completion fires early |
| U2 | parallel FlySto token refresh on one refresh token (inferred credential wipe cascade) |
| U3 | HTTP 400 classed as `denied`, wipes credentials |
| U4 | OAuth state check disabled; tokens in UserDefaults; Savvy token logged |
| U5 | Savvy: no retry, no token invalidation, no `.newFileUploaded` post. *To be resolved by removing Savvy (decided 2026-09-27)* |
| U6 | viewing a log in automatic mode can open an auth screen unprompted |
| U7 | `.csv.zip` files left in `Documents/` |
| U8 | `secrets.sample.json` lacks `flysto.logFilesUrl`, `flightlogstats.bugreport` |

## UI

| # | Issue |
|---|---|
| X1 | block-based `NotificationCenter` observers never removed; accumulate per appearance / cell display |
| X2 | `StatsTabBarController` casts the wrong tab index |
| X3 | no accessibility, no Dynamic Type |
| X4 | map renderer draws all points per tile; zoom reset on every record update |
| X5 | `ErrorManager` never receives errors; failures only reach the log |
