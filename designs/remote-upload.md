# Remote upload (FlySto, Savvy Aviation)

> As-built (reviewed 2026-09-27). Per-log upload of the raw CSV to FlySto (OAuth2,
> zipped POST) and Savvy Aviation (API token, multipart), status tracked per log in
> Core Data. Modernisation: `plans/upload-and-import.md`.

## Triggers

| Trigger | Path | Notes |
|---|---|---|
| Manual, one log | export button → `FlightLogViewModel.startServiceSynchronization` | |
| Force re-upload | `UploadSettingsViewController` popover | |
| Batch | list menu "Upload next N flights" → `FlightLogOrganizer.buildUploadList` → `RequestQueue.add(records:)` | flights only, not yet uploaded, newest first, `Settings.uploadBatchCount` (default 12) |
| "Automatic" | `LogSummaryViewController.startAutomaticUploadIfNeeded` from `viewModelHasChanged` | **only uploads the log being displayed**; nothing uploads after import (the `.newLocalFilesDiscovered` observer is commented out) |

No background execution: no `BGTaskScheduler`, no `beginBackgroundTask`, no
background `URLSession`. `UIBackgroundModes` declares `fetch` and
`remote-notification` with no handlers.

## Services

**FlySto** (`FlyStoRequest`, `FlyStoUploadRequest`, `FlyStoLogFilesRequest`)
- `OAuth2Swift` from `secrets.json`, `responseType "code"`,
  `allowMissingStateCheck = true`, callback `flightlogstats://ro-z.net/oauth/flysto`
  handled in `SceneDelegate.scene(_:openURLContexts:)`.
- Credential: `OAuthSwiftCredential` in UserDefaults (`Settings`).
- `start(attempt:)`: no credential → `authorize`; else **always** `refreshToken`
  first, then `makeRequest`. Attempt cap 2.
- Upload: zip to `<log>.csv.zip` beside the source, POST, keep `{fileId}` in
  `upload_response`. `FlyStoLogFilesRequest` turns it into
  `https://www.flysto.net/logs/<id>` (host hardcoded).
- `processSwiftOAuthError`: 503 → `tokenExpired`, 409 → `already`, 400 →
  `denied` (clears credentials), `accessDenied` → clears credentials.

**Savvy** (`SavvyRequest`, `SavvyAuthenticateViewController`)
- Token captured from a `WKWebView` redirect to `flightlogstats://`, stored in
  UserDefaults.
- `get-aircraft` → match registration (`AircraftRecord.aircraftIdentifier`,
  case-insensitive) → multipart `upload_files_api/<id>` via `URLSession.shared`.
- `"Error"` with `details == "duplicate"` → `already`. No retry (`attempt` never
  increments), no token invalidation.

## Status model

`RemoteServiceRecord.Status`: `ready`, `pending`, `uploaded`, `failed`.
`flystoStatus` / `savvyStatus` are computed over the one-to-one records, created
lazily by `ensureFlyStoStatus` / `ensureSavvyStatus`. Mapping: success/already →
uploaded; error/tokenExpired/denied → failed. `pending` is documented as
"uploaded in background" but nothing sets it; Savvy's getter defaults to it,
FlySto's to `ready`.

## Queue

`RequestQueue.shared` wraps an `OperationQueue`. `Item: Operation` holds the
record and a `UIViewController` (for auth UI), checks
`RZSystemInfo.networkAvailable()`, then runs FlySto and/or Savvy if enabled and
not uploaded (or forced). Completions hop to `AppDelegate.worker`, set status,
post `.flightLogViewModelUploadFinished`, save.

## Key exports

| Symbol | Role |
|---|---|
| `RequestQueue`, `RequestQueue.Item` | upload queue |
| `RemoteServiceRequest`, `AsyncOperation` | base class; `AsyncOperation` is unused |
| `FlyStoRequest`, `FlyStoUploadRequest`, `FlyStoLogFilesRequest` | FlySto |
| `SavvyRequest`, `SavvyAuthenticateViewController` | Savvy |
| `FlightFlyStoRecord`, `FlightSavvyRecord`, `RemoteServiceRecord.Status` | per-log status |
| `FlightLogOrganizer.buildUploadList` | batch selection |
| `BugReportViewController` | zips 24 h of logs to `Secrets["flightlogstats.bugreport"]` |

## Gotchas

- **The queue does not queue.** `Item` is a synchronous `Operation` whose
  `main()` only starts async work, so it finishes immediately: the whole batch
  runs in parallel and the barrier reports `.complete` before any upload ends.
- **Parallel token refresh.** A FlySto batch of 12 refreshes the same refresh
  token ~12 times at once. If FlySto rotates refresh tokens, most fail →
  `denied` → credentials cleared → several Safari auth flows (inferred).
- **400 logs you out.** A bad request is classed `denied` and wipes the
  credential.
- **Displaying a log can open a login screen.** In automatic mode with a service
  enabled but no credential, `startAutomaticUploadIfNeeded` triggers auth UI.
- **Secrets in UserDefaults**, not the Keychain. The Savvy token is logged in
  plain text, and the bug report uploads 24 h of logs.
- **Savvy registration**: `aircraftIdentifier` returns `""` when nil, so the
  failure reads "No matching aircraft"; no aircraft record at all skips Savvy
  silently. Savvy never posts `.newFileUploaded`, so the list does not refresh.
- **Zip litter**: `<log>.csv.zip` files accumulate in `Documents/` (and are
  therefore candidates for iCloud sync).
- **`secrets.sample.json` is incomplete**: lacks `flysto.logFilesUrl` and
  `flightlogstats.bugreport`.
- **No test seam**: requests build `OAuth2Swift` / `URLSession.shared` directly and
  need a `UIViewController`. Nothing in this module is unit tested.
- **Per-device state**: with Core Data not synced, a second device re-uploads
  everything and relies on 409 / "duplicate" to come back `already`.
