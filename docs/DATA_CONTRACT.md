# Snapshot data contract

The MQL5 snapshot API and JSON exporter share a versioned contract. Detection runs in MQL5; external programs consume the result. The authoritative shape is [snapshot.schema.json](../schemas/snapshot.schema.json). A deliberately unsorted [example snapshot](../tests/fixtures/snapshot-v1.json) and its [expected sample output](../tests/fixtures/snapshot-v1.expected.txt) are shared by the Python, TypeScript, C#, Go, Java, and Rust examples.

## Version and time

`schema_version` starts at `"1.0"`; `library_version` identifies the producer release independently. Consumers accept version strings matching `1.<minor>` and ignore additional properties. They must reject unsupported major versions, missing required fields, incorrect field types, and invalid numeric values. A new major version is required for incompatible changes to existing fields. Additional object properties do not replace any required field.

`time_basis` is `"broker"`. All timestamps use `YYYY-MM-DDTHH:MM:SS`, with no `Z` or UTC offset. They are MT5 broker-local wall-clock times, not UTC instants. Do not attach a UTC suffix or assume a fixed offset: a broker's clock rules may change with daylight saving time. A consumer that needs UTC must obtain the broker's historical time-zone rules separately.

`as_of` is the closing timestamp of the latest evaluated candle. It is `null` before data is available. Each module carries its own `as_of`; missing data must not appear as a current successful evaluation. `source_time` identifies the source candle or pivot by its opening timestamp. `confirmed_at` is the closing timestamp at which the result became knowable. `SmcBarClosedAt()` adds the timeframe duration for ordinary candles and uses midnight on the first day of the next calendar month for `MN1`; a month is not treated as a fixed 30-day interval. `updated_at` is the closing timestamp of the latest lifecycle update. All use broker time.

## Envelope and module status

Every envelope contains `schema_version`, `library_version`, `symbol`, `timeframe`, `time_basis`, `as_of`, `status`, `config`, `modules`, and `records`. `timeframe` uses the MT5 short name, for example `M5`, `H1`, or `D1`. An optional `message` string carries snapshot-level diagnostics, including failures in legacy Currency Strength or VIX modules; an empty string means no additional diagnostic. Its absence remains valid for existing version 1 consumers.

| Status | Meaning |
| --- | --- |
| `READY` | Every enabled module completed its evaluation; an empty result is valid. |
| `PARTIAL` | Some enabled modules could not finish; inspect their status before using their results. |
| `NOT_READY` | Required history or comparison data is unavailable. |
| `ERROR` | Evaluation failed; do not treat a prior result as a current success. |
| `DISABLED` | A module was intentionally disabled. |

A module entry contains `concept`, `status`, `as_of`, `truncated`, and `message`. `truncated: true` means the configured output cap removed older results after calculation. `message` explains an unavailable or failed module and may be empty on success. A disabled SMT module is expected when no comparison symbol is configured. Consumers must distinguish disabled or unavailable modules from a successfully evaluated module with no matching records.

## Configuration

All configuration fields are required in JSON, even when they equal the defaults. The schema's `default` annotations document defaults; consumers must not use them to repair an incomplete file.

`SmcConfig::WarmupBars()` derives additional history from detector dependencies. It uses the larger of the zone ancestry horizon (including both the original FVG and derived IFVG lifetimes) and the bounded prior-pivot horizon needed by MSS and SMT. This history precedes the visible `lookback_bars` evaluation window and changes with configuration.

| Fields | Default |
| --- | --- |
| `lookback_bars`, `max_records_per_concept`, `swing_strength` | `500`, `100`, `5` |
| `displacement_baseline`, `displacement_multiplier`, `displacement_body_fraction` | `20`, `1.5`, `0.6` |
| `min_fvg_pips`, `max_zone_age`, `bpr_max_separation`, `po3_expiry_bars` | `2`, `200`, `50`, `20` |
| `smt_symbol`, `smt_radius` | `""`, `1` |
| `enable_calendar`, `enable_po3`, `enable_displacement`, `enable_mss`, `enable_ifvg`, `enable_bpr` | `true` |
| `enable_draw`, `enable_smt`, `enable_cs`, `enable_vix` | `false` |

