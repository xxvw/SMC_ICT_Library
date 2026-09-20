import assert from "node:assert/strict";
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { parseArguments, renderSnapshot, validateSnapshot } from "../dist/read_snapshot.js";

const fixturePath = process.env.SNAPSHOT_FIXTURE ?? fileURLToPath(new URL("../../../tests/fixtures/snapshot-v1.json", import.meta.url));
const fixture = JSON.parse(readFileSync(fixturePath, "utf8"));
const expected = readFileSync(fixturePath.replace(/\.json$/, ".expected.txt"), "utf8");
const cli = fileURLToPath(new URL("../dist/read_snapshot.js", import.meta.url));

function changed(mutation) {
  const value = structuredClone(fixture);
  mutation(value);
  return value;
}

test("shared fixture validates and output filters and sorts without mutation", () => {
  const value = validateSnapshot(structuredClone(fixture));
  const original = value.records.map(record => record.id);
  const output = renderSnapshot(value);
  assert.equal(output, expected);
  assert.match(output, /^status=\S+ symbol=\S+ timeframe=\S+ as_of=\S+ time_basis=broker\n/);
  const lines = output.trimEnd().split("\n").slice(1);
  assert.deepEqual(lines.map(line => line.split("\t")[0]), [...original].sort());
  for (const line of lines) {
    const columns = line.split("\t");
    assert.equal(columns.length, 6);
    assert.match(columns[4], /^-?\d+\.\d{8}$/);
    assert.match(columns[5], /^-?\d+\.\d{8}$/);
  }
  assert.deepEqual(value.records.map(record => record.id), original);
  const selected = value.records[0];
  const filtered = renderSnapshot(value, { concept: selected.concept, direction: selected.direction }).trimEnd().split("\n").slice(1);
  assert.equal(filtered.length, value.records.filter(record => record.concept === selected.concept && record.direction === selected.direction).length);
  assert.ok(filtered.every(line => line.split("\t")[1] === selected.concept && line.split("\t")[2] === selected.direction));
});

test("all required fields are validated while additive fields remain compatible", () => {
  for (const key of Object.keys(fixture)) {
    assert.throws(() => validateSnapshot(changed(value => { delete value[key]; })), undefined, `missing ${key}`);
  }
  for (const key of Object.keys(fixture.config)) {
    assert.throws(() => validateSnapshot(changed(value => { delete value.config[key]; })), undefined, `missing config.${key}`);
  }
  for (const key of Object.keys(fixture.modules[0])) {
    assert.throws(() => validateSnapshot(changed(value => { delete value.modules[0][key]; })), undefined, `missing module.${key}`);
  }
  for (const key of Object.keys(fixture.records[0])) {
    assert.throws(() => validateSnapshot(changed(value => { delete value.records[0][key]; })), undefined, `missing record.${key}`);
  }
  assert.doesNotThrow(() => validateSnapshot(changed(value => {
    value.schema_version = "1.12";
    value.extension = { future: true };
    value.config.extension = 1;
    value.records[0].extension = true;
  })));
});

test("invalid data cannot be rendered as an empty successful snapshot", () => {
  const mutations = [
    value => { value.schema_version = "2.0"; },
    value => { value.time_basis = "UTC"; },
    value => { value.status = "SUCCESS"; },
    value => { value.records[0].concept = "UNKNOWN"; },
    value => { value.records[0].direction = "long"; },
    value => { value.records[0].lower = "1.2"; },
    value => { value.records[0].upper = Infinity; },
    value => { value.records[0].reference_price = null; },
    value => { value.records[0].lower = value.records[0].upper + 1; },
    value => { value.records[0].source_time = "2026-02-29T00:00:00"; },
    value => { value.records[0].confirmed_at += "Z"; },
    value => { value.records[0].active = 1; },
    value => { value.records[0].related_ids = [null]; },
    value => { value.records.push({ ...value.records[0] }); },
    value => { value.modules[0].status = "SUCCESS"; },
    value => { value.config.lookback_bars = 1.5; },
    value => { value.config.lookback_bars = 100001; },
    value => { value.config.swing_strength = 5001; },
    value => { value.config.max_zone_age = 10001; },
    value => { value.config.displacement_body_fraction = 0; },
    value => { value.config.displacement_body_fraction = 1.1; },
    value => { value.config.smt_radius = -1; },
    value => { value.config.smt_radius = 5001; },
    value => { value.config.enable_smt = "false"; },
    value => { value.config.enable_smt = true; value.config.smt_symbol = ""; },
    value => { value.config.sessions[0].start_minute = 1440; },
    value => { value.config.sessions.pop(); },
  ];
  for (const mutation of mutations) assert.throws(() => validateSnapshot(changed(mutation)));
  assert.doesNotThrow(() => validateSnapshot(changed(value => {
    value.as_of = null;
    value.modules[0].as_of = null;
    value.records[0].source_time = "2024-02-29T23:59:59";
    value.records[0].period_start = null;
    value.records[0].period_end = null;
    value.status = "NOT_READY";
  })));
});

test("CLI uses deterministic stdout and fails before writing stdout for invalid input", () => {
  const valid = spawnSync(process.execPath, [cli, fixturePath], { encoding: "utf8" });
  assert.equal(valid.status, 0, valid.stderr);
  assert.equal(valid.stdout, renderSnapshot(validateSnapshot(fixture)));
  const temporary = mkdtempSync(join(tmpdir(), "smc-typescript-"));
  try {
    const path = join(temporary, "invalid.json");
    writeFileSync(path, JSON.stringify(changed(value => { value.records[0].lower = "invalid"; })));
    const invalid = spawnSync(process.execPath, [cli, path], { encoding: "utf8" });
    assert.equal(invalid.status, 1);
    assert.equal(invalid.stdout, "");
    assert.match(invalid.stderr, /records\[0\]\.lower/);
    writeFileSync(path, "{");
    assert.equal(spawnSync(process.execPath, [cli, path], { encoding: "utf8" }).status, 1);
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
});

test("CLI argument validation catches typos and missing values", () => {
  assert.deepEqual(parseArguments(["sample.json", "--concept", "FVG", "--direction", "bullish"]), {
    path: "sample.json", filters: { concept: "FVG", direction: "bullish" },
  });
  for (const args of [[], ["sample.json", "extra.json"], ["sample.json", "--concept"],
    ["sample.json", "--concept", "fvg"], ["sample.json", "--direction", "long"],
    ["sample.json", "--unknown"], ["sample.json", "--direction", "bullish", "--direction", "bearish"]]) {
    assert.throws(() => parseArguments(args));
  }
});
