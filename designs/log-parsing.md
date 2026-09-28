# Log parsing

> As-built (reviewed 2026-09-27). Garmin CSV → `FlightData` (row-major while
> parsing, column-major `DataFrame`s on demand) with calculated fields evaluated
> per row. Types from RZData (rzutils) do the columnar work.

## Pipeline

```
InputStream ─ BufferedStreamReader (1 MB chunks, byte pop)
            ─ CsvParser (byte state machine) ─ CsvInterpreter.process(line:)
            ─ FlightData.ParsingState
                 #airframe_info line  -> meta ([MetaField: String])
                 # units line         -> column kind: ignored / categorical / double
                 header line          -> FlightLogFile.Field(rawValue:) or .Unknown
                 rows                 -> values [[Double]], strings [[String]], coords
                                         + .Distance (great circle, nm)
                                         + FieldCalculation per row
            ─ convertDataFrame() (lazy) -> doubleDataFrame, categoricalDataFrame,
                                          coordinateDataFrame  (RZData DataFrame)
```

`FlightLogFile.quickParse` samples one row per 300 (5 min at 1 Hz); `parse`
reads every row.

## Fields

- `FlightLogFile.Field` (`FlightLogFile+Field.swift`): String enum of ~90 Garmin
  column names plus calculated ones (`FQtyT`, `E1_EGT_Max`, `WndCross`,
  `WndDirect`, `FTotalizerT`, `FltPhase`, `Distance`, `Coordinate`, ...).
- Metadata (order, unit, description, value vs categorical) comes from bundled
  `python/logFileFields.json`, generated from `logFileFields.csv` by
  `logFileFields.py`, loaded from `Bundle.main` into a `static var`.
- Units: `Dimension.from(logFileUnit:)` and `GCUnit.mapping`
  (`GCUnit+Logfile.swift`). Two mappings, already drifted (`"ft Baro"` is only in
  the first).
- Avionics variants (G1000, Perspective, Perspective+, twins/turbines) share one
  column mapping; there is no model-specific parser. The TBM930 test is disabled.

## Calculated fields (`FieldCalculations.swift`)

| Field | Rule | Caveat |
|---|---|---|
| `FQtyT` | L + R | |
| EGT/CHT max, min, index | over cylinders | |
| `WndCross` / `WndDirect` | wind vs **CRS** (selected course) | should arguably be TRK; CRS can be far off track |
| `FTotalizerT` | `+= E1_FFlow / 3600` per row | assumes 1 Hz; ~300× too low after a quick parse; engine 1 only |
| `FltPhase` | IAS > 35 kt and ±50 ft over 20 samples; rewrites earlier rows | |

## Orphaned files

`DataFrame.swift`, `GroupBy.swift`, `ValueStats.swift`, `CategoricalStats.swift`
in `Source/` are **not in any target**. The compiled types come from `RZData`.
The local copies are an older fork (different signatures) and must not be read
as the implementation. Delete them.

## Key exports

| File | Symbols |
|---|---|
| `BufferedStreamReader.swift` | `BufferedStreamReader` |
| `CsvParser.swift` | `CsvParser`, `CsvInterpreter` |
| `FlightData.swift` | `FlightData`, `FlightData.ParsingState`, `doubleDataFrame`, `categoricalDataFrame`, `coordinateDataFrame(for:)`, `fieldsUnits` |
| `FlightLogFile.swift` | `FlightLogFile.parse`, `quickParse`, `dataSerie`, `legs`, `mapOverlayView` |
| `FlightLogFile+Field.swift` | `FlightLogFile.Field`, `MetaField`, `fieldDefinitions` |
| `FieldCalculations.swift` | `FieldCalculation`, `calculatedFields` |
| `GCUnit+Logfile.swift` | unit mapping |
| `AvionicsSystem.swift` | `AvionicsSystem` from `rpt_` CSV or `sys_` JSON |

## Gotchas

- **Quoted spaces break.** A space inside a quoted field leaves quoted mode
  (`CsvParser.swift` default branch), so `"a b"` parses as `ab"`. The
  `#airframe_info` test line contains exactly this but asserts other keys.
- **Lone `\r` line endings throw** `invalidStateForOtherChar`.
- **Rows need the units line.** A row is kept only if its column count matches
  the units row; a file without it yields no data, silently.
- **Date shortcut.** To avoid `DateFormatter` per row, if the last digit of the
  time advanced by 0/1/2 the step is assumed to be 0/1/2 s. A real 10/11/12 s gap
  is mis-dated. The formatter has no `en_US_POSIX` locale.
- **Frames can misalign.** In `convertDataFrame` the double and categorical
  frames drop repeated dates and restart when time goes backwards, and line up
  row for row (the frequency scan checks this). The coordinate frame still uses
  the raw, un-deduplicated `dates`: any time → position lookup (map cursor, plan
  projection) must fix this first.
- **Memory**: row-major and column-major copies are both held after conversion.
- **Coupling**: field metadata and logging use `Bundle.main`, which blocks moving
  the parser into a package until switched to `Bundle.module`.
- `python/flightreconcile/g1000_parser.py` is a second, pandas-based parser of
  the same format. Keep it for the lab; parity fixtures keep the two honest.
