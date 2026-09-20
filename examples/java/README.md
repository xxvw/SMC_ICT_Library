# Java snapshot reader

Requires Java 21 or newer and Maven 3.9 or newer. This example uses Jackson to
read the versioned JSON produced by the MQL5 library and networknt to validate
the canonical schema bundled into the JAR. It does not reproduce the ICT
detection rules or place trades.

From this directory:

```sh
mvn verify
java -jar target/snapshot-reader-1.0.0.jar ../../tests/fixtures/snapshot-v1.json
java -jar target/snapshot-reader-1.0.0.jar ../../tests/fixtures/snapshot-v1.json --concept FVG --direction bullish
```

Pass the path to the live JSON in your MT5 common files directory in place of
the fixture. Paths containing spaces must be quoted. Filters are optional,
case-sensitive, and combined with AND. The entire document is validated before
filters are applied, so an invalid excluded record still causes an error.

The first output line reports `status`, `symbol`, `timeframe`, `as_of` and
`time_basis`. Following lines are sorted by record ID and contain tab-separated
`id`, `concept`, `direction`, `state`, `lower`, and `upper`; prices always have
eight decimal places. Each price is read as an IEEE 754 binary64 value and its
exact binary value is rounded to eight decimal places using nearest rounding
with ties to even. Negative zero, including negative values that round to zero,
is displayed as `0.00000000`. Broker timestamps remain unconverted: they do not imply
UTC or the computer's local timezone. An unavailable `as_of` prints as `null`.

Only schema major version 1 is accepted. Required fields, nested objects,
types, enum values, timestamps, numeric limits, and price ordering are checked.
The optional top-level `message` must be a string when present.
Additional fields are accepted for forward compatibility. Malformed JSON,
invalid data, missing files, or incorrect arguments produce a diagnostic on
stderr and exit code 2; no partial summary is printed. Valid snapshots return
exit code 0 even when the reported data status is not `READY`.

The executable JAR includes its pinned runtime dependencies. Tests exercise the
shared contract fixture, filter output, invalid records, and CLI failures:

```sh
mvn test
```

Maven reads the schema and fixtures from the repository by default. For an
isolated worktree, override their locations with `-Dschema.directory=/path/to/schemas`
and `-Dfixture.directory=/path/to/tests/fixtures`; do not maintain separate copies.

See the repository's [snapshot schema](../../schemas/snapshot.schema.json) for
the data contract.
