# Log import and iCloud sync

> As-built (rewritten 2026-09-30 with phase 1 steps 1 and 2 of `plans/upload-and-import.md`).
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
| Core Data | `NSPersistentCloudKitContainer` with two stores (`LibraryStore`): **Derived** (local) and **UserState** (CloudKit `iCloud.net.ro-z.flightlogstats.records`), `NSMergeByPropertyObjectTrumpMergePolicy` | user state syncs, last writer wins per field; derived data never syncs |
| Parse strategy | quick parse on add, then `updateRecords`: one chain of batches at a time on worker, each batch re-dispatched so other worker work interleaves | a call while running only adds work; Rebuild Info queues every record |
| iCloud downloads | a record whose file is only in iCloud is skipped (not marked error) and its download requested once | parsed when the watcher sees it arrive |
| Record migration | `FlightLogFileRecord.currentVersion` (now 2); below it => `requiresParsing` | a bump re-parses the whole library |

## Core Data model

`FlightLogModel.xcdatamodeld`, codegen `category`, all attributes optional, no
relationships (the two stores cannot relate). Current version **4**, with two
configurations, each its own SQLite file in Application Support:

| Store (configuration) | File | Entities | Synced |
|---|---|---|---|
| Derived | `FlightLogDerived.sqlite` | `FlightLogFileRecord` | no: rebuilt from the files |
| UserState (`usedWithCloudKit`) | `FlightLogUserState.sqlite` | `AircraftRecord`, `FlightFuelRecord`, `FlightFlyStoRecord`, `HiddenLog` | CloudKit, history tracking, remote change notifications |

| Entity | Holds | Linked by |
|---|---|---|
| `FlightLogFileRecord` | `log_file_name`, `info_status`, `version`, `system_id`, times, fuel start/end, totaliser, route, ICAOs, distance, max alt | |
| `AircraftRecord` | `system_id`, `airframe_name`, `aircraft_identifier` (registration), `fuel_max`, `fuel_tab`, `gph`, `modified` (last user edit), `uuid` | `system_id` |
| `FlightFuelRecord` | added fuel L/R, target, totaliser start, `last_entered`, `uuid` | `log_file_name` |
| `FlightFlyStoRecord` | `upload_status`, `status_date`, `upload_response` (`{fileId}`), `attempts`, `last_error`, `next_retry`, `uuid` | `log_file_name` |
| `HiddenLog` | `log_file_name`, `hidden_date`, `uuid`: a deleted log (tombstone) | `log_file_name` |

`FlightLogFileRecord.aircraft_record`, `fuel_record`, `flysto_record` keep
their old names as lookups in the organizer's maps (setting one registers it
under the log's name).

**CloudKit schema is permanent in Production**: fields can be added, never
removed or renamed. Changing it: add attributes in a new model version, run
DEBUG › Initialize CloudKit Schema with an iCloud account (Development), then
deploy the schema to Production in the CloudKit console before a TestFlight or
App Store build.

**Duplicates.** Two devices can each create the record of the same log or
aircraft before syncing. `LibraryStore.deduplicate` keeps one per key, chosen
from synced values only so every device keeps the same: fuel by latest
`last_entered`, FlySto uploaded first then latest `status_date`, aircraft by
latest `modified`, tombstone by earliest date; ties by smallest `uuid`. The
others are deleted, at load and after every remote change.

**Remote changes.** `NSPersistentStoreRemoteChange` → one `reloadUserState()` on
worker per burst (1 s): refetch with refreshed values, deduplicate, drop the
logs newly hidden by another device, post `.localFileListChanged` and
`.newFileUploaded`.

**From the old single store.** Model versions 1 to 3 used one
`FlightLogModel.sqlite`. At the first launch with version 4
(`LibraryStore.migrateLegacy`), it is opened with model 3 (lightweight from 1
and 2), every record is copied into the new stores (derived records too, so
nothing is re-parsed; per-log records get their log's name from the old
relationship), and the old files are renamed `FlightLogModel-v3-backup.sqlite`.
The old file is renamed only after the copy is saved, so a copy that fails or is
interrupted runs again next launch; records already copied are not copied twice.
Tested by `testLegacyStoreSplit` from a version 1 store.

## iCloud Drive

- `watchLibrary()` (main, once, from `sceneDidBecomeActive`): one
  `NSMetadataQuery` over the ubiquitous documents scope, kept running, observing
  both `DidFinishGathering` and `DidUpdate` for that query only.
- On each change (worker): logs and aircraft files not downloaded get
  `startDownloadingUbiquitousItem` once; downloaded ones the library does not
  know trigger `addMissingRecordsFromLocal`; otherwise pending parses resume.
- `delete(info:)` leaves a `HiddenLog` tombstone, deletes the file by a
  coordinated delete in the library folder, and drops the record. Other devices
  drop theirs when the tombstone syncs; import, the watcher and `addMinimum` skip
  hidden names, so an SD card that still has the file does not bring it back.
  There is no restore yet.

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
| `delete(info:)`, `isHidden(logFileName:)` | delete with a tombstone (no UI yet) |
| `forget(info:)` | testing (DEBUG › Forget last): file, record, fuel and FlySto records removed, **no tombstone**, so re-importing the card replays import and upload |
| `reloadUserState`, `fuelRecord(logFileName:)`, `flyStoRecord(logFileName:)`, `existingAircraft(systemId:)` | user state (UserState store) |
| `LibraryStore` | store descriptions, `makeContainer`, `migrateLegacy`, `deduplicate`, `HiddenLog` |
| `initializeCloudKitSchema` | DEBUG: push the schema to CloudKit Development |
| `deleteAndResetDatabase`, `deleteLocalFilesAndDatabase` | maintenance (worker) |
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
