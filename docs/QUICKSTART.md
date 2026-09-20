# Quick start

[Documentation](README.md) · [Snapshot API](SNAPSHOT_API.md) · [Data contract](DATA_CONTRACT.md)

## Install the MQL5 library

Use MT5's **File → Open Data Folder** to locate the terminal's data directory. Copy the repository's `Include/SMC/` folder into `MQL5/Include/SMC/`. Copy the required `.mq5` entry points into the matching `MQL5/Experts/`, `MQL5/Indicators/`, or `MQL5/Scripts/` directory, then compile them in MetaEditor.

| Entry point | Use |
| --- | --- |
| `Experts/SMC_Snapshot_Export.mq5` | Export ICT snapshots without placing orders |
| `Indicators/SMC_Visualizer.mq5` | Draw the original SMC modules on a chart |
| `Scripts/SMC_DataExport.mq5` | Export historical OHLCV CSV for Python |
| `Experts/SMC_Sample_EA.mq5` | Existing sample with order-placement logic |

For the first data integration, attach `SMC_Snapshot_Export` to the desired symbol and timeframe. The terminal needs chart history plus D1, W1, and M1 history for calendar concepts. SMT additionally needs the comparison symbol's history. The default primary evaluation covers 500 closed candles and requests dependency warmup history. Allow MT5 to synchronize history and inspect the per-module status when data is unavailable.

## Consume the snapshot

The export EA writes UTF-8 JSON to MT5's common files directory, shared between terminal instances: `Terminal/Common/Files/`. Its inputs are `InpSymbol` (empty means chart symbol), `InpTimeframe` (`PERIOD_CURRENT` means chart timeframe), `InpFolder` (default `SMC_Export`), and `InpSMTSymbol` (empty disables SMT). Filenames include the sanitized symbol and timeframe, for example `SMC_Export/EURUSD_M15.json`. The full location starts at `TerminalInfoString(TERMINAL_COMMONDATA_PATH)` followed by `Files/`. Use distinct `InpFolder` values for instances exporting the same symbol/timeframe with different settings.

The writer completes a temporary file before replacing the destination. Open the destination for each read so that a long-lived file handle does not retain the previous document. The envelope includes symbol, timeframe, closing `as_of` timestamp, broker time basis, configuration, module statuses, and detection records.

Use a sample's own instructions to install its dependencies and run it:

[Python](../examples/python/README.md) · [TypeScript](../examples/typescript/README.md) · [C#](../examples/csharp/README.md) · [Go](../examples/go/README.md) · [Java](../examples/java/README.md) · [Rust](../examples/rust/README.md)

Start with [the shared fixture](../tests/fixtures/snapshot-v1.json), then substitute the exported file path. Each CLI supports `--concept IFVG --direction bearish`; omit the filters to print all records. The fixture is synthetic contract data, not a live trading signal.

`READY` means every enabled module evaluated successfully. `PARTIAL`, `NOT_READY`, and `ERROR` require checking module details. An empty record list only means “no detections” when the corresponding module is ready. SMT is intentionally disabled until a comparison symbol is configured. See [status handling](SNAPSHOT_API.md#readiness-and-failure-handling).

## Configure detection

Use `SmcConfig.SetDefaults()` before overriding individual fields. The new manager overload uses broker time and closed candles. For example:

```cpp
SmcConfig config;
config.SetDefaults();
config.lookbackBars = 500;
config.smtSymbol = "GBPUSD"; // Use the exact broker symbol, including any suffix.
config.sessions[0].startMinute = 0;
config.sessions[0].endMinute = 8 * 60;

string reason;
if(!config.Validate(reason))
   Print("Invalid configuration: ", reason);
```

Supplying `smtSymbol` enables SMT. Choose a comparison instrument appropriate for the positive-correlation detector; the library does not select one automatically. Session hours are broker-local, not fixed London or New York civil-time conversions. See [detection rules](ICT_RULES.md) for all defaults and [the snapshot API](SNAPSHOT_API.md) for a complete EA example.

## Python data and training

The JSON reader has its own setup instructions and does not require the ML training stack. For existing CSV-based workflows, install only the dependencies you need from the repository root:

```sh
# Portable CSV loading and feature preparation.
python -m pip install -r Python/requirements-data.txt

# Model training and ONNX export.
python -m pip install -r Python/requirements-ml.txt

# Optional direct terminal connection on Windows.
python -m pip install -r Python/requirements-mt5.txt
```

`Python/requirements.txt` remains the compatibility install for existing training entry points. The Python loader accepts the existing exported column names, normalizes timestamps and volume fields, and validates OHLCV input. CSV files use chronological order; provide an exported CSV when working without a Windows terminal connection.

Training entry points can be run from the repository root or `Python/`. Their generated models are resolved under `Files/models/` and must not be committed. The retained [Japanese Python guide](PYTHON_ML.md) describes the model families. For repository checks, use [development dependencies and local validation](DEVELOPMENT.md) rather than installing every ML dependency.
