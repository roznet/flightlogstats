# Log import and iCloud sync

> As-built (reviewed 2026-09-27, synced 2026-09-29). How a log gets from the SD card into the library,
> how files and records are kept, and how iCloud sync works. Owner:
> `FlightLogOrganizer`. Modernisation: `plans/upload-and-import.md`.

## Data flow

```
SD card ──UIDocumentPicker (open in place, security scoped)──┐
                                                             v
   FlightLogOrganizer.search(in:)       coordinated, deep enumeration, classify by name
   filterMissing / buildImportList      dedupe by file name, LogSelectionMethod
   importFiles                          copy into app Documents/ (sync, on main)
   addMissingRecordsFromLocal           scheduler: add(aircrafts:) + addMinimum
       addMinimum                       FlightLogFileRecord + quick parse (1 row / 5 min)
   updateRecords(count: 2)              worker: full parse, newest first, batches
   syncCloud()                          Documents/ <-> iCloud Drive Documents/
```

## Decisions (as found)

| Area | Choice | Consequence |
|---|---|---|
| Source of truth | **Files**. Core Data is a cache of derived summaries, plus a few user inputs | Records can be rebuilt from files; user inputs cannot |
| File identity | `lastPathComponent` (`log_YYMMDD_HHMMSS_<apt>.csv`) | No content hash; no Core Data uniqueness constraint |
| Classification | by name: `log_*.csv`, `rpt_*.csv`, `sys_*.json` (`String.logFileType`) | |
| `rpt_` files | converted to `sys_<systemId>.json` via `AvionicsSystem`, never copied | aircraft identity = Garmin System ID, leading zeros stripped |
| Local store | app `Documents/`, mirrored to the iCloud Drive container published as "Flight Log Stats" (`NSUbiquitousContainers`) | pilots can reach logs in Files |
| Core Data | plain `NSPersistentContainer("FlightLogModel")`, local SQLite, `NSMergeByPropertyObjectTrumpMergePolicy` | **not synced** |
| CloudKit | code present but disabled: `enableCloudKit = false`. Entitlements still declare `iCloud.net.ro-z.flightlogstats.records` | upload status, fuel entries and registrations are per device |
| Aggregated store | `AggregatedDataOrganizer` (FMDB, 60 s buckets) | **disabled in production** (`aggregatedData = nil`), only tests use it |
| Parse strategy | quick parse on add, full parse in batches of 2 later | list populates fast, details fill in |
| Record migration | `FlightLogFileRecord.currentVersion` (now 2); below it => `requiresParsing` | a bump re-parses the whole library |

## Core Data model

`FlightLogModel.xcdatamodeld` (`usedWithCloudKit="YES"`, codegen `category`, all
attributes optional, all delete rules Nullify). Current version **2**
(`FlightLogModel 2.xcdatamodel`): version 1 without `FlightSavvyRecord` and
`FlightLogFileRecord.savvy_record`, dropped with Savvy (`00c0366`). Stores
migrate by inferred lightweight migration (the `NSPersistentStoreDescription`
defaults); `testModelMigrationFromVersion1` opens a version 1 store with the
current model. Keep every old version in the bundle: Core Data finds the source
model there.

| Entity | Holds | Derived or user? |
|---|---|---|
| `FlightLogFileRecord` | `log_file_name`, `info_status`, `version`, times (engine/moving/flying), fuel start/end, `fuel_totalizer_total`, `route`, start/end ICAO, distance, max alt; to-one `aircraft_record`, `flysto_record`, `fuel_record` | derived |
| `AircraftRecord` | `system_id`, `airframe_name`, `aircraft_identifier` (registration), `fuel_max`, `fuel_tab`, `gph` | mixed: registration and performance are user input |
| `FlightFuelRecord` | added fuel L/R, target, totaliser start | user |
| `FlightFlyStoRecord` | `upload_status`, `status_date`, `upload_response` (`{fileId}`) | service state |

