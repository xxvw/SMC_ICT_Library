# C# snapshot reader

Requires the .NET 10 SDK. This example uses only `System.Text.Json` and the
standard library. It reads snapshots produced by MT5; it does not connect to MT5,
place trades, or run detection logic.

From the repository root:

```sh
dotnet run --project examples/csharp -- tests/fixtures/snapshot-v1.json
dotnet run --project examples/csharp -- tests/fixtures/snapshot-v1.json --concept FVG --direction bullish
dotnet run --project examples/csharp/tests -- tests/fixtures/snapshot-v1.json
```

Replace the fixture path with the JSON file in MT5's common files directory to
read live exports. The first positional argument is required. `--concept` accepts
an uppercase concept name; `--direction` accepts `bullish`, `bearish`, or `neutral`.
Filtering happens only after the entire snapshot is validated.

Output begins with the snapshot status, symbol, timeframe, evaluation time, and
broker time basis. Subsequent lines contain tab-separated `id`, `concept`,
`direction`, `state`, `lower`, and `upper`, sorted by ID. Prices use eight decimal
places with a decimal point regardless of the current locale. A null evaluation
time is printed as `null`.

The reader accepts schema major version 1 and ignores unknown additive fields.
Missing or invalid required fields, unsupported versions, non-finite values,
invalid enum values, and reversed price bounds fail with a message on stderr and
a nonzero exit code. Broker timestamps have no UTC `Z` suffix and are not
converted to local time.
