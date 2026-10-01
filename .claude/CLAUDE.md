## Always start here

Design docs give you architecture, key types and non-obvious decisions faster
than grepping. For any task that touches code, BEFORE reading or grepping:

1. Read `designs/INDEX.md`.
2. If a relevant module appears, read `designs/<module>.md`.
3. Check `designs/known-issues.md` for the area: the bug may already be known.
4. Only then explore with Grep/Read.

After changing a module that has a doc, sync that doc in the same change
(`sync-designs` skill). For a bulk pass, `/sync-all-designs`.

## Read the design doc before you write

- **Touching import, iCloud or Core Data** → `designs/log-import-sync.md` and
  `designs/plans/upload-and-import.md` (which fields are derived vs user state).
- **Touching FlySto / Savvy** → `designs/remote-upload.md`.
- **Adding a field or calculation** → `designs/log-parsing.md`.
- **Porting anything from `python/flightreconcile`** → `designs/flightreconcile.md`:
  Python is the reference; port with a parity fixture, change constants in
  Python first.

## Code design principles

- When adding logic around a library call (RZFlight, RZUtils/RZData), first
  consider enhancing the library instead of wrapping it here. Route geometry
  belongs in RZFlight, shared with flyfun-weather.
- Search for existing logic before duplicating. `Source/DataFrame.swift`,
  `GroupBy.swift`, `ValueStats.swift`, `CategoricalStats.swift` are NOT compiled;
  the real types come from RZData.
- Core Data: never touch `viewContext` off the main thread in new code; use a
  background context.
- New screens: SwiftUI in a `UIHostingController`, `@Observable` view model.

## Setup

- `git lfs pull` is required: `python/nav.db` and `flightlogstatsTests/TestAssets/log_*.csv`
  are LFS objects and are 130-byte pointers without it.
- `flightlogstats/secrets.json` is gitignored; a build phase copies
  `secrets.sample.json` if missing.
- nav.db is rebuilt with `python/make_nav_db.py` from the flyfun-apps nav.db.
- Unit tests are hosted in the app (need a simulator). Run them before pushing a
  change to parsing or analysis.

## Manual test hooks (keep them working)

- DEBUG "Forget last" drops the newest log so the next import brings it back,
  to re-test import/upload without a new flight. Never make it delete for good.
- Launch args (`Source/MainSplitViewController.swift`): `-FLSImportFolder <path>`
  opens the import sheet on a folder; `-FLSShowUploads YES` opens Uploads.
- CloudKit is off when the app hosts unit tests, and with `-FLSNoCloudKit YES`
  (`LibraryStore.cloudKitEnabled`): unsigned builds (CI) trap in CloudKit otherwise.
- Landing a PR written without Xcode: `/land-pr <N>`.
