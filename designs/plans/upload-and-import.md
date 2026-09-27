# Plan: upload and import pipeline

> Status: **proposal** (2026-09-27), scope decisions from the author folded in the
> same day: **FlySto only (Savvy removed)**, Mac Catalyst stays. Nothing built. Replaces the as-built flow in
> `../log-import-sync.md` and `../remote-upload.md`. Parent roadmap:
> `modernisation.md` (phases 2 and 3).

## Goals

1. One tap from SD card to library, **never blocking the UI**, with visible progress.
2. **No resurrection, no duplicates**: a deleted log stays deleted on every device.
3. **User state syncs** across iPad / iPhone / Mac: fuel entries, registrations,
   upload status, attached plans. Derived data does not need to.
4. Uploads are a **real queue**: serial per service, persisted, retried with
   backoff, one token refresh at a time, auth only ever prompted by the user.
5. Every piece testable without a device or a network.

## Decisions

| Area | Choice | Why | Rejected |
|---|---|---|---|
| Source of truth | **Files stay the truth**; derived Core Data is a rebuildable cache | 459 logs re-parse in minutes; any derived-schema change is just a version bump | Syncing derived records (conflict churn, each device re-derives anyway) |
| Store split | **Two Core Data stores in one `NSPersistentCloudKitContainer`**: `Derived` (local, no CloudKit) and `UserState` (CloudKit) | Syncs exactly the non-reproducible data (the table in `log-import-sync.md`) | Enabling CloudKit on the whole model (what the disabled `enableCloudKit` path does) |
| Cross-store links | **By `log_file_name` / `system_id` string keys**, no relationships | Core Data cannot relate across stores; names are already the identity | |
| Persistence tech | **Stay on Core Data** | Mature CloudKit mirroring, existing model, migration cost of SwiftData buys nothing here | SwiftData |
| File location | **One location**: the iCloud container `Documents/` when available, local `Documents/` only as fallback | Removes the two-way copy (`syncCloudLogic`) and the resurrection bug class | Keeping the mirror and patching it |
| Deletion | **Tombstone** (`HiddenLog` in UserState) checked by import and sync; optional "also delete file" | Survives re-import from the SD card, which still holds the file | Deleting the file only (current) |
| Identity | file name, plus size and a hash of the first 64 KB to detect a partial or changed copy | Names are unique per power-on but not guaranteed across aircraft | Name only |
| Concurrency | `actor LogLibrary` (files, import, sync) + background `NSManagedObjectContext` per task | Ends the `viewContext`-on-4-queues problem | More `dispatchPrecondition`s |
| Services | **FlySto only.** Savvy is removed (code, entity, token, WebKit login) in phase 0 of `modernisation.md` | Savvy is no longer used; one service halves the upload surface | Keeping Savvy behind a toggle |
| Upload model | `actor UploadCoordinator` over a persisted `UploadRecord` queue; FlySto behind a small `UploadService` protocol **as a test seam** (a fake conformer), not for pluggability | Status machine in one place, testable without network | Per-service `Operation` subclasses; a plugin framework for one service |
| Mac | **Mac Catalyst stays**, as the iCloud Drive sync hub (and SD import on the Mac) | The Python lab (`logfinder.py`) reads the same iCloud Drive folder on the Mac, so its layout is a contract | |
| Auth UI | `ASWebAuthenticationSession`, started only from a user action; services enter `needsSignIn` otherwise | No surprise Safari on viewing a log | Auto-prompt from queue |
| Secrets | Keychain (consider `kSecAttrSynchronizable` so a sign-in covers all devices) | UserDefaults is backed up in clear | |
| Background | Phase A: foreground drain + `beginBackgroundTask`. Phase B only if needed: `BGProcessingTask` + background `URLSession` upload tasks from files | A batch is tens of MB; the complexity of background sessions is not justified until proven | Background sessions first |

## Import flow

