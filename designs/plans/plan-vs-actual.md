# Plan: position relative to the plan

> Status: **proposal** (2026-09-27). Nothing built in Swift; the reference model
> is `python/flightreconcile` (see `../flightreconcile.md`). Parent roadmap:
> `modernisation.md` (phase 5, **secondary**: not one of the app's core jobs).
> The route engine (`RouteTracker`, rejoin rule, route entry) is built first by
> `../future/frequency-bingo.md` plan and live modes; this plan reuses it.

## Intent

Show where the aircraft was (or is) **relative to the planned route**: on or off
track, ahead or behind, fuel against plan, which fixes were flown or skipped.
Today the app draws the flown track alone (`../ui-map-graphs.md`).

The central idea: **one position engine, three position sources.**

```
 PositionSource ── LogReplay (samples of a parsed log)   post-flight + replay
                ── LiveGPS   (CLLocationManager)          in flight
                          │
                          v
 RouteTracker(plan)  projection → along-track, cross-track, next fix,
                     rejoin index (monotonic), ETA/fuel deltas if planned
                          │
     ┌────────────────────┼──────────────────────┐
  map (cursor)       charts (cursor)       live/replay card, freq ladder
```

Because replay drives exactly the same `RouteTracker` as GPS, **live mode is
tested with real logs** before it is ever used in the air. That is the main
reason to build post-flight first.

## Decisions

| Area | Choice | Why |
|---|---|---|
| Where geometry lives | **RZFlight** (`Route.projectPoint`, `RouteProjection` exist). Add signed cross-track, monotonic progress and the ±50° rejoin rule there | flyfun-weather's `FlightTrackingService` has its own `ProjectedPosition`; one library serves both apps ("enhance the library") |
| Where reconciliation lives | `FlightLogKit` (the extracted package, `modernisation.md` phase 1) | Needs `FlightData`; not aviation-generic |
| Plan storage | `FlightPlanRecord` in the **synced UserState** store, keyed by `log_file_name`, holding FlightExchange JSON + source + optional per-waypoint planned numbers | User input, must sync; see `upload-and-import.md` |
| Plan format | **RZFlight `FlightExchange`** (thin envelope around `Route`) | Already the cross-app format; flyfun-weather emits it |
| Matching | **Monotonic along the track** (segment index never decreases, with hysteresis) | Python's abeam is a global argmin and mis-matches out-and-back routes |
| Exposure | New calculated fields `PlanXTK`, `PlanATD`, `PlanETADelta`, `PlanFuelDelta` | Existing graph, legs and table machinery then works unchanged |
| UI tech | SwiftUI in a `UIHostingController`; `MKMapView` via representable; Swift Charts | First strangler screen; same map choice as flyfun-weather (`ios-app-architecture.md`) |

## Plan sources, in build order

| # | Source | Gives | Cost |
|---|---|---|---|
| 1 | **The log's own FMS sequence** (`AtvWpt` legs, resolved through `RoutePointResolver` over nav.db) | route geometry, zero input | free; misses fixes skipped by a direct-to |
| 2 | **FlightExchange** from flyfun-weather (share sheet / file import, later API) | filed route, times, cruise altitude | small; format exists in RZFlight |
| 3 | **Route string / ICAO FPL** pasted | route | small: `ICAOFlightPlanParser` + `RoutePointResolver` |
| 4 | **ForeFlight navlog HTML** *(deferred)* | per-waypoint planned ETA, fuel, GS, wind, altitude | port `navlog_html_parser.py` into RZFlight next to `ForeFlightParser`, with parity test. Kept in the background as a potential source; the Python reconcile stays the tool for it meanwhile |

Auto-attach: a plan with a date and origin/destination is matched to the log
whose first/last fix is near them (port of `logfinder.py`).

## Model

- `RouteTracker(plan: Route)`: `update(sample) -> TrackState` with
  `alongTrackNm`, `crossTrackNm` (signed, left negative), `segmentIndex`,
  `nextFixIndex`, `rejoinIndex`, `distanceToGoNm`, and when planned numbers exist
  `etaDelta`, `fuelDelta`. State carried between samples: highest index reached
  (the same `fromIndex` floor as Frequency Bingo).
- `PlanReconciliation(flight:plan:)`: port of reconcile layers B and C over the
  tracker's output: per-waypoint abeam (offset, time, fuel, GS, wind, overflown
  if ≤ 5 nm), per-leg planned vs flown, totals and distance saved, off-plan
  fixes from the `AtvWpt` legs (layer A already exists in `FlightLeg`).
