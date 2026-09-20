# Go snapshot reader

Requires Go 1.22 or newer. This sample uses only the Go standard library. It reads an existing MT5 JSON snapshot; it does not place trades or repeat the detection logic.

From this directory:

```sh
go run . ../../tests/fixtures/snapshot-v1.json
go run . ../../tests/fixtures/snapshot-v1.json --concept FVG --direction bullish
go test ./...
```

Pass the path to your exported snapshot in place of the fixture. Both filters are optional, case-sensitive, and combined when supplied. Concept names use uppercase (`FVG`, `MSS`, `PO3`); directions are `bullish`, `bearish`, or `neutral`. Results sort by ID. The first line describes the snapshot, followed by tab-separated `id`, `concept`, `direction`, `state`, `lower`, and `upper` values. Prices round the exact IEEE 754 binary64 value to eight decimal places using nearest, ties-to-even rounding, never exponent notation; rounded negative zero becomes `0.00000000`. Timestamps represent broker wall-clock time and are not converted to UTC.

The reader validates every required header, configuration, module, and record field against the version 1 contract, rejects invalid timestamps, nonfinite numbers, duplicate IDs, and reversed price bounds, and permits unknown additive fields. Version `1.<minor>` is supported; another major version fails with a nonzero exit code. `PARTIAL`, `NOT_READY`, `ERROR`, and `DISABLED` remain visible in the output rather than being treated as successful detections.
