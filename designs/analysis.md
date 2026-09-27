# Analysis: summaries, legs, trips, fuel

> As-built (reviewed 2026-09-27). What is derived from a parsed `FlightData`: the
> per-flight summary stored on `FlightLogFileRecord`, legs for the tables and map,
> corpus trips and visits, and the fuel refill calculator.

## Flight summary (`FlightSummary.init(data:)`)

| Quantity | Rule |
|---|---|
| Engine on (hobbs) | first/last row with `E1_PctPwr > 0` (fallback `E1_NP`) |
| Moving | `GndSpd > 0` for at least 5 consecutive rows |
| Flying | `IAS > 35` |
| Fuel start/end | first/last `FQtyL/R`, **stored as `Settings.fuelStoreUnit`** (aviation gallon) with no conversion from the log's unit |
| Totaliser | last `FTotalizerT` |
| Distance, max alt | from `.Distance`, `AltInd`/`AltMSL` |
| Route | sequence of `AtvWpt` names (`[Waypoint]`, the app's name-only struct) |
| Start/end airport | `AppDelegate.knownAirports?.nearestAirport(coord:)`, no distance cutoff |

`FlightSummary+Field.swift` exposes these as measurements (`GpH`, `NmpG`, ground
speed, ...). `GpH` divides by **moving** time (the variable is named `flying`).

## Legs (`FlightLeg`)

- `FlightLeg.legs(byfields:)` cuts the flight where a categorical value changes
  (`dataFrameForValueChange`): `[.AtvWpt]` waypoints, `[.FltPhase]`,
  `[.COM1, .COM2]` comms, `[.AfcsOn, .RollM, .PitchM]` autopilot.
- Or on a schedule (`TimeRange.schedule`, used for fixed intervals).
- Each leg carries `TimeRange` plus RZData `ValueStats` / `CategoricalStats` per
  field. The `.AtvWpt` legs are the in-app equivalent of the Python reconcile's
  "Layer A" (waypoint sequencing, min `WptDst`).
- `FlightLeg.legs(byfields: [.COM1])` is also the segmentation Frequency Bingo
  builds its index from (no debounce yet; see `future/frequency-bingo.md`).

## Trips and visits (`Trips.swift`, `Trip.swift`, `Visit.swift`)

- `computeVisits`: walk records newest first, build airport stays between an
  arriving and a departing flight; **base** = airport with most nights.
- `computeTrips`: walk oldest first per aircraft; `Trip.check` ends a trip on
  return to base, a local flight starts a new one. `.months` mode groups by
  calendar instead.
- Nothing is computed in `.trips` mode if no base is found.
- `computeVisitsSimple` appears unused.

## Fuel (`FuelTanks.swift`, `FuelAnalysis.swift`, `AircraftPerformance.swift`)

- `FuelTanks<UnitType: Dimension>` left/right quantities; `FuelQuantity`
  (volume), `FuelMass` (avgas 0.71 kg/L fixed). `init(total:)` splits 50/50.
- `FuelAnalysis`: from current tanks or totaliser, target fill → fuel to add per
  tank (the Europe gallons-vs-litres use case), and endurance from
  `AircraftPerformance` (max, tabs, gph).
- User inputs persist in `FlightFuelRecord`; aircraft performance in
  `AircraftRecord`.

## Aggregated data (`AggregatedDataOrganizer`)

FMDB table of 60 s buckets per log with a versioned config table,
`insertOrReplace`, delete by log name. **Disabled in production**; `init?`
returns nil on version or interval mismatch (no rebuild). Frequency Bingo plans
to copy the pattern but must drop-and-rebuild on mismatch.

## Key exports

| File | Symbols |
|---|---|
| `FlightSummary.swift`, `FlightSummary+Field.swift` | `FlightSummary`, `FlightSummary.Field` measurements |
| `FlightLeg.swift`, `TimeRange.swift` | `FlightLeg.legs(byfields:)`, `TimeRange.schedule` |
| `Trips.swift`, `Trip.swift`, `Visit.swift` | `Trips.computeVisits`, `computeTrips`, `Trip.check`, `Visit` |
| `FuelTanks.swift`, `FuelAnalysis.swift` | `FuelTanks`, `FuelQuantity`, `FuelMass`, `FuelAnalysis`, `FuelAnalysis.Inputs` |
| `AircraftPerformance.swift`, `AircraftRecord.swift` | `AircraftPerformance`, `AircraftRecord.aircraftIdentifier` |
| `AggregatedDataOrganizer.swift` | `AggregatedDataOrganizer` |

## Gotchas

- **`FuelTanks.isAlmostEqual` compares self to self** and always returns true, so
  every `isAlmostEqual` built on it (`FuelAnalysis.Inputs`,
  `AircraftPerformance`, `AircraftRecord`) only compares gph and ids.
- **`Trip` `NmpG` converts a distance to `UnitVolume.aviationGallon`**: a
  dimension mismatch.
- **Crosswind/headwind use CRS, not TRK** (see `log-parsing.md`).
- **Totaliser under quick parse** is per sampled row, so the quick summary's
  totaliser is far too low until the full parse replaces it.
- **Global coupling**: `FlightSummary` reads `AppDelegate.knownAirports` and
  `Settings.shared`; inject these before moving analysis into a package.
- **Untested**: trips/base detection, summary measurements, `FltPhase`,
  `FuelTanks` equality.
