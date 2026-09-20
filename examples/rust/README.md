# Rust snapshot reader

A read-only client for the MT5 library's version 1 JSON snapshot. Detection stays in MQL5; this client never sends orders or connects to a broker.

Requires Rust 1.82 or newer with Cargo. From the repository root:

```sh
cargo run --quiet --locked --manifest-path examples/rust/Cargo.toml -- tests/fixtures/snapshot-v1.json
cargo run --quiet --locked --manifest-path examples/rust/Cargo.toml -- tests/fixtures/snapshot-v1.json --concept FVG --direction bullish
```

Replace the path with the snapshot in MT5's common files directory. Paths with spaces must be quoted. `--concept` accepts an uppercase name matching `[A-Z][A-Z0-9_]*` (an unknown name produces only the header); record concepts follow [the JSON Schema](../../schemas/snapshot.schema.json). `--direction` accepts `bullish`, `bearish`, or `neutral`. Both filters are optional and are combined when provided. Records are sorted by ID.

The first output line contains status, symbol, timeframe, the evaluation time (or `null`), and `time_basis=broker`. Each following tab-separated line contains ID, concept, direction, state, lower price, and upper price; prices have eight decimal places. JSON prices are parsed as IEEE 754 binary64 and the exact binary64 value is rounded to the nearest decimal value, with ties to even. Any rendered negative zero is normalized to `0.00000000`. Broker wall-clock timestamps are preserved without timezone conversion.

The complete input is validated before filtering: required fields and types, version 1, enumerations, timestamps, configuration limits, finite numbers, ordered price bounds, and unique record IDs. An optional top-level `message`, when present, must be a string. Unknown object fields are accepted for additive extensions. Invalid input, unreadable files, or invalid CLI arguments produce an error on standard error and a nonzero exit code. Non-ready snapshots are still displayed with their status; an empty result is not a readiness signal.

Run the local tests and compare the shared fixture:

```sh
cargo test --locked --manifest-path examples/rust/Cargo.toml
cargo run --quiet --locked --manifest-path examples/rust/Cargo.toml -- tests/fixtures/snapshot-v1.json > /tmp/smc-rust-output.txt
diff -u tests/fixtures/snapshot-v1.expected.txt /tmp/smc-rust-output.txt
```

`Cargo.lock` is committed so the example uses reproducible dependency versions.
