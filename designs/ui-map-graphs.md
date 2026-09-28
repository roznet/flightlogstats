# UI: screens, map and graphs

> As-built (reviewed 2026-09-27, Frequencies tab 2026-09-28). UIKit, one
> storyboard, split view, plus one SwiftUI tab. The Graphs map shows the flown
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
SavvyAuthenticateViewController, UIDocumentPicker, progress overlay
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
  (C3 is open there), so markers sit on the drawn line.
- Points carry no segment number in the index; `FrequencyTimeline.pointsBySegment`
  recovers it from `freq`, `nextFreq` and non-increasing `nmToNext` (exact on
  every TestAssets log, `TestFrequencyTimeline`).
- The Graphs tab's Comms grouping is still there; whether the timeline replaces
  it is the owner's call once it has been used.

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
`StatsTabBarController`, `StatsTripsViewController`,
`FlightLogViewModel`, `DisplayContext`, `ViewConfig`, `TableDataSource`,
`TableCollectionViewLayout`, `FlightLegsDataSource`, `FlightDataMapOverlay`,
`FlightDataMapOverlayView`, `MeasurementView`, `RZNumberWithUnitView`.

## Gotchas

- **Block observers leak.** Added in `viewWillAppear` / `willDisplay cell` with the
  block API, "removed" with `removeObserver(self)`, which cannot remove them.
  They accumulate on every appearance (`LogMapGraphsViewController`,
  `LogSummaryViewController`, `LogTabBarController`, `LogListTableViewController`).
- **Stats tab wiring**: `StatsTabBarController` casts `viewControllers?[1]` to
  `StatsTripsViewController`, but index 1 is the Details stub in the storyboard.
- **Accessibility**: none. Table cells draw text in `draw(_:)`, invisible to
  VoiceOver; no Dynamic Type.
- **`FlightLogViewModel.build()` runs on `worker`** while main reads the same
  properties.
- **Two `Waypoint` types**: the app's name-only struct shadows `RZFlight.Waypoint`.
- **`AppDelegate.knownWaypoints` is loaded and unused** (it is there for route
  entry: Frequency Bingo and plan-vs-actual).
- Storyboard is 2,044 lines with the same prototype cells pasted into 6 scenes;
  navigation is by string identifiers and `fatalError()` on mismatch.
