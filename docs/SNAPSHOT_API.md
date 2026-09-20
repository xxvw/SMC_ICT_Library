# MQL5 snapshot API

[Documentation](README.md) · [Detection rules](ICT_RULES.md) · [JSON contract](DATA_CONTRACT.md)

## Public interface

Include `<SMC/SmcManager.mqh>`. The manager exposes the following interface in addition to its existing initialization overload and getters:

```cpp
bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
          const SmcConfig &config);
bool Update();
bool GetSnapshot(SmcSnapshot &snapshot) const;
ENUM_SMC_STATUS GetStatus() const;
void Clean();
```

`SmcConfig`, `SmcSnapshot`, `SmcRecord`, and `SmcModuleStatus` are defined in `Include/SMC/Core/SmcSnapshot.mqh`. Initialize configuration with `SetDefaults()` and optionally call `Validate(reason)` before `Init()`. Invalid configuration makes initialization fail; the reason is suitable for a diagnostic log.

`GetSnapshot()` copies the current snapshot into the supplied variable. Its boolean reports whether an update has produced a snapshot, including an unavailable or failed snapshot. It does **not** assert that the snapshot is ready. `Update()` returns `true` only when the resulting status is `SMC_STATUS_READY`.

## Minimal data-only EA

```cpp
#include <SMC/SmcManager.mqh>

CSmcManager smc;

int OnInit()
{
   SmcConfig config;
   config.SetDefaults();
   if(!smc.Init(_Symbol, _Period, config))
   {
      Print("SMC initialization failed: ", SmcStatusName(smc.GetStatus()));
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

void OnTick()
{
   bool ready = smc.Update();
   SmcSnapshot snapshot;
   if(!smc.GetSnapshot(snapshot))
      return;

   if(!ready)
   {
      for(int i = 0; i < ArraySize(snapshot.modules); i++)
         if(snapshot.modules[i].status != SMC_STATUS_READY &&
            snapshot.modules[i].status != SMC_STATUS_DISABLED)
            Print(SmcConceptName(snapshot.modules[i].concept), ": ",
                  SmcStatusName(snapshot.modules[i].status), " ",
                  snapshot.modules[i].message);
      return;
   }

   for(int i = 0; i < ArraySize(snapshot.records); i++)
   {
      SmcRecord record = snapshot.records[i];
      if(record.concept != ICT_IFVG || !record.active)
         continue;
      Print(record.id, " ", SmcDirectionName(record.direction), " ",
            record.state, " ", record.lower, "..", record.upper);
   }
}

void OnDeinit(const int reason) { smc.Clean(); }
```

This example places no orders. The manager handles evaluation caching; a consumer that emits notifications should also deduplicate using record IDs and lifecycle timestamps. `Clean()` removes drawing objects; object destruction releases owned resources. Do not treat calling `Clean()` as a successful new evaluation.

## Readiness and failure handling

| Status | Meaning for a consumer |
| --- | --- |
| `SMC_STATUS_READY` | All enabled concepts evaluated; zero records is a valid result. |
| `SMC_STATUS_PARTIAL` | Inspect per-concept statuses; some requested data is unavailable. |
| `SMC_STATUS_NOT_READY` | Required history or comparison data is not ready. |
| `SMC_STATUS_ERROR` | Evaluation failed; do not reuse a prior success as current data. |
| `SMC_STATUS_DISABLED` | Module-level marker for an intentionally disabled concept. |

A status belongs to its `asOf` evaluation time. `SmcModuleStatus` also includes a message and `truncated`; truncation means the configured output cap removed older records after calculation. Default `maxRecordsPerConcept` is 100. The envelope's status and each enabled module's status must be considered before using results. Legacy signal getters return a waiting state after an unsuccessful update.

For diagnostics, retrieve the snapshot even when `Update()` returns `false`. A caller may choose to consume a ready concept from a partial snapshot, but must explicitly verify that concept's status and timestamp. The minimal example above requires the complete snapshot to be ready.

## Configuration and records

The default `lookbackBars` is 500. `WarmupBars()` computes the additional dependency horizon from the configured dependency windows, so visible output is bounded independently of the history needed to derive it. Set configuration before initialization. Displacement, MSS, IFVG, BPR, calendar concepts, and Power of Three are enabled by default; drawing, currency strength, volatility analysis, and SMT are optional.

SMT becomes enabled when `smtSymbol` is nonempty. Setting `enableSMT = true` without a symbol is invalid. `sessions[0]` is the accumulation session used by Power of Three. Session minutes are measured from broker midnight; an end before the start crosses midnight, while equal boundaries are invalid.

`SmcSnapshot.records[]` contains typed `SmcRecord` values with an `ENUM_SMC_CONCEPT`. Each record provides:

- Stable `id`, `concept`, and `direction` (`1` bullish, `-1` bearish, `0` neutral).
- `sourceTime`, `confirmedAt`, and `updatedAt`, all in broker time.
- `lower` and `upper` prices, lifecycle `state`, and a separate `active` flag.
- Source links in `relatedId` and `secondaryId`, plus concept-specific measurements and a reason.

A source link can refer to a record outside the visible window or output cap. An expired zone keeps its lifecycle label and becomes inactive; expiration and a price break are different events. The [data contract](DATA_CONTRACT.md) defines how these fields map to JSON, including `related_ids`, version strings, and broker-local timestamp formatting.

## JSON export

Include `<SMC/Utils/SnapshotExporter.mqh>` to use `CSmcSnapshotExporter`. `Serialize(snapshot, json)` returns a boolean and writes the JSON string to its output argument. `ToJSON(snapshot)` returns an empty string for an invalid snapshot. `Export(snapshot, filename)` returns success after writing under MT5's `FILE_COMMON` directory. Use the supplied [export EA](../Experts/SMC_Snapshot_Export.mq5) for a complete data-only integration. See the [data contract](DATA_CONTRACT.md) for schema validation and file semantics.

## Compatibility

Existing `Init()`, `Update()`, `Clean()`, module accessors, and getters remain callable, including standalone modules. The configuration overload is the recommended entry point for snapshots. The legacy GMT-offset API retains its earlier meaning; the new configuration API uses broker-clock sessions.

Source compatibility does not preserve the earlier lifecycle defects. Closed-candle confirmation, deterministic replay, correct zone progression, and idempotent liquidity touches can change the detections returned for an existing chart. Swing records become knowable only after their right-side confirmation window closes. Later bars may advance a zone's state or remove it from the configured output window; they do not move its original source or confirmation time.
