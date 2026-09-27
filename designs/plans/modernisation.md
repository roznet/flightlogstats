# Plan: modernisation roadmap

> Status: **proposal** (2026-09-27), from a full code review. Sub-plans:
> `upload-and-import.md`, `plan-vs-actual.md`, and the existing
> `../future/frequency-bingo.md`. Bug inventory: `../known-issues.md`.

## Where the app stands

A 2022-2023 UIKit app that works for its author but has quietly stopped being
maintainable:

- **It does not build as checked in** (rzflight pin predates the types the
  nav.db commit needs; rzutils-touch's `Package.swift` is rejected by current
  Xcode). CI builds on a simulator name that no longer exists and runs no tests.
- **Everything is one flat target.** Parsing and analysis read
  `AppDelegate.knownAirports` and `Settings.shared`, so nothing is testable
  without launching the app in a simulator.
- **Concurrency is GCD over a main-queue Core Data context** used from four
  queues, with `NotificationCenter` block observers that leak.
- **The upload "queue" runs everything in parallel**, and user state (uploads,
  fuel inputs, registrations) does not sync between devices.
- **New analysis happens in Python** (`flightreconcile`) because that is where
  iteration is fast. That is healthy, but nothing carries results back into the
  app.

The good parts are worth keeping: files as the source of truth, the fast
byte-level parser, the generic `TableDataSource`, the legs abstraction, the
record-version re-derive mechanism, and the Python lab with its eval harnesses.

## Principles

1. **Strangle, do not rewrite.** Every phase ships an App Store build. New
   screens in SwiftUI inside the existing UIKit shell; old screens move when
   touched for another reason.
2. **Tests before moves.** Pin behaviour with fixtures, then refactor.
3. **Library first.** Aviation geometry into RZFlight (shared with
   flyfun-weather), log logic into a local `FlightLogKit` package. The app target
   shrinks to UI and wiring.
4. **Python is the lab, Swift is the product.** A model graduates with a parity
   fixture; constants change in Python first.
5. **Docs move with code.** Each PR syncs the design doc it touches
   (`.claude/skills/sync-designs`).

## Phases

| # | Phase | Size | Outcome |
|---|---|---|---|
| 0 | Build, CI, hygiene | S | green build, tests in CI, obvious bugs fixed |
| 1 | `FlightLogKit` package | M | parsing + analysis testable with `swift test`, Swift 6 mode inside |
| 2 | Library + concurrency | M | `LogLibrary` actor, background contexts, one file location, tombstones, synced user state |
| 3 | Upload engine | S-M | FlySto only: real queue, Keychain, status machine |
| 4 | Plan vs actual | M-L | Route tab: plan overlay, cursor-linked map and charts, replay |
| 5 | Frequency Bingo | M | as designed in `future/frequency-bingo.md`, on the phase 4 engine |
| 6 | UI migration | ongoing | Swift Charts replaces `GCSimpleGraph`, rzutils-touch dropped, SwiftUI settings/stats, accessibility |

Phases 2-3 and 4-5 are independent tracks after phase 1; do whichever hurts
more first. The upload work fixes things users hit; plan-vs-actual is new value.

### Phase 0: build, CI, hygiene

- Re-resolve packages: rzflight to a release containing `KnownWaypoints`,
  `RoutePointResolver` and the `Airport(db:ident:)` schema fix (tag one from
  rzflight main if needed); declare `RZData` as a product; commit a current
  `Package.resolved`.
- rzutils-touch: bump its `swift-tools-version` to 5.7 and tag (one line
  upstream). Dropping it waits for Swift Charts in phase 6.
- Delete the four orphan sources (`DataFrame.swift`, `GroupBy.swift`,
  `ValueStats.swift`, `CategoricalStats.swift`) and `airports.py`; fix README.
- Align deployment targets (app 18.6, tests 16.0, UI tests 15.4) on one value.
- CI modelled on flyfun-weather's `ios.yml`: `macos-26`, pinned Xcode,
  `actions/checkout` with `lfs: true`, `xcodebuild test` on the unit target,
  cached SPM checkouts. Add rzflight's `claude-code-review.yml` and the
  `code-review` command.
- Fix with a test each: C1 `FuelTanks.isAlmostEqual`, C2 `NmpG` units, C3 frame
  alignment, C4 quoted spaces, C5 POSIX locale, X2 stats tab index.
