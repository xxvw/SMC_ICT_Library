# TypeScript snapshot reader

Read the JSON exported by MT5, validate the version 1 contract, and display records. This example uses Node.js only at runtime; it does not place orders or reproduce ICT detection logic.

Requirements: Node.js 22 or later and npm.

Run from this directory:

```sh
npm ci
npm run build
node dist/read_snapshot.js ../../tests/fixtures/snapshot-v1.json
node dist/read_snapshot.js ../../tests/fixtures/snapshot-v1.json --concept FVG --direction bullish
npm test
```

Use the path of your exported JSON in the MT5 common files directory in place of the fixture. Filters are optional and combined. Concept names are uppercase; directions are `bullish`, `bearish`, or `neutral`.

The first line shows snapshot status, symbol, timeframe, evaluation time, and the broker time basis. Following lines are sorted by record ID and contain tab-separated ID, concept, direction, state, lower price, and upper price. Prices have eight decimal places. A valid snapshot with no matching records prints only the header. `NOT_READY`, `PARTIAL`, and `ERROR` remain visible in the header; no readiness is inferred from an empty record list.

The reader accepts additive properties and `1.x` schema versions. It rejects missing required fields, unsupported enums, invalid calendar timestamps, nonfinite numbers, reversed price bounds, and duplicate record IDs. Broker timestamps are displayed unchanged and never interpreted as UTC. Validation and file errors go to stderr and produce exit code 1 without partial stdout.

See the [JSON Schema](../../schemas/snapshot.schema.json) for the full contract. The tests use the shared fixture; set `SNAPSHOT_FIXTURE` to use a fixture in another checkout.
