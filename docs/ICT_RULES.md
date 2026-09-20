# Detection rules and defaults

[Documentation](README.md) · [Snapshot API](SNAPSHOT_API.md)

These are the library's reproducible numerical definitions of ICT-related concepts. ICT terminology is discretionary; these rules document this implementation rather than claiming a universal definition or a trading result. Settings are exposed through `SmcConfig`.

## Evaluation and time

- Evaluate only closed candles, in chronological order. The default output horizon is 500 candles; dependency warmup is requested separately using `SmcConfig.WarmupBars()`.
- Use broker-local time. `source_time` is a source candle's opening time; `confirmed_at` is when the confirming candle closes. JSON timestamps have neither a `Z` suffix nor an inferred UTC offset.
- Require a tradable tick for a price break. Tick size and pip size are separate: the default minimum FVG width is 2 pips.
- Confirm a strict swing with five candles on each side by default. Equal highs/lows do not establish a strict swing. A pivot cannot affect detection before the right-side confirmation closes.
- Keep stable event IDs independent of lifecycle updates. Repeating the same input and configuration does not append duplicate events. Result caps apply after detection, with truncation reported in module status.
- Report incomplete history or failed evaluation explicitly. Unavailable data does not mean that no pattern occurred.

## Additional concepts

| Concept | Detection rule | Main defaults |
| --- | --- | --- |
| Displacement | A nonzero candle body is at least the multiplier times the mean absolute body of the preceding baseline candles, and occupies at least the configured fraction of the candle's range. The candidate is excluded from the mean; a zero mean or range does not qualify. | Baseline 20, multiplier 1.5, body fraction 0.6 |
| MSS | Against an established trend, a directionally matching Displacement candle closes at least one tick through a previously confirmed swing. Emit once per target swing. Higher highs and higher lows establish bullish structure; lower highs and lower lows establish bearish structure. | Swing strength 5; Displacement settings above |
| IFVG | The first later close at least one tick through an FVG's opposite boundary creates a zone with the same prices and the opposite direction. A wick alone does not invert an FVG. | Source and derived-zone age limit 200 bars |
| BPR | Intersect opposite-direction original FVGs whose confirmation bars are no more than the configured separation apart. The overlap must be at least one tick. Direction follows the newer FVG; each pair creates one result. | Separation 50 bars, derived-zone age limit 200 bars |
| Previous-day/week highs and lows | Read the most recently completed broker D1/W1 periods. Do not substitute the forming period's extrema. | Calendar enabled |
| Session highs and lows | Aggregate covered M1 history for each completed broker-clock session. Return the latest completed range for each session, with its boundaries; the forming session is excluded. | Sessions below |
| Broker daily/weekly opening gaps | Compare the new broker period's open with the previous completed period's close and track filling. | Minimum gap 1 tick |
| SMT divergence | Compare successive confirmed primary-symbol swing extrema with extrema in the comparison symbol around the same timestamps. A primary extension of at least one tick without the positively correlated companion following produces divergence. No missing timestamp is interpolated. | Explicit comparison symbol; neighborhood radius 1 |
| Power of Three | A completed accumulation range is followed by a one-sided sweep and a close back inside, then a matching Displacement close through the opposite side. Preserve the stage transitions and reasons. | First configured session, manipulation window 20 bars |

BPR may reference original FVGs that have already been filled or broken: it represents their geometric overlap. Source links identify both FVGs. Broker opening gaps are deliberately named `DAILY_GAP` and `WEEKLY_GAP`; their period boundaries are not New York-based NDOG/NWOG definitions.

SMT is for positive-correlation comparisons in this version. No comparison instrument is chosen implicitly. A nonempty `smtSymbol` enables it; explicitly enabling SMT without a comparison symbol is invalid. Missing comparison data is a readiness problem, not a no-divergence result.

## Sessions and Power of Three

All session intervals include the start and exclude the end. The defaults are:

| Name | Broker-local time | Configuration minutes |
| --- | --- | --- |
| Asian | 00:00–08:00 | `[0, 480)` |
| London | 07:00–16:00 | `[420, 960)` |
| NewYork | 12:00–21:00 | `[720, 1260)` |

Names are labels, not automatic time-zone conversions. Set broker-local hours appropriate to your data. An end before the start denotes a session crossing midnight; equal start/end values are invalid. A synchronized history interval may include no-tick minutes, but an uncovered or empty session is not a completed usable range.

Power of Three uses `sessions[0]` for accumulation. A candle spanning the accumulation boundary cannot prove a later manipulation. A bar that sweeps both sides invalidates the sequence. After manipulation, a close through the manipulation side invalidates it; distribution requires a later Displacement body in the expected direction closing beyond the opposite range boundary. The opportunity expires after the 20-bar manipulation window or at the next accumulation-session start, whichever comes first. `ACCUMULATION`, `MANIPULATION`, `DISTRIBUTION`, `INVALIDATED`, and `EXPIRED` describe pattern stages; they are not the zone lifecycle below.

## Zone lifecycle

For OB/FVG and derived zones, evaluate lifecycle changes only on candles after formation:

| State | Condition |
| --- | --- |
| `FRESH` | Formed without a subsequent touch |
| `TESTED` | Subsequent candle range touches the zone |
| `MITIGATED` | Subsequent price reaches the zone midpoint |
| `BROKEN` | Subsequent close passes the opposite boundary by at least one tick |

A single candle can advance directly to the furthest applicable state. An expired zone becomes inactive while retaining its last lifecycle label and an expiry reason. Breaker detection can inspect broken order-block history; a historical broken zone is not a currently active order block. Liquidity replay counts each confirmed touch once rather than counting it again on every update.

## Boundaries of reproducibility

Given the same closed input history, configuration, and symbol price properties, detection is deterministic. Source and confirmation timestamps do not move when future candles are appended. Lifecycle state can legitimately advance; old records can leave the configured lookback or result cap. Historical broker data corrections, a different history window, or changed configuration can change results and should be recorded alongside saved snapshots.

The existing Japanese [concept guide](SMC_CONCEPTS.md) describes the original modules. Use this page and the [data contract](DATA_CONTRACT.md) for the snapshot rules and machine-readable fields.