This split is the key fact for any redesign: **only the user and service state
needs to sync**; everything else is reproducible from the CSVs.

## iCloud file sync

`syncCloud()` resolves the ubiquity container, lists local files, and runs an
`NSMetadataQuery` (`NSMetadataQueryUbiquitousDocumentsScope`) on main.
`didFinishGathering` → `syncCloudLogic(localUrls:cloudUrls:)`:

- local-only → plain `FileManager.copyItem` into the ubiquity folder
  (uncoordinated write);
- cloud-only → coordinated read, copy to `Documents/`, then
  `addMissingRecordsFromLocal()`.

Runs on every scene activation (`SceneDelegate.sceneDidBecomeActive`). No live
`DidUpdate` handling, so changes arriving while the app is open are missed.

## Launch sequence

`AppDelegate.didFinishLaunching` queues on `worker`: nav.db → `KnownAirports` /
`KnownWaypoints`, then `loadFromContainer()` and `addMissingRecordsFromLocal()`.
The serial queue guarantees airports exist before any parse needs
`nearestAirport`.

## Key exports

| Symbol | Role |
|---|---|
| `FlightLogOrganizer.shared` | library singleton: container, `managedFlightLogs` (name → record), `managedAircrafts` (systemId → record) |
| `search(in:completion:)` | security-scoped, coordinated discovery |
| `filterMissing`, `buildImportList(urls:method:)`, `isSelected(url:in:)`, `importFiles` | dedupe, select, copy |
| `importAndAddRecordsForFiles(urls:method:process:)` | picker entry point |
| `addMissingRecordsFromLocal`, `add(aircrafts:)`, `addMinimum` | record creation |
| `updateRecords(count:force:)` | batched full parse and version migration |
| `syncCloud`, `syncCloudLogic` | iCloud Drive two-way copy |
| `delete(info:)`, `deleteAndResetDatabase`, `deleteLocalFilesAndDatabase` | maintenance |
| `LogSelectionMethod` | `.automatic`, `.selectedFile`, ... import scope |
| `FlightLogFileRecord` | `requiresParsing`, `parseAndUpdate(quick:)`, `updateFromFlightLog`, `ensure*Record` |
| `FlightLogFile`, `FlightLogFileList` | file wrapper and sorted list |
| `ProgressReport` (+ overlay / view controller) | progress model and bottom overlay |
| `LogListTableViewController.addLog`, `documentPicker(_:didPickDocumentsAt:)` | UI entry |

## Gotchas

- **Deleted logs come back.** `delete(info:)` removes the local file only; the
  next `syncCloudLogic` copies it back from iCloud and re-creates the record.
- **Import runs on main.** Search, coordination and copying are synchronous in
  the picker callback; a full SD card freezes the UI.
- **Security scope ends before a large import.** `search` stops access in a
  `defer`; the ">150 files" path copies later through never-persisted minimal
  bookmarks. Likely fails for an SD card on iOS (unverified on device).
- **Double reporting.** The deep enumerator plus explicit `data_log` recursion
  finds files twice; with several picked URLs, `completion` runs once per URL.
- **`.selectedFile` selects by path**: a found URL is selected if it is a picked
  URL or lies under one (`FlightLogOrganizer.isSelected`, resolved and
  standardised paths), so picking a folder, the Mac default, imports its logs
  (I5, `26d469b`).
- **Observers pile up.** `syncCloud(with:)` adds an `NSMetadataQuery` observer on
  every activation and never stops the query.
- **`updateRecords` state machine**: resets `currentState = .ready` right after
  scheduling the next batch, defeating its own guard.
- **Core Data threading.** `viewContext` is used from `worker`, `scheduler`, the
  request queue and main. `-com.apple.CoreData.ConcurrencyDebug 1` should trap.
- **nav.db coverage.** Europe + North America only; `nearestAirport` has no
  distance cutoff, so a flight outside coverage gets a wrong airport, not none.
- **`Settings.databaseVersion`** is written, never read.
