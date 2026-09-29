# Analysis: summaries, legs, trips, fuel

> As-built (reviewed 2026-09-27, synced 2026-09-29). What is derived from a parsed `FlightData`: the
> per-flight summary stored on `FlightLogFileRecord`, legs for the tables and map,
> corpus trips and visits, and the fuel refill calculator.

## Flight summary (`FlightSummary.init(data:)`)

| Quantity | Rule |
|---|---|
| Engine on (hobbs) | first/last row with `E1_PctPwr > 0` (fallback `E1_NP`) |
| Moving | `GndSpd > 0` for at least 5 consecutive rows |
| Flying | `IAS > 35` |
| Fuel start/end | first/last `FQtyL/R`, converted from the log's unit (`FlightSummary.fuelUnit(in:)`, from the units line, gallons if unknown) to `Settings.fuelStoreUnit` (aviation gallon) |
| Totaliser | last `FTotalizerT`, same conversion |
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
  `==` and `isAlmostEqual` compare per tank across units; `<` compares totals.
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

- **`FuelTanks` equality is per tank, ordering by total** (C11 `3f2ab0a`, C1
  `1474758`). Two tanks with the same total and a different split are neither
  `<` nor `==`; compare `totalMeasurement` when the total is what matters (as
  the fuel target segment and `testEdgeCases` do).
- **Crosswind/headwind use CRS, not TRK** (see `log-parsing.md`).
- **Totaliser under quick parse** is integrated over real time (C7), so the
  quick summary is close to the full one; it misses only the flow before the
  first sampled row.
- **Fuel records are not migrated**: logs parsed before C8 with non-gallon
  units keep their old values until re-parsed (no record version bump).
- **Global coupling**: `FlightSummary` reads `AppDelegate.knownAirports` and
  `Settings.shared`; inject these before moving analysis into a package.
- **Untested**: trips/base detection, most summary measurements, `FltPhase`.
  Tested: `FuelTanks` equality, trip `NmpG`, fuel unit conversion.
