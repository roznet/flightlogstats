# Log import and iCloud sync

> As-built (rewritten 2026-09-30 with phase 1 step 1 of `plans/upload-and-import.md`).
> How a log gets from the SD card into the library, where files and records are
> kept, and how other devices' logs arrive. Owners: `LogLibrary` (files) and
> `FlightLogOrganizer` (records). The `+` sheet is in `ui-map-graphs.md`.

## Data flow

```
SD card ──UIDocumentPicker (open in place)──> PostFlightImportModel.start
   FlightLogOrganizer.importLogs(from:selection:)      async, off main
     known snapshot (names, system ids, newest date)    on worker
     LogLibrary.importFiles                              any thread, holds the security scope
       discover      one coordinated deep enumeration, each file once, hidden files skipped
       filterMissing known record, or already in the folder (downloaded or not)
       select        LogLibrary.Selection (import method setting)
       confirm       above 150 new files, the sheet asks
       copyIn        coordinated write into the library folder; rpt_ -> sys_<id>.json
     addMissingRecordsFromLocal                          on worker
       add(aircrafts:) + addMinimum (record + quick parse)
       updateRecords(count: 2)                           full parse, batches, newest first
   Uploads.uploadAfterImport(new logs)                   flights only, automatic mode
```

## Decisions

| Area | Choice | Consequence |
|---|---|---|
| Source of truth | **Files**. Core Data is a cache of derived summaries, plus user inputs and upload state | Records can be rebuilt from files; user inputs cannot |
| One location | The library folder is the iCloud Drive container `Documents/` ("Flight Log Stats", `NSUbiquitousContainers`) when iCloud is on, the app's local `Documents/` otherwise (`FlightLogOrganizer.libraryFolder`) | No two-way copy; the Mac and `flightreconcile` see new logs without the app running |
| Moving there | `openLibrary()` at launch (worker, before loading records): local-only logs and aircraft files move to iCloud Drive (`setUbiquitous`); a local copy of a file already there, downloaded or not, is **deleted** | A stale local copy cannot bring back a log deleted on another device. Files that fail to move stay local and are tried next launch |
| File identity | `lastPathComponent` (`log_YYMMDD_HHMMSS_<apt>.csv`) | Size/hash identity from the plan is not built |
| Classification | by name: `log_*.csv`, `rpt_*.csv`, `sys_*.json` (`String.logFileType`) | |
| `rpt_` files | converted to `sys_<systemId>.json` via `AvionicsSystem`, never copied | aircraft identity = Garmin System ID |
| Security scope | started on the picked URLs for the whole import, copy included | no bookmarks (the old >150 path used unscoped ones) |
| Threads | Core Data on `AppDelegate.worker` only (the scheduler queue is gone); record maps behind `synchronized(self)` for readers elsewhere | screens still read managed objects on main (see Gotchas) |
| Core Data | plain `NSPersistentContainer("FlightLogModel")`, local SQLite, `NSMergeByPropertyObjectTrumpMergePolicy` | **not synced**; CloudKit user state is step 2 of the plan |
| Parse strategy | quick parse on add, then `updateRecords`: one chain of batches at a time on worker, each batch re-dispatched so other worker work interleaves | a call while running only adds work; Rebuild Info queues every record |
| iCloud downloads | a record whose file is only in iCloud is skipped (not marked error) and its download requested once | parsed when the watcher sees it arrive |
| Record migration | `FlightLogFileRecord.currentVersion` (now 2); below it => `requiresParsing` | a bump re-parses the whole library |

## Core Data model

`FlightLogModel.xcdatamodeld` (`usedWithCloudKit="YES"`, codegen `category`, all
attributes optional, all delete rules Nullify). Current version **3**:
version 2 plus `FlightFlyStoRecord.attempts`, `last_error`, `next_retry` for the
upload queue (`remote-upload.md`); version 2 dropped `FlightSavvyRecord`.
Stores migrate by inferred lightweight migration; `testModelMigrationFromVersion1`
opens a version 1 store with the current model. Keep every old version in the
bundle.

