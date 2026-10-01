# Log parsing

> As-built (reviewed 2026-09-27, synced 2026-09-29 after the phase 0 fixes).
> Garmin CSV → `FlightData` (row-major while
> parsing, column-major `DataFrame`s on demand) with calculated fields evaluated
> per row. Types from RZData (rzutils) do the columnar work.

## Pipeline

```
InputStream ─ FastCsv.CsvParser (1 MB chunks, byte state machine)
            ─ CsvInterpreter.process(row: CsvRow)   fields kept as bytes
            ─ FlightData.ParsingState               doubles via row.doubles(at:into:)
                 #airframe_info line  -> meta ([MetaField: String])
                 # units line         -> column kind: ignored / categorical / double
                 header line          -> FlightLogFile.Field(rawValue:) or .Unknown
                 rows                 -> values [[Double]], strings [[String]], coords
                                         + .Distance (great circle, nm)
                                         + FieldCalculation per row
            ─ convertDataFrame() (lazy) -> keptRows(dates:) once, then
                                          doubleDataFrame, categoricalDataFrame,
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
  the first). Litre spellings (`L`, `ltr`, `liters`, ...) map to
  `UnitVolume.liters` in `Dimension.from` only; none has been seen in a real log.
- Avionics variants (G1000, Perspective, Perspective+, twins/turbines) share one
  column mapping; there is no model-specific parser. The TBM930 test is disabled.

## Calculated fields (`FieldCalculations.swift`)

| Field | Rule | Caveat |
|---|---|---|
| `FQtyT` | L + R | |
| EGT/CHT max, min, index | over cylinders | |
| `WndCross` / `WndDirect` | wind vs **CRS** (selected course) | should arguably be TRK; CRS can be far off track |
| `FTotalizerT` | `+= E1_FFlow × elapsed / 3600`, elapsed = seconds since the previous parsed row (`usesElapsed`) | right-rectangle rule, so a quick parse loses the flow before its first sampled row; time going backwards counts as 0; engine 1 only; flow assumed per hour in the fuel quantity unit |
| `FltPhase` | IAS > 35 kt and ±50 ft over 20 samples; rewrites earlier rows | |

## RZData types

`DataFrame`, `ValueStats`, `CategoricalStats` and the group-by come from
`RZData` (a declared package product). The old local copies in `Source/` were
deleted (`c09955d`).

## Key exports

| File | Symbols |
|---|---|
| `Packages/FastCsv/Sources/FastCsv/CsvParser.swift` | `CsvParser`, `CsvInterpreter`, `CsvRow` |
| `FlightData.swift` | `FlightData`, `FlightData.ParsingState`, `doubleDataFrame`, `categoricalDataFrame`, `coordinateDataFrame(for:)`, `coordinateColumn`, `fieldsUnits`, `keptRows(dates:)`, `secondsOfDay(_:)` |
| `FlightLogFile.swift` | `FlightLogFile.parse`, `quickParse`, `dataSerie`, `legs`, `mapOverlayView` |
| `FlightLogFile+Field.swift` | `FlightLogFile.Field`, `MetaField`, `fieldDefinitions` |
| `FieldCalculations.swift` | `FieldCalculation` (`usesElapsed`), `calculatedFields` |
| `GCUnit+Logfile.swift` | unit mapping |
| `AvionicsSystem.swift` | `AvionicsSystem` from `rpt_` CSV or `sys_` JSON |

## Gotchas

- **Quoting.** A field is quoted only if the quote opens it (after optional
  spaces); spaces inside are kept, spaces after the closing quote are dropped. A
  quote inside an unquoted field is kept as a character (`key="a b"` in
  `#airframe_info` stays whole and the interpreter strips the quotes). `\n`,
  `\r\n` and lone `\r` all end a line (C4, `efc121a`).
- **Rows need the units line.** A row is kept only if its column count matches
  the units row; a file without it yields no data, silently.
- **Date shortcut.** To avoid `DateFormatter` per row, a row whose date and
  offset columns equal the previous row's is dated from the previous date plus
  the difference in `HH:mm:ss` seconds of day: exact for any gap and any
  sampling. Otherwise the formatter (`en_US_POSIX`) parses it (C5, `d14c589`).
- **Rows kept in the frames.** `keptRows(dates:)` drops a repeated date (keeps
  the first row) and restarts when time goes backwards (the log restarted: the
  rows before are dropped). All three frames use it, so they line up row for row
  and a time lookup on coordinates is safe (C3, `ecbd8ee`). `count`,
  `firstCoordinate` and `lastCoordinate` still read the raw rows.
- **Memory**: row-major and column-major copies are both held after conversion.
- **Speed, Debug vs Release.** The CSV loop is ~5x slower unoptimised and Swift
  optimises per module, not per file (`@_optimize(speed)` does nothing at
  `-Onone`). So the CSV layer is the local `FastCsv` package, built `-O` in Debug
  too. Keep the per-field work behind `CsvRow` calls and nothing `@inlinable`:
  inlined code would compile into the Debug app unoptimised. Measured on EGLL
  (5.4 MB) by `TestParsingSpeed`, see the commit for numbers.
- **Numbers from bytes.** `CsvRow.double(at:)` equals `Double(String)` bit for bit:
  plain decimals take the exact Clinger fast path (mantissa ≤ 2^53, ≤ 22
  decimals, one correctly rounded division), anything else falls back to
  `Double(String)`. `strtod_l` is not bridged to Swift.
- **Rows are views.** A `CsvRow` shares the parser's buffer; keeping one copies it
  on the next line (copy on write), so it is safe but not free.
- **Coupling**: field metadata and logging use `Bundle.main`, which keeps
  `FlightData` and the interpreter in the app (only the CSV layer is a package).
- `python/flightreconcile/g1000_parser.py` is a second, pandas-based parser of
  the same format. Keep it for the lab; parity fixtures keep the two honest.
