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
the over-ground detour; **avg/max TAS/alt** the speed/altitude trade; **Start**
the local departure time. Each option also gets a `short|long / low|high` tag.

**Routing options** are found by **track-shape clustering** (default — cleanest
map separation), each cluster labelled by its most distinctive nav fix and then
given a friendly name via the editable `RENAME` map in `corridor.py` (e.g.
`RCH → "OCAS (low, OCK/LYD)"`). Tune the number of options with `--cluster-rms`.

Alternatively `--rules` groups by the *fixes actually flown* (FMS sequence) using
the editable `DEFAULT_RULES` — strategy labels like **OCAS** (low via OCK/LYD)
vs **Airways** (via GWC), split by the **CMB shortcut**. (`M25*` are treated as
custom OCAS departure fixes.) Rules capture intent precisely but the clusters
draw a cleaner map.

Requires the `euro_aip` library (for the nav database) and a nav.db:
`pip install -e ~/Developer/public/rzflight/euro_aip`; default db is
`~/Developer/public/flyfun-apps/main/data/nav.db` (override with `--db`).
Scan results are cached under `~/.cache/flightreconcile`.

## Frequency prediction — which ATC frequency am I likely to get?

Separate tool (`freq_cli`) that answers *"what will I be told to call next?"*
from your own logs. Every G1000 log records the **active COM1/COM2 frequency**
once a second, so the corpus is a record of where, how high and in which
direction each frequency was actually used.

```sh
# the frequency sequence to expect along a route
./venv/bin/python -m flightreconcile.freq_cli route EGTF OCK LYD LFAT --alt 5000

# what am I on now, and what comes next, at a position
./venv/bin/python -m flightreconcile.freq_cli at 51.32 -0.49 --alt 3000 \
    --trk 90 --current 125.250

# how good is it? leave-one-flight-out over the whole corpus
./venv/bin/python -m flightreconcile.freq_cli eval

# which frequencies appear in the logs, where, and at what level
./venv/bin/python -m flightreconcile.freq_cli list

# the parity fixture the app's Swift port is tested against (TestFrequencyModel)
./venv/bin/python -m flightreconcile.freq_cli --dir ../flightlogstatsTests/TestAssets \
    fixture ../flightlogstatsTests/TestAssets/freq_fixture.json
```

`route` prints a **ladder**: the predicted frequency for each stretch of the
route, with the along-track distance where it changes, how confident the vote is
and how many past flights back it. Read it as a watch list, not a clearance.

### How it works

Two signals are blended (`freq.py`):

- **Where you are.** A k-nearest-neighbour vote over the indexed points. The
  distance is horizontal NM **+ 6 NM per 1000 ft** of altitude difference **+ up
  to 25 NM** for flying the opposite way. Direction and altitude matter because
  the *point* of a handoff is diffuse (median ~20 NM spread around its centroid)
  while the *region* a frequency covers is well defined. Asking "which sector am
  I in" beats "which handoff point is nearest" by a wide margin.
- **What you are on.** A transition table, P(next | current), since handoff
  chains are stable.

Accuracy on the author's corpus (459 logs, 143k indexed points, 396 distinct
frequencies), leave-one-flight-out:

| question | top-1 | top-3 |
|---|---|---|
| most common frequency (baseline) | 5.5% | 13.1% |
| which frequency am I on now | 62.1% | 83.3% |
| next frequency, current known | 56.6% | 71.8% |
| next frequency, position only | 50.3% | 68.5% |

Distance to the next handoff is estimated to a median error of ~8 NM.

### Notes / data quirks handled

- **Radio flicker.** A standby swap made and undone shows up as a one-second
  frequency run; roughly a tenth of raw runs are this kind of noise and would
  otherwise look like handoffs. Runs shorter than `MIN_DWELL_S` (60 s) are
  dropped and equal neighbours merged — except the first and last, which are the
  ground frequencies and are short only because the log starts or stops there.
- **Evaluation leakage.** Scoring a flight while its *own* transitions are still
  in the table overstates next-frequency accuracy by several points, so
  `evaluate()` subtracts the held-out flight from both signals.
- **Airspace changes.** Frequencies renumber (8.33 kHz) and sectors are
  reorganised, so `--since YYYY-MM-DD` restricts the model to recent flights.
  Log dates come in both `YYYY-MM-DD` and `DD/MM/YYYY` and are normalised.
- **Climb and descent.** `route` ramps the altitude at 3 NM per 1000 ft at each
  end rather than assuming cruise level throughout, because tower and approach
  frequencies live low and area control lives high.
- There is **no AIP frequency database** in nav.db, so frequencies cannot be
  named ("London Information"). `list` labels them instead by the nearest fix or
  airport to where they are used, plus the altitude band.

Only COM1 is modelled. COM2 holds a useful hint (the next frequency is often
tuned there before the swap) but is noisy with ATIS and monitoring.

## Modules

| file | purpose |
|---|---|
| `navlog_parser.py` | ForeFlight navlog PDF → `Navlog` (summary + planned waypoints) |
| `navlog_html_parser.py` | ForeFlight navlog HTML → `Navlog` (preferred; uses real tables) |
| `g1000_parser.py`  | Garmin CSV → `FlightLog` (track, fuel, waypoint events) |
| `logfinder.py`     | match a navlog to the right G1000 log in a directory |
| `corridor.py`      | scan corridor flights, segment metrics, cluster + label options |
| `corridor_report.py` / `corridor_cli.py` | corridor comparison report + map + CLI |
| `freq.py`          | frequency segments + point index, kNN/transition model |
| `freq_cli.py`      | frequency prediction CLI (route / at / eval / list) |
| `reconcile.py`     | matching layers A/B/C → per-waypoint / per-leg / totals |
| `report.py`        | markdown report + route map PNG |
| `cli.py`           | command line entry point |
| `geo.py`           | coordinate parsing + great-circle / wind math |