- Parity: export Python results for 2-3 logged flights with navlogs as a fixture,
  assert in tests. Fix the Python true-wind / magnetic-course mix first.

## UI: the Route tab

New tab in `LogTabBarController` (later it can absorb the Graphs tab).

- **Map**: plan as dashed `MKPolyline`; fix annotations (overflown, skipped,
  off-plan flown); flown track as `MKGradientPolylineRenderer` coloured by
  |cross-track| (switchable to altitude), simplified for display. This replaces
  the custom `FlightDataMapOverlayView`. Position marker at the cursor.
- **Charts**: cross-track vs along-track distance; altitude vs planned altitude
  profile; ETA delta when a navlog exists. `chartXSelection` sets the cursor.
- **One cursor** (`cursorTime`) shared by map, charts and table: tap the map →
  nearest sample; drag a chart → marker moves. Requires the frame alignment fix
  (`../known-issues.md` C3).
- **Table**: per waypoint planned vs actual (ETA, fuel, GS, wind), overflown
  flag; tap a row → cursor to abeam point.
- **Replay**: play/scrub control advancing the cursor; the live card (next fix,
  XTK, distance/ETA to go, frequency guess when Bingo exists) renders from the
  same `TrackState`.
- Empty state: "No plan attached. Using the FMS route from the log." with
  actions to attach a flyfun-weather flight, paste a route, or import a navlog.

## Live mode (after Frequency Bingo phase 2)

`LiveGPS` source, `NSLocationWhenInUseUsageDescription` (the app has no location
permission today), plan chosen from attached or pasted routes. The card is the
replay card. Nothing new in the engine.

## Open questions

- **Is live mode worth it here?** In flight the iPad is usually running
  ForeFlight, and flyfun-weather already shows a live position on its route map.
  The unique value in this app is the log corpus (Frequency Bingo). Recommend
  building live mode only as the Bingo live card, not as a general moving map.
- Should flyfun-weather flights be fetched by API (needs FlyFunCommon sign-in)
  or only shared as files? Files first; the API adds an account dependency.
- Without the navlog, **planned numbers per waypoint** (ETA, fuel) are missing:
  FlightExchange carries departure/arrival time and cruise altitude, so only a
  destination ETA delta is available. Option worth weighing: flyfun-weather's
  headwind advisory already computes the cruise headwind at every route point
  and a cruise TAS (`analysis/advisories/headwind.py`), so a per-waypoint ETA is
  a small derivation there. Carried as an optional field in FlightExchange, it
  would give planned times from the tool actually used, without porting the
  navlog parser.

Decided 2026-09-27: the ForeFlight navlog is **deferred** (source 4), kept as a
potential plan source.

## Phasing

1. RZFlight: signed XTK, monotonic tracker, rejoin; tests. FlightLogKit:
   `RouteTracker` over log samples, the `Plan*` fields, FMS-derived plan.
2. Route tab, post-flight, FMS plan + FlightExchange + route string.
3. Replay control and card.
4. Live source, shared with Frequency Bingo phase 3.
5. Deferred: planned numbers per waypoint (navlog import, or per-waypoint ETA in
   FlightExchange), per-waypoint table, parity fixture against the Python
   reconcile.
