# Remote upload (FlySto)

> As-built (reviewed 2026-09-27, synced 2026-09-29). Per-log upload of the raw CSV
> to FlySto (OAuth2, zipped POST), status tracked per log in Core Data.
> Modernisation: `plans/upload-and-import.md`.
> **Savvy Aviation was removed** 2026-09-29 (`00c0366`): code, settings rows,
> `FlightSavvyRecord` (Core Data model version 2) and the stored token.

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

**Savvy** (removed). `Settings.removeObsoleteKeys()` deletes `savvy.token` and
`savvy.enabled` from UserDefaults at every launch.

## Status model

`RemoteServiceRecord.Status`: `ready`, `pending`, `uploaded`, `failed`.
`flystoStatus` is computed over the one-to-one `FlightFlyStoRecord`, created
lazily by `ensureFlyStoStatus`. Mapping: success/already → uploaded;
error/tokenExpired/denied → failed. `pending` is documented as "uploaded in
background" but nothing sets it; the getter defaults to `ready`.

## Queue

`RequestQueue.shared` wraps an `OperationQueue`. `Item: Operation` holds the
record and a `UIViewController` (for auth UI), checks
`RZSystemInfo.networkAvailable()`, then runs FlySto if enabled and not uploaded
(or forced). Completions hop to `AppDelegate.worker`, set status, report the
item's `pct` progress state, post `.flightLogViewModelUploadFinished`, save.

## Key exports

| Symbol | Role |
|---|---|
| `RequestQueue`, `RequestQueue.Item` | upload queue |
| `RemoteServiceRequest`, `AsyncOperation` | base class; `AsyncOperation` is unused |
| `FlyStoRequest`, `FlyStoUploadRequest`, `FlyStoLogFilesRequest` | FlySto |
| `FlightFlyStoRecord`, `RemoteServiceRecord.Status` | per-log status |
| `Settings.removeObsoleteKeys` | clears the removed Savvy settings |
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
- **Secrets in UserDefaults**, not the Keychain, and the bug report uploads 24 h
  of logs.
- **Zip litter**: `<log>.csv.zip` files accumulate in `Documents/` (and are
  therefore candidates for iCloud sync).
- **`secrets.sample.json`** has every key the code reads; `flightlogstats.bugreport`
  is empty, so the bug report has no endpoint in a contributor build.
- **No test seam**: requests build `OAuth2Swift` / `URLSession.shared` directly and
  need a `UIViewController`. Nothing in this module is unit tested.
- **Per-device state**: with Core Data not synced, a second device re-uploads
  everything and relies on 409 to come back `already`.