| Entity | Holds | Derived or user? |
|---|---|---|
| `FlightLogFileRecord` | `log_file_name`, `info_status`, `version`, times, fuel start/end, totaliser, route, ICAOs, distance, max alt; to-one `aircraft_record`, `flysto_record`, `fuel_record` | derived |
| `AircraftRecord` | `system_id`, `airframe_name`, `aircraft_identifier` (registration), `fuel_max`, `fuel_tab`, `gph` | mixed: registration and performance are user input |
| `FlightFuelRecord` | added fuel L/R, target, totaliser start | user |
| `FlightFlyStoRecord` | `upload_status`, `status_date`, `upload_response` (`{fileId}`), `attempts`, `last_error`, `next_retry` | service state (the upload queue) |

Only user and service state needs to sync; everything else is reproducible
from the CSVs.

## iCloud Drive

- `watchLibrary()` (main, once, from `sceneDidBecomeActive`): one
  `NSMetadataQuery` over the ubiquitous documents scope, kept running, observing
  both `DidFinishGathering` and `DidUpdate` for that query only.
- On each change (worker): logs and aircraft files not downloaded get
  `startDownloadingUbiquitousItem` once; downloaded ones the library does not
  know trigger `addMissingRecordsFromLocal`; otherwise pending parses resume.
- `delete(info:)` removes the record and the file by a coordinated delete in the
  library folder, so the log disappears on every device. An SD card that still
  has the file imports it again (tombstones are step 2).

## Launch sequence

`AppDelegate.didFinishLaunching` queues on `worker`: nav.db → `KnownAirports` /
`KnownWaypoints`, then `openLibrary()` (resolve iCloud, move old local logs,
remove `.csv.zip` litter), `loadFromContainer()`, `addMissingRecordsFromLocal()`,
`Uploads.shared.start()`. The serial queue guarantees airports exist before any
parse needs `nearestAirport`.

## Key exports

| Symbol | Role |
|---|---|
| `LogLibrary` | files: `discover(in:)`, `filterMissing`, `select`, `importFiles(from:selection:known:...)`, `copyIn`, `exists(name:in:)`, `delete(name:)`, `migrate(local:to:)`, `removeUploadArchives` |
| `LogLibrary.Selection` | `.allMissingFromFolder`, `.sinceLatestImportedFile`, `.selectedFile([URL])`, `.afterDate` (alias `FlightLogOrganizer.LogSelectionMethod`) |
| `LogLibrary.ImportProgress`, `ImportResult` | steps for the sheet: discovering, found, copying, copied, recorded |
| `FlightLogOrganizer.shared` | records: `managedFlightLogs` (name → record), `managedAircrafts` (systemId → record), queries (`flightLogFileRecords(request:filter:)`, `first`, subscripts) |
| `importLogs(from:selection:confirmLarge:progress:)` | the `+` import; returns the copy result and new record names |
| `openLibrary`, `libraryFolder`, `watchLibrary` | one location, iCloud watcher |
| `addMissingRecordsFromLocal`, `add(aircrafts:)`, `addMinimum` | record creation (worker) |
| `updateRecords(count:force:)`, `isUpdatingRecords` | batched full parse |
| `delete(info:)`, `deleteAndResetDatabase`, `deleteLocalFilesAndDatabase` | maintenance (the last two on worker) |
| `FlightLogFileRecord` | `requiresParsing`, `parseAndUpdate(quick:)`, `updateFromFlightLog`, `ensure*Record` |
| `ProgressReport` (+ overlay) | parse progress in the list's bottom overlay |

## Gotchas

- **Screens read managed objects on main** (list cells, summary, view model
  reads) while worker writes them. Writes are confined to worker now; reads
  move with the `@Observable` `FlightLogViewModel` (modernisation phase 6).
- **Local copies are deleted at the first launch with iCloud on** when the same
  name is in iCloud Drive; they were copies made by the old two-way sync.
- A device without iCloud keeps its library local; when iCloud comes on later,
  the next launch moves it.
- **`.selectedFile` selects by path**: a found URL is selected if it is a picked
  URL or lies under one (`LogLibrary.isSelected`), so picking a folder, the Mac
  default, imports its logs.
- **nav.db coverage.** Europe + North America only; `nearestAirport` has no
  distance cutoff (C9).
- `Settings.databaseVersion` was written, never read; no longer written.
- DEBUG: `-FLSImportFolder <path>` opens the import sheet on a folder (simulator
  testing without the document picker).
