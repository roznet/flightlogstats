# Frequency Bingo — guessing the ATC frequency from your own logs

> Status: **phase 1 done** (index + model, PR #10), and the per-flight
> frequency timeline built on the index (PR #PRNUM, modernisation §Phase 3 step 0);
> plan mode is next. The model was built,
> tuned and validated in Python (`python/flightreconcile/freq.py`, `freq_cli.py`)
> and is ported to Swift in `FrequencyModel.swift`, with the persistent index in
> `FrequencyIndexOrganizer.swift`. The prerequisite has landed: nav.db is bundled,
> so route fixes resolve on device (commit `a3636bc`).
> Related: [../../python/flightreconcile/README.md](../../python/flightreconcile/README.md)
> (the reference implementation and its `eval` harness).
> Position engine shared with [../plans/plan-vs-actual.md](../plans/plan-vs-actual.md)
> (`RouteTracker`: log replay and live GPS drive the same rejoin logic).

Every G1000 log records the **active COM1 frequency once a second**. A corpus of
logs is therefore a record of where, at what altitude and in which direction
every frequency was actually used. This feature turns that into a prediction:
*which frequency will I be given next, and when?*

## Decisions taken

| Area | Decision |
|---|---|
| What is modelled | **COM1 only.** COM2 carries a hint (the next frequency is often tuned there before the swap) but is noisy with ATIS and monitoring |
| Core model | **kNN over logged points, blended with a `P(next \| current)` transition table.** No ML framework; ~150 lines of Swift |
| Distance metric | horizontal nm **+ 6 nm per 1000 ft** of altitude difference **+ up to 25 nm** for opposite track. Tuned by leave-one-flight-out |
| Why not handoff points | Tune-in points scatter with a **median 20 nm** spread. The *region* a frequency covers is well defined; the point you were given it is not |
| Altitude | **First-class input, not a detail.** Sectors are stacked; the answer genuinely changes with level |
| Index storage | A dedicated `FrequencyIndexOrganizer` on the `AggregatedDataOrganizer` pattern (FMDB, versioned config table, delete-by-log-file-name) |
| Index build | Incremental, hooked next to the existing call in `updateRecords` |
| Version mismatch | **Drop and rebuild.** Do *not* copy `AggregatedDataOrganizer`'s behaviour of returning nil, which silently disables the feature |
| Page placement | New tab in `StatsTabBarController` — corpus-wide, not tied to a selected log |
| Modes | **Plan** (route + altitude → ladder) and **Live** (GPS), one page |
| Off route | Rejoin at the next fix ahead on the route, within ±50° of track — the IFR assumption |
| GPS | iPad with GPS. Baro-vs-GPS altitude disagreement is accepted (~1 nm of metric cost) |
| Frequency naming | **None.** No AIP frequency data exists in nav.db. Label by nearest fix + altitude band instead |
| Confidence | Probability **and** supporting-flight count always shown together |
| Near ties | Shown side by side, highest first, left to right — not as a ranked winner |
| Map labels | **Numbered markers keyed to the list.** Labels on the line collide into an unreadable pile on a diagonal route |

## The measured case

Leave-one-flight-out over the author's corpus — 459 logs, 143,403 indexed
points, 3,119 frequency segments, **396 distinct frequencies**:

| Question | top-1 | top-3 |
|---|---|---|
| Most common frequency (baseline) | 5.5% | 13.1% |
| **Which frequency am I on now** | **62.1%** | **83.3%** |
| Next frequency, current known | 56.6% | 71.8% |
| Next frequency, position only | 50.3% | 68.5% |

Distance to the next handoff lands within a **median 7.9 nm** (p90 28.4 nm).

**On a route with history it is markedly better.** Across the 10 logged
LSGS→EGTF flights, 671 sample points each predicted with its own flight held
out: **75.9% top-1, 94.6% top-3**. That is the number that matters for the page,
since it is used where there is history.

### It finds sector boundaries unaided

On LSGS→EGTF the DJL→REM stretch flips from 118.890 to 132.100 between 11,000
and 12,000 ft — which matches the author's own experience, and was never told to
the model:

```
  level       freq
  11000    118.890 [####################] 100%
  11500    118.890 [#############       ]  63%   then 132.100 37%
  12000    132.100 [############        ]  61%   then 118.890 39%
  13000    132.100 [##################  ]  91%   then 118.890  9%
  16500    132.100 [####################] 100%
```

The 60/40 split at the boundary is the honest answer, and the UI must be able to
show it as such rather than picking a winner.

## The model

Two signals, blended as log-probabilities (`FreqModel.next` in `freq.py`):

1. **Where you are.** The K nearest logged points vote for their frequency,
   weighted `1/(d + 2)`. Direction and altitude are folded into `d`.
2. **What you are on.** `P(next | current)`, counted over the segments. Handoff
   chains are stable, so this sharpens the guess considerably.

Constants, all tuned by the eval harness — **change them there, not by feel**:

| Constant | Value | Meaning |
|---|---|---|
| `STEP` | 15 s | index sampling interval |
| `MIN_DWELL_S` | 60 s | shorter runs are radio flicker, not handoffs |
| `MIN_GS_KT` | 15 kt | below this we are parked |
| `ALT_NM_PER_1000FT` | 6.0 | altitude cost in the metric |
| `DIR_PENALTY_NM` | 25.0 | cost of flying the exact opposite way |
| `K_NEIGHBOURS` | 60 | |
| `SOFTEN_NM` | 2.0 | weight is `1/(d + SOFTEN_NM)` |
| `BLEND_TRANSITION` | 0.4 | transition table vs spatial vote |
| `CLIMB_NM_PER_1000FT` | 2.0 | measured off this author's own climbs |

### Performance

143k points is small. One `current()` query is a full scan and is sub-millisecond
in Swift; a 479 nm ladder is ~120 queries, a few tens of milliseconds. **No
spatial index is needed**, and a KD-tree would not help anyway — the metric is
not Euclidean. Recompute freely on every altitude change and GPS update.

## Data layer

### The index

Two things per log, both derived from what `FlightLeg` already produces:

**Segments** — one continuous period on a COM1 frequency:
`freq, log_file_name, date, t_start, dur_s, nm, lat/lon/alt/trk at entry,
lat/lon/alt at exit, prev_freq, next_freq, wpt_in`.

`FlightLeg.legs(byfields: [.COM1])` ([FlightLeg.swift:96](../../flightlogstats/Source/FlightLeg.swift#L96))
already produces exactly these dwell periods — this is the same segmentation
`LogMapGraphsViewController` uses for its comm view
([LogMapGraphsViewController.swift:59](../../flightlogstats/Source/LogMapGraphsViewController.swift)).
What it does **not** do is debounce; see Gotchas.

**Points** — every `STEP` seconds: `lat, lon, alt, trk, gs, freq, next_freq,
nm_to_next, log_file_name`. `next_freq` and `nm_to_next` are per-flight
derivations (walk the flight in time order), not stored per row if you would
rather compute them on load — 3,119 segments is nothing.

Roughly 4 MB of packed floats for the whole corpus; 10–15 MB as SQLite rows.

### Incremental build

`FlightLogOrganizer.updateRecords` already parses each new log and, right there,
updates the aggregated store
([FlightLogOrganizer.swift:381](../../flightlogstats/Source/FlightLogOrganizer.swift)).
The frequency index hooks in alongside it. `delete(info:)` must remove rows by
`log_file_name`, exactly as the aggregated store does.

### Reading one log

`FrequencyIndexOrganizer.logIndex(logFileName:)` returns one log's segments and
points in time order (`seq`), nil if the log is not indexed, and an empty index
for a log indexed without signal (taxi only, no radios). `logIndex(flightLog:)`
indexes a log that is missing first, through the same `insertOrReplace(flightLog:)`
as the hook and the backfill, and records nothing if the log does not parse. The
Frequencies tab of the log view (`FrequencyTimeline.swift`,
`FrequencyTimelineView.swift`) is its consumer.

Points store no segment number; `FrequencyTimeline.pointsBySegment` recovers it
from `freq`, `nextFreq` and non-increasing `nmToNext` (exact on every TestAssets
log). If a consumer ever needs it guaranteed, store `seg` in `freq_points` and
bump `currentDatabaseVersion` (a full rebuild).

### Copy the pattern, not two of its behaviours

`AggregatedDataOrganizer` is the model to follow — FMDB, a versioned config
table, `insertOrReplace`, delete-by-name. Two things about it to **not** inherit:

1. It is **disabled in production**
   ([FlightLogOrganizer.swift:667](../../flightlogstats/Source/FlightLogOrganizer.swift)
   — the initialiser is commented out), so it is only exercised by tests. Don't
   assume it is a proven-in-the-field path.
2. `checkOrInitDb` returns **nil on a version mismatch**, so bumping the version
   silently disables the store instead of rebuilding it. A frequency index must
   drop and rebuild, or a tuning change leaves a stale index with no signal.

### Reuse alternative, considered and rejected

Adding `.COM1: [.mostFrequent]` and `.TRK: [.average]` to
`FlightLogFileAggregatedData.defaultSchema` would make the existing 60-second
aggregation produce most of the point index for free. Rejected because 60 s is
**2.5 nm of sampling at 150 kt** against 0.6 nm here, which would blur a 5 nm
rung like the 119.175 out of Sion; and the debouncing and per-flight
next-frequency walk do not fit the generic metric schema. Worth revisiting if
the dedicated store proves burdensome.

## Prediction API (Swift)

Mirror `freq.py` so the two stay comparable:

```swift
struct FrequencyGuess { let freq: String; let prob: Double
                        let support: Int; let nmToChange: Double? }

final class FrequencyModel {
    func current(lat:lon:alt:trk:top:) -> [FrequencyGuess]
    func next(lat:lon:alt:trk:current:top:) -> [FrequencyGuess]
    func when(lat:lon:alt:trk:) -> Double?          // nm to next handoff
    func routeLadder(points:cruiseAlt:) -> [Rung]
    func liveLadder(points:lat:lon:alt:trk:fromIndex:) -> ([Rung], Int?)
    func segments(for freq: String) -> [FrequencySegment]   // for the flight list
}

// per flight, on the index rather than the model (FrequencyIndexOrganizer)
func logIndex(logFileName: String) -> FrequencyLogIndex?     // nil: not indexed
func logIndex(flightLog: FlightLogFile) -> FrequencyLogIndex? // indexes if missing
```

`Rung` carries `freq, fromNm, toNm, confidence, support, alt, alternates,
unsettled`.

## The page

### Plan mode

Route field + cruise altitude → the ladder. Route parsing uses
`RoutePointResolver(airports:waypoints:)` from RZFlight over
`AppDelegate.knownAirports` / `AppDelegate.knownWaypoints`, both now loaded from
nav.db. A stepper on altitude re-runs the ladder in place.

```
   from      to      freq   conf  flights     alt  also likely
      0      13   118.275  100%       40    1000
     13      18   119.175   91%       12    7565  126.350 125.550
     72     133   125.415   64%        5   11000  124.105 126.990
    137     230   118.890  100%        6   11000  124.105 125.415
```

### Live mode

GPS position, altitude and track drive the same model. Shows the current
frequency, the next, and distance/ETA to the handoff. Ground speed gives the
ETA. Recompute on each location update — it is cheap.

The only session state is **the highest waypoint index reached**, for the rejoin
rule. Reset it when the route is edited. Everything else is a pure function of
position, altitude and track, so the card cannot drift out of sync.

### The frequency table, and the flights behind it

A frequency list ordered along the route, with probability, supporting-flight
count and location, current and next highlighted. **Tapping a frequency opens a
small table below listing the flights that contribute it** — segments carry
`log_file_name`, which is the key of `FlightLogFileRecord`, so each row is a
real record that can be pushed into the existing detail view.

### The map

Reuse the `FlightDataMapOverlay` / `FlightDataMapOverlayView` pattern
([FlightData+Map.swift](../../flightlogstats/Source/FlightData+Map.swift)) — a
custom `MKOverlayRenderer` already draws a track with a highlighted range.

- **Route coloured per rung**, colour cycling so adjacent legs contrast.
- **Numbered markers at each handoff**, keyed to the list. Tap either to
  highlight both. *Labels are not drawn on the line* — on a diagonal route they
  collapse into an unreadable pile, which is what the first Python rendering did.
- **A faint scatter of the logged points backing each frequency**, as a toggle.
  This is the most valuable layer and the least obvious: it shows *why* the model
  said something, and makes thin support visible rather than implied. Clip it to
  the route's bounding box or a frequency used elsewhere blows out the view.
- Current position marker in live mode.

`freq_report.save_route_map` is the reference rendering.

### Off route — the rejoin rule

Vectors, a shortcut, a diversion. Assume the IFR outcome: you rejoin at the next
fix you are actually flying towards.

Candidates start at **the next waypoint along the route**, found by projecting
the position onto each leg. Among those, take the first within **±50°** of the
current track. Nothing ahead (a hold, a 180 for weather) falls back to the next
one along. A `fromIndex` floor keeps progress monotonic.

The along-route projection is not optional: **bearing alone nominated the
departure airport** when flying south from mid-route, which is genuinely ahead by
bearing but is not a rejoin.

The remaining route becomes `[current position] + route[rejoinIndex...]`, fed to
the same ladder code — off-route is not a special mode.

## Parity with the Python reference

Export a fixture of query points with the Python model's expected top-3, and
assert against it in `flightlogstatsTests`. Without it the two implementations
drift and there is no way to tell which is wrong. `freq_cli eval` stays the
reference for any model change.

Done: `freq_cli fixture` scans `flightlogstatsTests/TestAssets` and writes
`TestAssets/freq_fixture.json`, which `TestFrequencyModel` replays. It carries
three things, checked separately so a failure says which half drifted:

- the **segments** per log, against the Swift scan of the same CSVs (debounce,
  first/last run rule, durations, distances);
- the **point index** itself, rounded, so the model is tested on exactly the
  corpus the expectations came from, independent of small differences between
  the two CSV readers;
- expected `current`, `next` (with and without the current frequency) and `when`
  per query, each with and without its own flight held out, plus two route
  ladders (one with an unsettled band) and a live ladder with its rejoin index.
  The tuned constants are asserted too.

Regenerate it after any change to `freq.py`, never by hand:

```
cd python
python -m flightreconcile.freq_cli --dir ../flightlogstatsTests/TestAssets \
    fixture ../flightlogstatsTests/TestAssets/freq_fixture.json
```

### Backfill

Parsing is what feeds the incremental hook, and logs already parsed are never
parsed again, so an index added to an existing install (or dropped by a version
bump) would never fill. `FlightLogOrganizer.updateRecords` therefore, once
nothing is left to parse, re-parses a batch of parsed logs missing from the index
and reschedules itself until none are left. Every processed log is recorded in
`freq_logs`, including those that yield nothing, so none is retried forever.

## Phasing

1. **Index + model**, with the fixture test. No UI.
2. **Plan mode** — table and map. Useful on the ground on its own.
3. **Live mode** — needs `NSLocationWhenInUseUsageDescription` and a
   `CLLocationManager`; the app has no location permission at all today.
4. **Confirmation taps** (see below).

## Gotchas

- **Radio flicker.** A standby swap made and undone is a one-second run;
  **roughly a tenth of raw runs** are this noise and would otherwise look like
  handoffs. Drop runs under `MIN_DWELL_S` and merge equal neighbours — *except
  the first and last*, which are the ground frequencies and are short only
  because the log starts and stops there.
- **Evaluation leakage.** Scoring a flight with its own transitions still in the
  table overstates next-frequency accuracy by **several points** (it read 60.3%
  against a true 56.6%). Any eval must subtract the held-out flight from *both*
  signals.
- **Never let a confident rung absorb an uncertain one.** Merging short rungs
  into the *previous* rung made the ladder claim "123.430, 87%" for 19 nm out of
  EGTF, where the model really says 134.355 / 123.225 / 124.600 at about 40%
  each. Runs of short unconvincing rungs must collapse into a band of their own,
  carrying their candidates and their low confidence. **Overstating is the one
  thing this page cannot do.**
- **Climb and descent are separate.** Using one altitude for both the start of
  the climb and the end of the descent means that in live mode — where cruise
  equals current altitude — the profile stays level to the threshold and
  **every arrival frequency is lost**.
- **Short but solid rungs are real.** Approach and tower sectors are only a few
  miles of route and are the ones worth knowing. A short rung survives when
  confidence ≥ 0.6 and support ≥ 5.
- **Airspace changes.** Frequencies renumber for 8.33 kHz and sectors are
  reorganised, so offer a "recent flights only" filter (`--since` in the CLI).
  Log dates come in both `YYYY-MM-DD` and `DD/MM/YYYY` and must be normalised or
  a string compare silently gets the ordering wrong.
- **Thin coverage is common and must be visible.** The LSGS→EGTF ladder has
  rungs at "100%" backed by 2 flights. Confidence and support belong side by side.
- **This is a watch list, not a clearance.** It predicts from one pilot's history
  and can be confidently wrong where the corpus is thin. Say so on the page.

## Not built (deliberate)

- **Frequency names.** nav.db has no AIP frequency data (`aip_entries` is
  empty), so "London Information" is not available. Nearest fix + altitude band
  is the fallback. Revisit if AIP frequencies land in nav.db.
- **COM2 modelling.** See above.
- **Confirmation taps feeding the model.** The app cannot read the radio, so the
  pilot's tap is the only in-flight ground truth. Knowing the current frequency
  is what lifts next-frequency accuracy from 50% to 57%, so confirmations are
  worth capturing — and they also give a predicted-vs-actual review afterwards.
  Phase 4, not phase 1.
- **Sharing a corpus between pilots.** Everything here is one pilot's own
  history. Pooling would change the privacy story entirely.
