# UI: screens, map and graphs

> As-built (reviewed 2026-09-27, Frequencies tab 2026-09-28, Frequency Bingo
> 2026-09-29, import sheet and Uploads screen 2026-09-30). UIKit, one storyboard, split view, plus one SwiftUI tab and one
> SwiftUI modal (Frequency Bingo). The Graphs map shows the flown
> track only; there is no plan overlay, no annotations, no time cursor. Plan for
> the next version: `plans/plan-vs-actual.md`.

## Screen map

```
MainSplitViewController (Main.storyboard initial, classic master/detail)
├─ primary: UINavigationController
│    └─ LogListTableViewController   "Display Statistics" row, flights / aircraft,
│                                    search, "More" UIMenu (import, upload batch,
│                                    rebuild, settings, bug report)
└─ secondary, one of:
     LogTabBarController ─ Summary  LogSummaryViewController (4 tables, upload)
                         ─ Fuel     LogFuelAnalysisViewController
                         ─ Graphs   LogMapGraphsViewController
                         ─ Frequencies FrequencyTimelineViewController (SwiftUI,
                                    appended in code in viewDidLoad)
     StatsTabBarController (built in code) ─ Flights StatsTripsViewController
                                            ─ Details StatsDetailledViewController (stub)
Modals (code): settings, bug report, UploadSettingsViewController popover,
UIDocumentPicker → PostFlightImportViewController (SwiftUI sheet),
UploadsViewController (SwiftUI, More › Uploads), progress overlay,
FrequencyBingoViewController (SwiftUI,
"Frequency Bingo" in the More menu, or "Bingo this route" on the Frequencies
tab; full screen, page sheet in compact width)
```

Selection: list → `LogSelectionDelegate.selectlogInfo` → `LogTabBarController`
builds a new `FlightLogViewModel`, pushes it to every child conforming to
`ViewModelDelegate`, then `build()` on `AppDelegate.worker`.

Mac Catalyst: same UI, no menu bar or toolbar work, multiple scenes disabled.
iPhone: default collapse; the graph/map stack goes vertical in compact width.

## Map and graphs (`LogMapGraphsViewController`)

Layout: `GCSimpleGraphView` and `MKMapView` in an equal stack, two segmented
controls (leg grouping: Waypoints / Phase / Comms / Autopilot; graph style:
Single / Two / Scatter), then the legs table.

- **Track**: custom `FlightDataMapOverlay: MKOverlay` over the coordinate column,
  drawn by `FlightDataMapOverlayView: MKOverlayRenderer`. Two colours only
  (`ViewConfig.graphPathColor` blue, highlighted leg yellow). The renderer draws
  every point on every tile, ignoring the `mapRect`.
- **No** `MKPolyline`, annotations, map type control, start/end pins, route,
  airspace or replay.
- **Graphs**: `GCSimpleGraphView` (ObjC, rzutils-touch) fed by
  `GCSimpleGraphCachedDataSource` from `FlightLogViewModel.graphDataSource` /
  `scatterDataSource`. X is elapsed time since hobbs start, max two series on
  separate y axes, selected leg as a gradient fill. Default `[.IAS, .AltInd]`.
- **Choosing a field**: only by tapping a legs-table cell, which appends that
  column's field to `graphFields`.
- **Linking is one way**: tapping a leg highlights graph and map and zooms the
  map. No scrubbing, no graph cursor, no tap-on-map to pick a time.
- `mapOverlayView` allocates a new overlay per call and `updateUI` resets the
  visible rect, so any record update resets the user's zoom.

## Frequencies tab (`FrequencyTimelineView.swift`)

The first SwiftUI screen (modernisation §Phase 6 pattern): a
`UIHostingController` subclass that conforms to `ViewModelDelegate`, so the tab
bar's existing selection fan-out reaches it, over an `@Observable`
`FrequencyTimelineViewModel` (`FrequencyTimeline.swift`, pure: no `AppDelegate`
or `Settings`).

- **Data**: the selected log's debounced COM1 segments and 15 s points from
  `FrequencyIndexOrganizer.logIndex(logFileName:)`; a log not indexed yet is
  indexed on the spot through `logIndex(flightLog:)` (the same
  `insertOrReplace(flightLog:)` as the import hook). Loaded on `worker`, which is
  serial and already has the selection's `FlightLogViewModel.build()` queued, so
  the log is parsed first. A late load for a previous selection is dropped.