- **Remove Savvy** (decided 2026-09-27): `SavvyRequest.swift`,
  `SavvyAuthenticateViewController`, `FlightSavvyRecord` + the `savvy_record`
  relationship (a lightweight migration: entity removal), the Savvy settings and
  token (clear the stored token on upgrade), the `WebKit` import, Savvy branches
  in `RequestQueue` / `UploadSettingsViewController` / list and summary views.
  Resolves U5 and half of U4 before the upload rewrite starts.
- Complete `secrets.sample.json`.

### Phase 1: `FlightLogKit`

Local SPM package in the repo (`Packages/FlightLogKit`), moved in this order:

1. `BufferedStreamReader`, `CsvParser`, `FlightLogFile.Field` (+ JSON via
   `Bundle.module`), `FieldCalculations`, `FlightData`.
2. `FlightSummary` with an injected `AirportLookup` protocol and explicit fuel
   unit (removes the `AppDelegate` / `Settings` reads), `FlightLeg`, `TimeRange`.
3. `FuelTanks`, `FuelAnalysis`, `AircraftPerformance`, `AvionicsSystem`,
   `Trip` / `Trips` / `Visit` over a plain value (not the managed object).

Swift Testing with parameterised cases per fixture log; Swift 6 language mode in
the package from day one (value types, `Sendable`, `let` statics). The app
target stays Swift 5 mode until phase 2 has removed the shared mutable state.
Target macOS for `swift test`; **Linux is not a goal** (RZData is ObjC-backed and
CoreLocation types are used throughout, and nothing needs it).

Do not swap the home-grown parser for TabularData without a benchmark: the
byte-level parser and date shortcut are deliberate performance choices. Storing
columns directly while parsing (no row-major copy) is the cheaper win.

### Phase 2 and 3

See `upload-and-import.md`.

### Phase 4 and 5

See `plan-vs-actual.md` and `../future/frequency-bingo.md`. Phase 4 builds the
position engine (`RouteTracker`, `PositionSource`) that Bingo's live mode reuses,
and the first SwiftUI screen, which sets the pattern for phase 6.

### Phase 6: UI migration

- Pattern: `@Observable` view model per screen, SwiftUI view in a
  `UIHostingController` inside the existing tab/split structure. Keep
  `UISplitViewController` until the list itself moves.
- **Swift Charts** replaces `GCSimpleGraphView` screen by screen; when the last
  one goes, drop rzutils-touch (and its broken manifest) entirely.
- Map: `MKPolyline` / `MKGradientPolylineRenderer` replace the custom renderer.
- Order: Settings (a `Form`) → Stats → Summary tables → Fuel → list last.
- Accessibility and Dynamic Type come with SwiftUI; the custom `draw(_:)` cells
  go with the screens that use them.
- Mac Catalyst stays (the iCloud Drive sync hub): menu commands for import and
  upload; see `upload-and-import.md` §Mac Catalyst.

## Explicitly not doing

- **SwiftData migration**: no gain over Core Data + CloudKit here.
- **A big-bang SwiftUI rewrite**: the app would stop shipping for months.
- **Linux builds** of the package.
- **Replacing RZData / RZUtils**: they are the author's own libraries; improve
  them upstream instead of forking again (the orphan files are what a fork
  looks like after two years).

## Maintainability extras

- `.claude/CLAUDE.md` pointing at `designs/INDEX.md` first (added with this plan).
- Python: a `pyproject.toml` for `flightreconcile`, paths from env vars instead
  of `~/Developer/...`, and a `make fixtures` target that exports parity
  fixtures into `flightlogstatsTests/TestAssets/`.
- `make_nav_db.py`: same env-var treatment; document the rebuild in the
  architecture doc.
- Keep `known-issues.md` as the tracker; mark items resolved with commits.

## Risks

- **CloudKit schema is forever**: once the UserState store is deployed to
  production, fields can be added but not removed or renamed. Design it once,
  carefully, in phase 2.
- **Record re-derive cost**: every `FlightLogFileRecord.currentVersion` bump
  re-parses the library. Fine at 459 logs; keep full parses off the main thread.
- **Two parsers** (Swift and pandas) will drift; parity fixtures are the only
  guard.
- **Scope** (rough guess): several months of part-time work. Phase 0 alone makes the app
  maintainable again; stop there if priorities change.
