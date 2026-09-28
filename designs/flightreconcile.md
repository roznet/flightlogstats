# flightreconcile: the Python lab

> As-built (reviewed 2026-09-27). `python/flightreconcile/` is where new analyses
> are designed and validated against the real corpus before any Swift is written:
> plan vs actual (navlog reconcile), corridor comparison, frequency prediction.
> User docs: `python/flightreconcile/README.md`.

## Role

The Python package is the **reference implementation**, not a product. A feature
graduates to the app by porting its model to Swift with a parity fixture
(Python-computed expected outputs asserted in `flightlogstatsTests`). Any change
to a tuned constant happens in Python first, with its eval harness.

## Tools

| CLI | Question | Core |
|---|---|---|
| `cli` (reconcile) | how did this flight differ from its ForeFlight navlog? | `reconcile.py` layers A/B/C |
| `corridor_cli` | which routing between two points is objectively better? | `corridor.py` clustering + still-air time |
| `freq_cli` | which ATC frequency next, and when? | `freq.py` kNN + transition model |

## Reconcile (plan vs actual)

Inputs: ForeFlight navlog HTML (`navlog_html_parser.py`, preferred) or PDF
(`navlog_parser.py`), and a G1000 CSV (`g1000_parser.py`), auto-matched by
`logfinder.py` (filename date, then first fix ≈ origin and last fix ≈
destination; the filename airport is unreliable).

`PlannedWaypoint` carries name, lat/lon (FF `DDMM.m`, `geo.parse_ff_coord`),
airway, altitude, MSA, wind, OAT, heading/course, TAS, GS, leg/remaining
distance, fuel remaining/used/flow, leg time, ETA.

- **Layer A, sequencing**: a `WptEvent` at every `AtvWpt` change, with min
  `WptDst` while active.
- **Layer B, geometric abeam**: for every planned waypoint, nearest track point
  → lateral offset (`overflown` if ≤ 5 nm), abeam time/fuel/GS/TAS/alt/wind,
  ETA and fuel deltas, planned vs actual headwind.
- **Per leg**: planned vs flown distance, time, fuel (totaliser and tank), GS;
  `reliable` when both ends were overflown.
- **Off-plan**: FMS waypoints not in the plan (vectors, arrivals).
- **Layer C, totals**: distance saved, airborne time, fuel by totaliser vs
  tank, cruise wind, TOC/TOD vs plan, climb/level/descent sub-segments,
  ForeFlight model accuracy over reliable legs.
- Output: Markdown/HTML/PDF + matplotlib map (flown solid, plan dashed,
  waypoints green overflown / red skipped).

## Corridor

Scans logs that fly an anchor ↔ via corridor, cuts the common segment, clusters
by cross-track offset profile, labels each option by its most distinctive fix
(`RENAME` map) or by `DEFAULT_RULES` over the flown `AtvWpt` sequence. Key
metric: still-air time ∫(GS/TAS)dt. Offline, corpus-wide; not a per-flight view.

## Frequency prediction

See `future/frequency-bingo.md` for the model, constants and measured accuracy.
Route tools reused by any plan-aware view: `sample_route` (every 4 nm),
`altitude_profile` (2 nm per 1000 ft; the README's "3 nm" is stale),
`route_progress` (segment projection → next waypoint index, offset),
`rejoin_index` (next fix ahead within ±50° of track), `live_ladder`.

## Key exports

`Navlog`, `PlannedWaypoint`, `FlightLog`, `WptEvent`, `WaypointRecon`, `LegRecon`,
`Reconciliation`, `find_logs`, `FreqCorpus`, `FreqModel`, `Guess`, `Rung`,
`route_progress`, `rejoin_index`, `geo.cross_track_nm`, `geo.parse_ff_coord`.

## Dependencies and paths

pandas, numpy, matplotlib, pdfplumber, lxml, reportlab (`requirements.txt`), and `euro_aip` (rzflight) for
nav.db. Defaults point at the author's machine:
`~/Developer/public/flyfun-apps/main/data/nav.db` and the flightlogstats iCloud
log directory. Caches under `~/.cache/flightreconcile` (pickles).

## Gotchas

- **Abeam is a global argmin** ignoring sequence: out-and-back or self-crossing
  routes will mis-match. The Swift port must constrain matching to be monotonic
  along the track.
- **Planned headwind mixes true wind with magnetic course** (`navlog_parser.py`,
  `reconcile.py`): fix before porting.
- **Fuel used is integrated fuel flow**, because tank quantity is coarse and
  stepped; tank burn is only a cross-check.
- **G1000 `WndDr` is signed**; normalise to 0-360.
- `g1000_parser.py` duplicates the Swift parser; differences are expected in
  edge cases (quoted fields, time jumps). Parity fixtures should use logs that
  avoid them, or both parsers should be fixed together.
