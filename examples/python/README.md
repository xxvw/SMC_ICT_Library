# Python snapshot reader

Requires Python 3.10 or newer. No third-party packages, MetaTrader connection,
or trading permissions are needed. Detection stays in the MQL5 library; this
sample validates and reads its exported UTF-8 JSON snapshot.

From the repository root:

```sh
python3 examples/python/read_snapshot.py tests/fixtures/snapshot-v1.json
python3 examples/python/read_snapshot.py tests/fixtures/snapshot-v1.json --concept IFVG --direction bearish
python3 -m unittest discover -s examples/python -p 'test_*.py'
```

For a live export, replace the fixture path with the snapshot JSON path in MT5's
common files directory. Paths containing spaces must be quoted. Re-run after a
new closed candle has been exported; the reader never opens orders or modifies
the input file.

The reader accepts schema versions `1.<minor>` and unknown additive fields. It
rejects missing or invalid required fields, unsupported versions, nonfinite
prices, reversed bounds, and invalid broker timestamps. Errors go to stderr and
return a nonzero exit code. `PARTIAL`, `NOT_READY`, `ERROR`, and `DISABLED` are
valid data states and remain visible in the header; they are not converted to
successful detection results.

Output begins with snapshot status, symbol, timeframe, broker time, and time
basis. Subsequent lines are sorted by ID and contain tab-separated ID, concept,
direction, state, lower price, and upper price. Prices use eight decimal places,
rounding the exact IEEE 754 binary64 value to nearest with ties to even. Values
that round to zero are always printed as `0.00000000`, without a negative sign.
Filters are optional and case sensitive. Broker timestamps have no UTC suffix
and must not be interpreted as UTC without the broker's timezone information.

The shared [JSON Schema](../../schemas/snapshot.schema.json) defines the data
contract. The shared [fixture](../../tests/fixtures/snapshot-v1.json) is also used
by the other language samples.
