# UI: screens, map and graphs

> As-built (reviewed 2026-09-27). UIKit, one storyboard, split view. The map
> shows the flown track only; there is no plan overlay, no annotations, no time
> cursor. Plan for the next version: `plans/plan-vs-actual.md`.

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
`LogMapGraphsViewController`, `StatsTabBarController`, `StatsTripsViewController`,
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