```
Picker (.folder / .commaSeparatedText, also Files "Open in", Mac drag and drop)
  └─ Task { await library.import(urls) }                 off main
       hold security scope for the whole task (no bookmarks needed)
       discover: one deep coordinated enumeration, classify by name
       filter: known files, HiddenLog tombstones, partial copies
       copy: coordinated write into the container Documents/
       emit AsyncStream<ImportProgress>                  banner in UI
  └─ indexer: bounded TaskGroup (2) → quick parse → full parse, background context
  └─ on new flight logs: uploadCoordinator.enqueue(new, reason: .imported)
```

Downloads: files evicted on another device need
`startDownloadingUbiquitousItem` before parsing; the metadata query reports
download status, so the indexer waits on it rather than failing.

Migration (once): move any file only in local `Documents/` into the container,
convert `FlightFlyStoRecord` into `UploadRecord` keeping the FlySto `fileId`
(Savvy records are simply dropped), copy fuel and aircraft user fields into UserState.

## Upload engine

```swift
protocol UploadService: Sendable {
    var id: ServiceID { get }                       // .flysto (a fake in tests)
    func state() async -> ServiceState              // .disabled, .needsSignIn, .ready
    func signIn(from anchor: ASPresentationAnchor) async throws
    func upload(_ log: LogFileRef) async throws -> UploadReceipt
    func remoteURL(for receipt: UploadReceipt) -> URL?
}
```

`UploadRecord(log_file_name, service, state, attempts, last_error, next_retry,
receipt, updated)`, with states `queued → uploading → uploaded | failed`.

Error classes, decided **inside each service**, never by callers:

| Class | Examples | Action |
|---|---|---|
| `duplicate` | FlySto 409 | mark uploaded |
| `auth` | 401, refresh rejected | service → `needsSignIn`, pause its queue, one banner |
| `transient` | network, 5xx, timeout | retry with backoff (1 min, 5 min, 30 min, then manual) |
| `permanent` | 400 with body | failed with a readable reason; no retry |

- **One worker per service, serial.** FlySto refreshes its token only when
  expired or after a 401, inside the service actor (single flight).
- Zips go to a temporary directory and are deleted after the request.
- `HTTPClient` protocol wraps `URLSession` so services test against recorded
  responses; the coordinator tests against fake services.
- "Automatic" means **after import** (and on reconnect), never on display.
- UI: per-service chip on each list row; an Uploads screen listing queue and
  failures with reasons, "retry all", "sign in" when paused.

## Open questions

- Does FlySto support PKCE? If so, drop the bundled client secret.

## Mac Catalyst

The Mac is where the library meets iCloud Drive and the Python lab, so:

- **One file location pays off most here**: the iPad writes straight into the
  iCloud Drive container, and the Mac (and `flightreconcile`) sees new logs
  without the app having to run and copy them.
- **Keep the folder layout stable** (`Documents/` flat, `log_*.csv`, `sys_*.json`):
  `logfinder.py` defaults to this directory.
- Keep `.selectedFile` as the Mac import default (SD card readers mount as
  volumes); fix I5 so picking a folder still works.
- Sign-in: `ASWebAuthenticationSession` works on Catalyst, which removes today's
  `SafariURLHandler` / `OAuthSwiftOpenURLExternally` split.
- Add menu commands (Import, Upload pending) with keyboard shortcuts.

## Phasing

1. **LogLibrary actor + background contexts** behind today's UI, fixing I1-I9
   (`../known-issues.md`). Tests: import fixtures into a temp container.
2. **Store split + CloudKit UserState + migration.** Tombstones.
3. **UploadCoordinator + FlySto service + Keychain**, fixing U1-U4, U6-U8.
4. Uploads screen and list chips (can be the first SwiftUI screen).
5. Only if needed: background upload sessions.

## Gotchas to design for

- CloudKit mirroring requires every attribute optional or defaulted and no
  unique constraints; enforce uniqueness in code on the string keys.
- A second device may see a `UploadRecord` for a log whose file has not
  downloaded yet; the list must tolerate state without a derived record.
- Security-scoped access must wrap the entire async import, including copying.
- Keep the file name convention: `flightreconcile/logfinder.py` and the
  frequency index key off `log_file_name`.
