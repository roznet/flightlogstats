# Plan: modernisation roadmap

> Status: **proposal** (2026-09-27), from a full code review. Sub-plans:
> `upload-and-import.md`, `plan-vs-actual.md`, and the existing
> `../future/frequency-bingo.md`. Bug inventory: `../known-issues.md`.
> Reprioritised 2026-09-27 around the author's core jobs (below).
> Updated 2026-09-28: build unblocked, CI runs the unit tests, Frequency Bingo
> (#9) step 1 merged and pulled ahead of phases 1-2 (see §Order); step 0, the
> per-flight frequency timeline, in PR #11, so plan mode (step 2) is next.

## The jobs the app is for

In order of use, as stated by the author (2026-09-27):

1. **After the flight: `+` import from the SD card**, which saves the logs to
   iCloud Drive (synced to the Mac) and **uploads them to FlySto**.
2. **Fuel**: the refill calculation, and checking fuel after the flight.
3. **Frequencies after the flight**, being extended by Frequency Bingo.

Everything else (trips, stats, graphs by phase or autopilot, plan vs actual) is
secondary. The roadmap spends effort in that order and keeps the rest working
without investing in it.

### What that means for the design

- **Import and upload are one flow, not two features.** `+` → progress → logs in
  iCloud → FlySto upload queued → land on the newest flight. Today upload is a
  separate action, or happens only when a log is displayed.
- **The newest flight is the home screen after an import.** Summary with FlySto
  status, the fuel check, and the frequencies flown, without hunting in the list.
- **Frequency review of one flight comes before prediction.** Bingo's index
  (debounced COM1 segments with the nearest fix and altitude band) is also the
  best per-flight frequency timeline, better than today's raw `[.COM1, .COM2]`
  legs. Build the index first, show it per flight, then add the prediction.

## Where the app stands

A 2022-2023 UIKit app that works for its author but has quietly stopped being
maintainable:

- **It did not build as checked in** (rzflight pin predated the types the
  nav.db commit needs; rzutils-touch's `Package.swift` was rejected by current
  Xcode), and CI built on a simulator name that no longer existed and ran no
  tests. Both fixed 2026-09-28 (`8cdd2e5`, `ios.yml`).
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

| # | Phase | Job | Size | Outcome |
|---|---|---|---|---|
| 0 | Build, CI, hygiene, Savvy removal, fuel bugs | all | S | green build, tests in CI, core-job bugs fixed. **Build + CI done**; hygiene, Savvy, bugs open |
| 1 | Post-flight import + FlySto upload | 1 | M | one `+` flow: off-main import, one iCloud location, tombstones, real FlySto queue, Keychain, synced user state, land on newest flight |
| 2 | `FlightLogKit` package | 2, 3 | M | parsing, fuel and legs testable with `swift test`; home for the frequency index |
| 3 | Frequency review + Bingo (#9) | 3 | M | per-flight frequency timeline from the index, then Bingo plan mode, then live. **Index + model merged** (PR #10); **timeline** in PR #11; plan mode next |
| 4 | Post-flight fuel check | 2 | S | fuel card on the newest flight: used by totaliser vs tanks, landing fuel, refill to target |
| 5 | Plan vs actual | secondary | M | Route tab reusing Bingo's route engine; post-flight only |
| 6 | UI migration | ongoing | ongoing | Swift Charts replaces `GCSimpleGraph`, rzutils-touch dropped, SwiftUI screens as they are touched |

### Order

Phase 1 before `FlightLogKit` because it touches the library, network and Core
Data, not the parser; its test seams (`LogLibrary`, `HTTPClient`) do not need
the package. Phase 4 is small and can slot in anywhere after phase 2.

**Phase 3 does not wait for phases 1-2** (decided 2026-09-28). The index and
model were built in the app target (`FrequencyModel.swift`,
`FrequencyIndexOrganizer.swift`, PR #10) and pinned by the Python parity test.
`FrequencyModel` imports only Foundation and CoreLocation, so it moves into
`FlightLogKit` as a file move when phase 2 happens; waiting for the package
would buy nothing. Bingo's UI touches neither import, upload nor Core Data
sync, so it runs alongside phase 1. Two phase 0 items gate it: CI running the
unit tests (done, so the parity fixture is enforced) and C3 before any Bingo
map that overlays `FlightData`'s track. The timeline map draws from the index
only (which reads the aligned double frame), so it did not wait for C3.

### Phase 0: build, CI, hygiene

- ~~Re-resolve packages: rzflight to a release containing `KnownWaypoints`,
  `RoutePointResolver` and the `Airport(db:ident:)` schema fix~~ (rzflight 1.3.0,
  `8cdd2e5`). Still open: drop the stale pins (BrightFutures, Erik, FileKit,
  Kanna, Swifter) and check `RZData` is a declared product (B3, B4).
- ~~rzutils-touch: bump its `swift-tools-version` to 5.7 and tag~~ (1.0.8,
  `8cdd2e5`). Dropping it waits for Swift Charts in phase 6.
- Delete the four orphan sources (`DataFrame.swift`, `GroupBy.swift`,
  `ValueStats.swift`, `CategoricalStats.swift`) and `airports.py`; fix README.
- ~~Align deployment targets on one value~~ (all 18.6, 2026-09-28).
- ~~CI modelled on flyfun-weather's `ios.yml`~~ (done 2026-09-28:
  `.github/workflows/ios.yml`, `macos-26`, Xcode 26.6 pinned because the image
  has no 27 yet, LFS checkout, unit target only, vacuous-pass guard). Still
  open: rzflight's `claude-code-review.yml` and the `code-review` command.
- Fix with a test each, core jobs first:
  - fuel: C11 (`FuelTanks ==` compares totals only, so an edit that moves fuel
    between tanks does not mark the view model dirty and the fuel table is not
    rebuilt), C7 (quick-parse totaliser), C8 (fuel unit
    assumed gallons), C1 (latent, no live caller);
  - import: I5 (folder pick with `.selectedFile` imports nothing, the Mac default);
  - C3 frame alignment (prerequisite for any map/time work on `FlightData`'s
    coordinates; the double/categorical half is fixed in `aef4e43`, the
    coordinate frame is left; Bingo maps avoid it by drawing from the index),
    C4 quoted spaces,
    C5 POSIX locale; C2 and X2 only because they are one-liners.
- **Remove Savvy** (decided 2026-09-27): `SavvyRequest.swift`,
  `SavvyAuthenticateViewController`, `FlightSavvyRecord` + the `savvy_record`
  relationship (a lightweight migration: entity removal), the Savvy settings and
  token (clear the stored token on upgrade), the `WebKit` import, Savvy branches
  in `RequestQueue` / `UploadSettingsViewController` / list and summary views.
  Resolves U5 and half of U4 before the upload rewrite starts.
- Complete `secrets.sample.json`.

### Phase 1: post-flight import + FlySto upload

See `upload-and-import.md` (its phases 1-4). The user-visible result is the
`+` flow above. Stays UIKit apart from the progress/uploads sheet, which can be
the first SwiftUI screen.

### Phase 2: `FlightLogKit`

Local SPM package in the repo (`Packages/FlightLogKit`), moved in this order:

1. `BufferedStreamReader`, `CsvParser`, `FlightLogFile.Field` (+ JSON via
   `Bundle.module`), `FieldCalculations`, `FlightData`.
2. `FlightSummary` with an injected `AirportLookup` protocol and explicit fuel
   unit (removes the `AppDelegate` / `Settings` reads), `FlightLeg`, `TimeRange`.
3. `FuelTanks`, `FuelAnalysis`, `AircraftPerformance`, `AvionicsSystem`,
   `Trip` / `Trips` / `Visit` over a plain value (not the managed object).
4. `FrequencyModel` (already pure) and the segment building of
   `FrequencyIndexOrganizer`; the FMDB storage stays in the app.

Swift Testing with parameterised cases per fixture log; Swift 6 language mode in
the package from day one (value types, `Sendable`, `let` statics). The app
target stays Swift 5 mode until phase 1 has removed the shared mutable state.
Target macOS for `swift test`; **Linux is not a goal** (RZData is ObjC-backed and
CoreLocation types are used throughout, and nothing needs it).

Do not swap the home-grown parser for TabularData without a benchmark: the
byte-level parser and date shortcut are deliberate performance choices. Storing
columns directly while parsing (no row-major copy) is the cheaper win.

### Phase 3: frequency review, then Bingo

`../future/frequency-bingo.md` phases (issue #9), with one step added in front.
Step 1 shipped first (PR #10), then step 0 on top of its index; plan mode is
next.

0. ~~**Per-flight frequency timeline**~~ (PR #11): a Frequencies tab in
   `LogTabBarController` (SwiftUI in a `UIHostingController`) listing the
   selected flight's debounced COM1 segments from the index, each with its fix,
   altitude band, duration and track miles, and a map with each segment in its
   own colour and numbered handoff markers matching the list. See
   `../ui-map-graphs.md` §Frequencies tab. Meant to replace the Comms grouping
   of the Graphs tab as the way to look at frequencies after a flight; that
   grouping stays until the owner has used the timeline and decides.
1. ~~Index + model with the Python parity fixture~~ (PR #10, `a8149e9`;
   parity realigned in `aef4e43`).
2. Plan mode (**next**). Its route entry and route engine (`RouteTracker` with
   the rejoin rule, in RZFlight) are what plan-vs-actual later reuses.
3. Live mode.
4. Confirmation taps, and predicted vs actual for a flown flight: the
   natural follow-up of step 0.

### Phase 4: post-flight fuel check

Small, on top of the existing `FuelAnalysis`, shown on the newest flight:

- fuel used by **totaliser vs tank quantity**, and the discrepancy;
- landing fuel and endurance at the aircraft's gph;
- refill to target per tank (the existing calculator, pre-filled);
- optional: the totaliser-vs-tank discrepancy across the aircraft's recent
  flights, which shows a drifting fuel-flow calibration or a gauge problem.
  Worth doing only if it would change what you do; ask before building.

### Phase 5: plan vs actual

See `plan-vs-actual.md`. Post-flight only; builds on the phase 3 route engine
rather than creating it.

### Phase 6: UI migration

- Pattern: `@Observable` view model per screen, SwiftUI view in a
  `UIHostingController` inside the existing tab/split structure. Keep
  `UISplitViewController` until the list itself moves.
- **Swift Charts** replaces `GCSimpleGraphView` screen by screen; when the last
  one goes, drop rzutils-touch (and its broken manifest) entirely.
- Map: `MKPolyline` / `MKGradientPolylineRenderer` replace the custom renderer.
- Order follows the core jobs: import/uploads sheet (phase 1) → frequency
  timeline (phase 3, done first: PR #11, the first SwiftUI screen) → fuel
  card (phase 4) → Settings → list last. Stats and
  trips move only if they break.
- **Tables: keep the UIKit table engine** (`TableCollectionViewLayout` +
  `TableDataSource` + `RZNumberWithUnitGeometry`), decided 2026-09-27. SwiftUI
  has nothing equivalent to its combination of scrolling both ways with frozen
  header rows and columns, column widths measured from content, and numbers
  aligned on decimal point and unit:
  - `Table` pins the header row but has no frozen columns, and on iPhone
    (compact width) shows only the first column;
  - `Grid` sizes columns from content and can align decimals with a custom
    alignment guide, but is not lazy and has no frozen rows or columns;
  - frozen column + two-way scroll means two synchronised scroll views
    (`onScrollGeometryChange`, iOS 18): possible, fiddly, and rebuilding what
    already works.

  So: **wide tables** (legs × fields, stats flight list) stay on the engine,
  embedded in SwiftUI screens through a `UIViewRepresentable` wrapper. **Small
  key/value tables** (summary time, fuel, aircraft; 2-6 columns) move to SwiftUI
  `Grid` when their screen moves, with the decimal alignment reproduced by an
  alignment guide. Give the engine the two things it lacks rather than replacing
  it: an `accessibilityLabel` per cell from its `CellHolder` (cells draw text in
  `draw(_:)`, invisible to VoiceOver), and fonts through `UIFontMetrics` with a
  geometry recompute on content-size change (Dynamic Type).
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
  carefully, in phase 1 (where synced user state ships).
- **Record re-derive cost**: every `FlightLogFileRecord.currentVersion` bump
  re-parses the library. Fine at 459 logs; keep full parses off the main thread.
- **Two parsers** (Swift and pandas) will drift; parity fixtures are the only
  guard.
- **Scope** (rough guess): several months of part-time work. Phase 0 alone makes the app
  maintainable again; stop there if priorities change.
