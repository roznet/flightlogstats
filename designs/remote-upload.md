# Remote upload (FlySto)

> As-built (rewritten 2026-09-30 with phase 1 step 3 of `plans/upload-and-import.md`).
> Per-log upload of the raw CSV to FlySto through a serial, persisted queue.
> Savvy Aviation was removed 2026-09-29 (`00c0366`).

## Pieces

```
Uploads.shared                  app wiring: triggers, network monitor, sign in
  UploadCoordinator (actor)     serial drain, backoff, pause for sign in, Snapshot
    UploadService (protocol)    FlyStoService.shared; a fake in tests
    UploadStore (protocol)      RecordUploadStore: FlightFlyStoRecord on worker
UploadActivity (@Observable)    the coordinator's Snapshot on main, for screens
FlyStoSignIn (@MainActor)       ASWebAuthenticationSession sign in
```

## Triggers

| Trigger | Path |
|---|---|
| After an import | `PostFlightImportModel` → `Uploads.uploadAfterImport(added)`: FlySto on, upload method automatic, flights only |
| Launch | `Uploads.start()` after records load: drains what was queued, then on every network `satisfied` (`NWPathMonitor`) |
| Scene active | `Uploads.drain()` |
| Batch | More › Upload next N flights, or the Uploads screen: `uploadNextBatch()` (`Settings.uploadBatchCount`, newest not uploaded flights) |
| One log | Summary export button → `FlightLogViewModel.startServiceSynchronization(force:)`; Upload settings popover force re-upload |
| Retry | Uploads screen › Retry all failed: `retryFailed()` |

**Never on display**: showing a log does not upload it or open a sign in page (U6).

## Queue

State lives in each log's `FlightFlyStoRecord`, in the UserState store (synced by
CloudKit, so every device knows what was uploaded):
`upload_status` (`RemoteServiceRecord.Status`), `status_date`, `attempts`,
`last_error`, `next_retry`, `upload_response` (`{fileId}`).

| Status | Meaning |
|---|---|
| `ready` | never queued |
| `pending` | queued; drained in order, newest first |
| `uploaded` | done (or FlySto answered 409) |
| `failed` | with `next_retry`: retried then; without: waits for Retry all |

`drain()` is serial (one upload at a time, a call while draining runs again at
the end). A log whose file is still in iCloud waits for its download. After a
drain, a task sleeps until the earliest `next_retry` while the app runs.

## Failure classes

Decided inside the service (`FlyStoService.classify`), never by callers:

| Class | FlySto answer | Coordinator |
|---|---|---|
| duplicate | 409 (file id kept if the body has one) | uploaded |
| auth | 401/403 still after a refresh, refresh token refused, no credential | pause (`needsSignIn`), log stays queued, attempts unchanged |
| transient | network error, 408, 429, 5xx, 503 still after a refresh | failed, retry after 1, 5, 30 min, then manual |
| permanent | 400 and other 4xx, unreadable file | failed, no retry; **never signs out** (U3) |

## FlySto service

- OAuth2 through OAuthSwift (`secrets.json`: consumer key/secret, authorize,
  token, upload, log files URLs, callback `flightlogstats://ro-z.net/oauth/flysto`).
- **Credential in the Keychain** (`net.ro-z.flightlogstats.flysto`, device only,
  after first unlock), moved from UserDefaults on first use (U4). Device only so
  two devices never refresh the same refresh token.
- **Refresh only when needed**: before a request if the token is expired, or once
  after a 401/403/503. One refresh at a time (`refreshTask`), concurrent callers
  wait for it (U2).
- **Sign in only from a user action**: `FlyStoSignIn` with
  `ASWebAuthenticationURLHandler` on iOS and Mac Catalyst; a random `state` is
  sent (checked when FlySto returns it). The callback, or its cancellation,
  reaches `OAuthSwift.handle` through `SceneDelegate`.
- Upload: log zipped in a temporary folder, POSTed, folder removed (U7). The
  response `{fileId}` is kept; `logPage(for:)` turns it into
  `https://www.flysto.net/logs/<id>` (Open in FlySto).

## Key exports

| Symbol | Role |
|---|---|
| `Uploads`, `Uploads.shared` | triggers, sign in / out |
| `UploadCoordinator`, `Snapshot`, `Phase`, `backoff` | queue |
| `UploadService`, `ServiceState`, `UploadFailure`, `UploadReceipt`, `UploadJob` | service contract |
| `UploadStore`, `RecordUploadStore`, `RecordUploadStore.Row` | persisted queue, Uploads screen rows |
| `UploadActivity` | observable snapshot for SwiftUI |
| `FlyStoService`, `FlyStoService.classify`, `Outcome`, `zip`, `fileId(from:)` | FlySto |
| `FlyStoSignIn` | sign in UI |
| `KeychainStore` | generic password storage |
| `FlightLogFileRecord.flystoStatus`, `flystoLastError`, `flystoReceipt` | per-log accessors |
| `BugReportViewController` | zips 24 h of logs to `Secrets["flightlogstats.bugreport"]` |

## Gotchas

- **No background execution**: uploads run while the app is in the foreground;
  the queue resumes at the next launch or activation.
- **Upload state syncs, the credential does not** (decided 2026-09-30): the queue
  and statuses are in the UserState store, the FlySto sign in stays per device in
  its Keychain. A log queued on the iPad and drained by the Mac before sync
  settles may be uploaded twice; FlySto answers 409 → uploaded.
- **Not verified against FlySto from this machine**: the sign in page on Mac
  Catalyst and FlySto's handling of `state` need a check on a device.
- Tests: `TestUploads` (fake service and in-memory store, classification,
  zip, Keychain, record store). No network test.