`sessions` contains three objects with `name`, `start_minute`, and `end_minute`. Minutes are measured from broker midnight, from `0` through `1439`. The defaults are Asian `[0,480)`, London `[420,960)`, and NewYork `[720,1260)`. The start is inclusive and the end exclusive. An end earlier than the start denotes a session crossing midnight; equal boundaries are invalid. Names must be nonempty and unique; the first session is the Power of Three accumulation session. Custom hours remain broker-local.

A nonempty `smt_symbol` enables SMT even when `enable_smt` is `false`; setting `enable_smt` to `true` requires a nonempty comparison symbol. The schema records the same numeric bounds as `SmcConfig::Validate()`. Cross-field session constraints require semantic validation after JSON Schema validation.

## Detection records

Each record requires the following fields:

| Fields | Meaning |
| --- | --- |
| `id`, `concept` | Stable event identifier and concept name. An ID does not change when lifecycle state changes. |
| `source_time`, `confirmed_at`, `updated_at` | Broker-local source, confirmation, and lifecycle timestamps. |
| `direction` | `bullish`, `bearish`, or `neutral`. |
| `lower`, `upper` | Inclusive price interval; a price level uses identical values. |
| `state`, `active` | Concept-specific lifecycle label and whether the result remains active. |
| `related_ids` | IDs of source results, such as the FVG that generated an IFVG. |
| `period_start`, `period_end` | Associated calendar/session boundaries, or `null` when not applicable. |
| `reference_price`, `comparison_price`, `strength` | Concept-specific numeric measurements; `0` when unused. |
| `reason` | Human-readable explanation, or an empty string. |

The known concept names are defined in the schema. These include the existing swing, structure, zone, liquidity, premium/discount, OTE, and session results, plus Displacement, MSS, IFVG, BPR, previous-period levels, session levels, broker daily/weekly gaps, SMT, and Power of Three.

Zone lifecycle labels include `FRESH`, `TESTED`, `MITIGATED`, and `BROKEN`. `active` is separate from `state`: an expired zone can retain its last lifecycle label and become inactive, with expiry recorded in `reason`. Other concepts may use labels such as `CONFIRMED`. Consumers must not interpret every record as a zone or assume every inactive record is broken. References may point outside the current output window or to a result removed by a result cap, so absence from `records` does not invalidate a `related_ids` entry.

JSON Schema validates shape, required fields, enums, and per-field bounds. Consumers also validate finite numeric values and `lower <= upper`; numeric comparisons between different fields are not expressible in standard JSON Schema. Producers preserve real calendar dates, chronological timestamps (`source_time <= confirmed_at <= updated_at <= as_of`), unique record IDs, unique module concepts, and `period_start < period_end` when both boundaries are present. Applications may validate these additional invariants when ingesting untrusted files. Empty strings, `null`, `0`, and absent fields have different meanings and must not be interchanged; empty `smt_symbol`, `reason`, and `message` values are valid.

## File and sample behavior

The exporter writes UTF-8 JSON in the MT5 common files directory. It completes a temporary file before replacing the destination so readers do not consume an in-progress document. Pass the snapshot file path to an external example; examples do not place trades and do not reproduce detection logic.

Each sample prints one envelope line followed by records sorted by `id`, optionally filtered by concept and direction. Fields in each record row are separated by tabs in this order: `id`, `concept`, `direction`, `state`, `lower`, `upper`. Prices use a dot and exactly eight decimal places; output ends with a newline.

For consistent output across languages, readers interpret JSON price numbers as IEEE 754 binary64 values and round that exact binary value to eight fractional digits using round-to-nearest, ties-to-even. Do not round the original decimal spelling or a value obtained by multiplying the floating-point price by `100000000`; either can change the boundary. For example, `0.001953125` prints as `0.00195312`, while the binary64 value parsed from `1.000000005` prints as `1.00000000`. Any value that rounds to zero, including negative zero and tiny negative prices, prints as `0.00000000`. Large finite values retain fixed decimal notation, never scientific notation.

The envelope line is:

```text
status=READY symbol=EURUSD timeframe=M5 as_of=2026-09-18T12:00:00 time_basis=broker
```

The fixture contains a broken bullish FVG, its fresh bearish IFVG, and a confirmed bearish MSS. Its symbolic IDs make the example readable; production IDs are generated from detection identity. It is a contract fixture, not an assertion that these events were observed in live EURUSD market data.
