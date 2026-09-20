# SMC/ICT Library for MetaTrader 5

[English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Español](README.es.md)

An MIT-licensed MQL5 library for detecting and retrieving Smart Money Concepts (SMC) and Inner Circle Trader (ICT) patterns in MT5. Use typed snapshots inside an EA or read the same results as JSON from Python, TypeScript, C#, Go, Java, or Rust.

Detection uses closed candles and broker time. Numerical rules are explicit, configurable project definitions; see [detection rules](docs/ICT_RULES.md).

## What is included

| Area | Capabilities |
| --- | --- |
| Structure and zones | Confirmed swings, BOS, CHoCH, order blocks, FVG, breaker blocks, liquidity, premium/discount, OTE, and sessions |
| Additional ICT patterns | Displacement, MSS, IFVG, BPR, previous-day/week and completed-session highs/lows, broker daily/weekly opening gaps, SMT divergence, and Power of Three |
| Data access | `SmcConfig`, `SmcSnapshot`, per-concept readiness, stable record IDs, lifecycle states, UTF-8 JSON, and existing CSV export |
| Examples | A snapshot-export EA that places no orders; six external-language JSON readers; existing visualizer and sample trading EA |
| Optional analysis | Currency strength, historical-volatility analysis, Python training scripts, and ONNX utilities |

## Start in MT5

1. In MT5, choose **File → Open Data Folder**.
2. Copy `Include/SMC/` into `MQL5/Include/SMC/` and `Experts/SMC_Snapshot_Export.mq5` into `MQL5/Experts/`.
3. Compile the export EA in MetaEditor, attach it to a chart, and inspect its Experts log. It exports a new snapshot when a candle closes without placing trades.
4. Read the JSON file in MT5's shared `Terminal/Common/Files/` directory with one of the examples below.

For MQL5 integration, initialize a configuration and check both update success and snapshot status:

```cpp
#include <SMC/SmcManager.mqh>

CSmcManager smc;

int OnInit()
{
   SmcConfig config;
   config.SetDefaults();
   return smc.Init(_Symbol, _Period, config) ? INIT_SUCCEEDED : INIT_FAILED;
}

void OnTick()
{
   if(!smc.Update())
      return; // Read GetStatus()/GetSnapshot() for unavailable-module details.

   SmcSnapshot snapshot;
   if(!smc.GetSnapshot(snapshot) || snapshot.status != SMC_STATUS_READY)
      return;

   for(int i = 0; i < ArraySize(snapshot.records); i++)
      if(snapshot.records[i].concept == ICT_IFVG)
         Print(snapshot.records[i].id, " ", snapshot.records[i].state);
}

void OnDeinit(const int reason) { smc.Clean(); }
```

The existing `Init()`, `Update()`, `Clean()`, and getter interfaces remain available. See the [quick start](docs/QUICKSTART.md), [snapshot API](docs/SNAPSHOT_API.md), and [compatibility notes](docs/SNAPSHOT_API.md#compatibility).

## Read results in another language

Each example accepts a snapshot path and optional `--concept IFVG --direction bearish` filters. The readers share a fixture and expected output; detection stays in MQL5.

| Language | Setup and run instructions |
| --- | --- |
| Python | [examples/python](examples/python/README.md) |
| TypeScript | [examples/typescript](examples/typescript/README.md) |
| C# | [examples/csharp](examples/csharp/README.md) |
| Go | [examples/go](examples/go/README.md) |
| Java | [examples/java](examples/java/README.md) |
| Rust | [examples/rust](examples/rust/README.md) |

The [data contract](docs/DATA_CONTRACT.md) and [JSON Schema](schemas/snapshot.schema.json) define versioning, timestamps, statuses, and record fields. Broker timestamps have no UTC suffix. Missing history is reported separately from a successful evaluation with no matches.

## Documentation and development

- [Documentation index](docs/README.md), including retained Japanese reference guides.
- [Detection rules and defaults](docs/ICT_RULES.md).
- [Local validation and development](docs/DEVELOPMENT.md).
- [Contributing](CONTRIBUTING.md), [code of conduct](CODE_OF_CONDUCT.md), [security reporting](SECURITY.md), and [changes](CHANGELOG.md).

All changes go through small PRs to `main`, with local validation before squash merge. Commit one completed unit, validate it, and push it before starting another. CI runs locally; GitHub hosted and self-hosted runners are not required.

```sh
python -m pip install -r requirements-dev.txt
python tools/setup_hooks.py
python tools/check_all.py
```

Full validation also requires MetaEditor/MT5 and the sample-language toolchains; follow the [development guide](docs/DEVELOPMENT.md). Missing tools and interrupted checks fail validation.

Python CSV processing, terminal connectivity, and ML training have separate dependency sets. See [quick start: Python](docs/QUICKSTART.md#python-data-and-training).

## License

[MIT](LICENSE). The library and examples support research and software development. Pattern detections are data, and do not establish profitability. The existing `SMC_Sample_EA.mq5` can place orders; use `SMC_Snapshot_Export.mq5` for data-only integration.
