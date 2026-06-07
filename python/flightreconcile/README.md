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

./venv/bin/python -m flightreconcile.cli navlog.html log.csv --pdf report.pdf
# or: -o report.md   /   --html report.html   (the map PNG is written alongside)
```

The navlog may be a ForeFlight **HTML** export (`.html`, recommended — cleaner,
more robust to parse) or the **PDF** export (`.pdf`); the parser is chosen by the
file extension.

### Auto-matching the G1000 log

Instead of a CSV, pass a **directory** of logs (or nothing — it defaults to the
flightlogstats iCloud directory) and the matching log is found automatically from
the navlog's date + origin/destination — no need to hunt for the right file:

```sh
# simplest: just the navlog; the iCloud log directory is searched automatically
./venv/bin/python -m flightreconcile.cli navlog.html --pdf report.pdf

# or point at any directory of logs
./venv/bin/python -m flightreconcile.cli navlog.html /path/to/logs --pdf report.pdf
```

Logs are named `log_YYMMDD_HHMMSS_<airport>.csv`. Matching uses the filename date
as a prefilter, then confirms the log's **start position ≈ navlog origin** and
**end position ≈ destination** (peeking only the first fix + tail of each file).
This ignores the filename airport, which is unreliable (it can be a nearby
airport or blank), and disambiguates multiple logs on the same day.

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

## Corridor analysis — compare routing options across many flights

Separate tool (`corridor_cli`) that answers *"which way is objectively better?"*
when several routings share a common point. It scans the whole log directory,
keeps flights that fly an **anchor ↔ via** corridor, auto-clusters the common
segment into routing options, labels each by a distinctive nav fix, and compares
them with **wind-adjusted** metrics.

```sh
# default corridor EGTF <-> BILGO, iCloud logs, flyfun nav.db
./venv/bin/python -m flightreconcile.corridor_cli --pdf corridor.pdf

# any corridor
./venv/bin/python -m flightreconcile.corridor_cli --anchor EGTF --via DVR --pdf out.pdf
```

Key metric is **still-air time** = ∫(groundspeed/TAS) dt — the segment time with
the day's wind removed, so flights weeks apart are comparable. **Track NM** is
the over-ground detour; **avg TAS/alt** the speed/altitude trade. Each option
also gets a plain `short|long / low|high` profile tag.

Requires the `euro_aip` library (for the nav database) and a nav.db:
`pip install -e ~/Developer/public/rzflight/euro_aip`; default db is
`~/Developer/public/flyfun-apps/main/data/nav.db` (override with `--db`).
Scan results are cached under `~/.cache/flightreconcile`.

## Modules

| file | purpose |
|---|---|
| `navlog_parser.py` | ForeFlight navlog PDF → `Navlog` (summary + planned waypoints) |
| `navlog_html_parser.py` | ForeFlight navlog HTML → `Navlog` (preferred; uses real tables) |
| `g1000_parser.py`  | Garmin CSV → `FlightLog` (track, fuel, waypoint events) |
| `logfinder.py`     | match a navlog to the right G1000 log in a directory |
| `corridor.py`      | scan corridor flights, segment metrics, cluster + label options |
| `corridor_report.py` / `corridor_cli.py` | corridor comparison report + map + CLI |
| `reconcile.py`     | matching layers A/B/C → per-waypoint / per-leg / totals |
| `report.py`        | markdown report + route map PNG |
| `cli.py`           | command line entry point |
| `geo.py`           | coordinate parsing + great-circle / wind math |
