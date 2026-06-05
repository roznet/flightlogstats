# flightreconcile

Compare a planned **ForeFlight navlog** (PDF) against the **flown route** from a
Garmin G1000 / Perspective CSV log, and produce a planned-vs-actual report:
time/ETA, fuel, wind, ground speed, route differences and shortcut savings.

## Why

A ForeFlight navlog has an `ACTUALS / ATE / ATA` column that the pilot rarely
fills in. The G1000 log already contains everything needed to fill it: position
every second, fuel quantity and flow, computed wind, and — crucially — the
active FMS waypoint (`AtvWpt`). This tool fills the actuals automatically and
quantifies how the flight differed from the plan (shortcuts, vectors, winds).

## Install / run

```sh
python3 -m venv venv
./venv/bin/pip install -r flightreconcile/requirements.txt

./venv/bin/python -m flightreconcile.cli navlog.pdf log.csv --pdf report.pdf
# or: -o report.md   /   --html report.html   (the map PNG is written alongside)
```

Outputs (any combination): `--pdf`, `--html`, `-o` (markdown). The route map PNG
is generated next to whichever report you ask for (override with `--map`).

The report includes: planned-vs-flown summary, ForeFlight model accuracy on
overflown legs only, **climb & descent vs plan** (using the `-TOC-`/`-TOD-`
pseudo-waypoints), per-waypoint and per-leg tables (fuel shown as plan /
totaliser / tank), off-plan waypoints flown, and a planned-vs-flown map.

## How it works

Three layers (see `reconcile.py`):

- **A — Waypoint sequencing.** Each time the G1000 `AtvWpt` changes, the previous
  waypoint was sequenced. Matched to planned idents → confirms which planned
  waypoints were active and the closest FMS distance achieved.
- **B — Geometric abeam.** For *every* planned waypoint (flown or skipped), find
  the closest point on the actual track → lateral offset (large ⇒ shortcut) plus
  the abeam time/fuel/GS/wind. This is the uniform comparison used in the report.
- **C — Route totals.** Planned vs flown distance/time/fuel and shortcut savings.

### Notes / data quirks handled

- ForeFlight coordinates are `DDMM.m` (e.g. `N5120.9/W00033.5`); converted to
  decimal degrees in `geo.py`.
- The navlog table spans pages and each waypoint is up to 3 stacked sub-rows;
  the parser anchors on the coordinate row and maps fields by column x-position.
- G1000 `WndDr` is stored signed; normalised to 0–360.
- Fuel tank quantity is coarse/stepped, so **actual fuel used is the integrated
  fuel flow** (apples-to-apples with the planned flow-based model). Tank-based
  burn is also reported as a cross-check.

## Modules

| file | purpose |
|---|---|
| `navlog_parser.py` | ForeFlight navlog PDF → `Navlog` (summary + planned waypoints) |
| `g1000_parser.py`  | Garmin CSV → `FlightLog` (track, fuel, waypoint events) |
| `reconcile.py`     | matching layers A/B/C → per-waypoint / per-leg / totals |
| `report.py`        | markdown report + route map PNG |
| `cli.py`           | command line entry point |
| `geo.py`           | coordinate parsing + great-circle / wind math |