- **List**: SwiftUI `List`, one row per segment: number, frequency, fix
  (`waypointIn`), start time, duration, altitude in-out band (the `freq_cli list`
  format, from this segment's entry and exit), nm. Rows are the index as
  recorded: no smoothing beyond the scan's debounce.
- **Map**: SwiftUI `Map`, one `MapPolyline` per segment (entry, points, exit),
  colours cycling so neighbours contrast, and a numbered `Annotation` at each
  handoff matching the row number (labels on the line collide). Tapping a row or
  a marker highlights that segment, dims the rest and zooms to it.
- **Draws only from the index**, never from `FlightData`'s coordinate frame
  (C3 was open there when it was built; fixed since, `ecbd8ee`), so markers sit
  on the drawn line.
- Points carry no segment number in the index; `FrequencyTimeline.pointsBySegment`
  recovers it from `freq`, `nextFreq` and non-increasing `nmToNext` (exact on
  every TestAssets log, `TestFrequencyTimeline`).
- **Locate** (top-right of the map): toggles the live position, an aircraft icon
  along the GPS track plus a line to where it will be in one minute at the current
  ground speed (no line under ~2 kt or without a track). The camera moves to the
  first fix after the toggle, then is left alone. See *Live position* below.
- **Bingo this route** (list header): opens Frequency Bingo through
  `FrequencyBingoViewController.present(launch:from:)` on this flight's route
  and cruise altitude (`FrequencyBingo.launch(logFileName:...)`).
- The Graphs tab's Comms grouping is still there; whether the timeline replaces
  it is the owner's call once it has been used.

## Post-flight import sheet (`PostFlightImport.swift`)

The `+` flow in one sheet (`plans/upload-and-import.md` §The post-flight flow),
presented by the split view after the document picker. `@MainActor @Observable`
`PostFlightImportModel` drives `FlightLogOrganizer.importLogs` and follows
`UploadActivity`:

- **SD card**: looking for new logs → (above 150 files) "Import all / Cancel" in
  the sheet → copying n of N → "k new logs", or "No new logs on this card".
- **Library**: "Saved to iCloud Drive" (or "on this device"), number of flights,
  files that failed to copy.
- **FlySto** (only when the import has flights): off, manual mode hint, Sign in
  button when the queue paused, uploading n of N, then uploaded / failed with the
  reason.
- **Open latest flight** (bottom): selects the newest new flight in the detail
  screen (`LogListTableViewController.openLog(name:)`) and closes the sheet.
- Closing the sheet cancels nothing; closing it while it asks for a large import
  answers Cancel. Progress steps arrive in their own tasks; one arriving after the
  end is dropped.

## Uploads screen (`UploadsView.swift`)

More › Uploads. `UploadsModel` reloads `RecordUploadStore.overview()` on every
`.newFileUploaded`. Sections: FlySto status (off, Sign in, uploading n of N,
all uploaded), Waiting, Failed (reason, next retry). Actions menu: Retry all
failed, Upload next N flights.

The log list shows each log's FlySto status as the cell's accessory
(`LogListTableViewCell.updateUploadStatus`): queued, uploaded, failed, nothing
when never queued or FlySto is off; with an accessibility label.

DEBUG: `-FLSImportFolder <path>` and `-FLSShowUploads YES` open the two screens
at launch (`MainSplitViewController.viewDidAppear`), for the simulator.

## Frequency Bingo (`FrequencyBingo.swift`, `FrequencyBingoView.swift`)

Plan and live modes of the Bingo tool, as specified in `future/frequency-bingo.md`
§The page (that doc is the reference for behaviour). Same pattern as the
Frequencies tab: a pure `@Observable` `FrequencyBingoViewModel` (no
`AppDelegate`; the resolver and the store are injected) under a SwiftUI view in
a `UIHostingController`, opened only through `FrequencyBingoViewController(launch:)`.
Regular width: route, radio and ladder table on the left, map on the right;
compact: route, radio, map, table stacked. The map carries the live position
(`OwnshipMapContent`, `.ownshipLocate`); a fix switches the screen to live mode
(ladder from the position, handoff distance/ETA in the next box), see
`future/frequency-bingo.md` §Implementing live mode.

## Live position (`Ownship.swift`, `OwnshipMap.swift`)

Built for reuse by every live SwiftUI map (Frequencies tab now, Bingo live mode
and plan-vs-actual live next). A host adds `OwnshipMapContent` inside its
`Map { }`, tracks the camera heading with `onMapCameraChange` (so the icon points
along the track on a rotated map) and applies `.ownshipLocate(live, position:)`.

- `OwnshipVector` (pure, `TestOwnship`): position, track, ground speed, and the
  `lead` point after 60 s by great circle, from RZFlight's
  `CLLocationCoordinate2D.pointFromBearingDistance` (longitude normalised to
  ±180 here: RZFlight does not).
- `LiveLocation.shared` (`@Observable`, main actor): `CLLocationUpdate.liveUpdates(.airborne)`
  with a `CLServiceSession` for when-in-use authorisation. One instance, so the
  toggle is the same on every screen. GPS runs only while the toggle is on **and**
  a map using `.ownshipLocate` is on screen (appear/disappear count).
- Permission: `NSLocationWhenInUseUsageDescription` in `Info.plist`, and
  `com.apple.security.personal-information.location` for the Mac Catalyst sandbox.

## Presentation pattern

| Type | Role |
|---|---|
| `FlightLogViewModel` | per-log inputs (display context, fuel inputs, `legsByFields`), `build()` creates all data sources; dirty via write/build counters; also triggers uploads |
| `TableDataSource` + `TableCollectionViewLayout` + `CellHolder` | generic "spreadsheet" on `UICollectionView` with frozen rows/columns; subclasses `FlightLegsDataSource`, `FlightSummaryTimeDataSource`, `FlightSummaryFuelDataSource`, `FuelAnalysisDataSource`, `AircraftSummaryDataSource`, `FlightListDataSource`. Reuse for any per-waypoint table |
| `DisplayContext` | date style, airport style, per-field stat metric and display unit (hard-coded; only fuel units are user settings) |
| `ViewConfig` | fonts/colours singleton, Avenir Next fixed sizes, `dynamicFont = false` |

`ViewModelDelegate.viewModelDidFinishBuilding` is never called and
`.flightLogViewModelChanged` has no observer; views refresh through racing
`updateUI()` calls and `.logFileRecordUpdated`.

## Key exports

`MainSplitViewController`, `LogListTableViewController`, `LogListTableViewCell`,
`LogTabBarController`, `LogSummaryViewController`, `LogFuelAnalysisViewController`,
`LogMapGraphsViewController`, `FrequencyTimelineViewController`,
`FrequencyTimelineView`, `FrequencyTimelineViewModel`, `FrequencyTimeline`,
`LiveLocation`, `OwnshipVector`, `OwnshipMapContent`, `ownshipLocate(_:position:)`,
`FrequencyBingoViewController`, `FrequencyBingoView`, `FrequencyBingoViewModel`,
`PostFlightImportViewController`, `PostFlightImportModel`, `UploadsViewController`, `UploadsModel`, `WindowReader`,
`BingoLaunch`, `BingoRadio`, `BingoStore`,
`StatsTabBarController`, `StatsTripsViewController`,
`FlightLogViewModel`, `DisplayContext`, `ViewConfig`, `TableDataSource`,
`TableCollectionViewLayout`, `FlightLegsDataSource`, `FlightDataMapOverlay`,
`FlightDataMapOverlayView`, `MeasurementView`, `RZNumberWithUnitView`.

## Gotchas

- **Block observers leak.** Added in `viewWillAppear` / `willDisplay cell` with the
  block API, "removed" with `removeObserver(self)`, which cannot remove them.
  They accumulate on every appearance (`LogMapGraphsViewController`,
  `LogSummaryViewController`, `LogTabBarController`, `LogListTableViewController`).
- **Stats tab default**: the Flights tab opens on `.trips`. A cast that meant to
  set `.months` targeted the Details index and never applied; removed (X2).
- **Accessibility**: none. Table cells draw text in `draw(_:)`, invisible to
  VoiceOver; no Dynamic Type.
- **`FlightLogViewModel.build()` runs on `worker`** while main reads the same
  properties.
- **Two `Waypoint` types**: the app's name-only struct shadows `RZFlight.Waypoint`.
- **`AppDelegate.knownWaypoints` is loaded and unused** (it is there for route
  entry: Frequency Bingo and plan-vs-actual).
- Storyboard is 2,044 lines with the same prototype cells pasted into 6 scenes;
  navigation is by string identifiers and `fatalError()` on mismatch.
