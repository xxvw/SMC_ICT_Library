import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

type JsonObject = Record<string, unknown>;
export type Direction = "bullish" | "bearish" | "neutral";
export interface SnapshotRecord extends JsonObject {
  id: string;
  concept: string;
  direction: Direction;
  state: string;
  lower: number;
  upper: number;
}
export interface Snapshot extends JsonObject {
  status: string;
  symbol: string;
  timeframe: string;
  as_of: string | null;
  records: SnapshotRecord[];
}
export interface Filters {
  concept?: string;
  direction?: Direction;
}

function invalid(path: string, expectation: string): never {
  throw new Error(`${path}: expected ${expectation}`);
}
function object(value: unknown, path: string): JsonObject {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return invalid(path, "an object");
  }
  return value as JsonObject;
}
function nonempty(value: unknown, path: string): string {
  if (typeof value !== "string" || value.length === 0) {
    return invalid(path, "a nonempty string");
  }
  return value;
}
function enumeration(value: unknown, path: string, values: readonly string[]): string {
  if (typeof value !== "string" || !values.includes(value)) {
    return invalid(path, values.join(" | "));
  }
  return value;
}
function finite(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return invalid(path, "a finite number");
  }
  return value;
}
function boolean(value: unknown, path: string): void {
  if (typeof value !== "boolean") invalid(path, "a boolean");
}
function string(value: unknown, path: string): void {
  if (typeof value !== "string") invalid(path, "a string");
}
function integer(value: unknown, path: string, minimum: number, maximum = Infinity): void {
  const number = finite(value, path);
  if (!Number.isInteger(number) || number < minimum || number > maximum) {
    invalid(path, `an integer between ${minimum} and ${maximum}`);
  }
}
function array(value: unknown, path: string): unknown[] {
  if (!Array.isArray(value)) return invalid(path, "an array");
  return value;
}

/** Broker wall-clock values carry no UTC suffix or inferred timezone. */
function timestamp(value: unknown, path: string, nullable = false): void {
  if (nullable && value === null) return;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/.test(value)) {
    invalid(path, `a broker timestamp YYYY-MM-DDTHH:mm:ss${nullable ? " or null" : ""}`);
  }
  const [year, month, day, hour, minute, second] = (value as string).split(/[-T:]/).map(Number);
  const leapYear = year! % 4 === 0 && (year! % 100 !== 0 || year! % 400 === 0);
  const days = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month! - 1] ?? 0;
  if (year! < 1 || month! < 1 || month! > 12 || day! < 1 || day! > days ||
      hour! > 23 || minute! > 59 || second! > 59) {
    invalid(path, "a valid broker calendar date and time");
  }
}

const statuses = ["READY", "PARTIAL", "NOT_READY", "ERROR", "DISABLED"] as const;
const directions = ["bullish", "bearish", "neutral"] as const;
const concepts = [
  "SWING_HIGH", "SWING_LOW", "BOS", "CHOCH", "ORDER_BLOCK", "FVG", "LIQUIDITY",
  "PREMIUM_DISCOUNT", "OTE", "KILL_ZONE", "BREAKER", "DISPLACEMENT", "MSS", "IFVG",
  "BPR", "PREVIOUS_DAY_HIGH", "PREVIOUS_DAY_LOW", "PREVIOUS_WEEK_HIGH", "PREVIOUS_WEEK_LOW",
  "SESSION_HIGH", "SESSION_LOW", "DAILY_GAP", "WEEKLY_GAP", "SMT", "PO3",
] as const;

function validateConfig(input: unknown): void {
  const config = object(input, "config");
  const limits: Record<string, number> = {
    lookback_bars: 100000, max_records_per_concept: 100000, swing_strength: 5000,
    displacement_baseline: 5000, max_zone_age: 10000, bpr_max_separation: 10000, po3_expiry_bars: 10000,
  };
  for (const [field, maximum] of Object.entries(limits)) {
    integer(config[field], `config.${field}`, 1, maximum);
  }
  integer(config.smt_radius, "config.smt_radius", 0, 5000);
  for (const field of ["displacement_multiplier", "displacement_body_fraction"]) {
    if (finite(config[field], `config.${field}`) <= 0) invalid(`config.${field}`, "a number greater than 0");
  }
  if ((config.displacement_body_fraction as number) > 1) invalid("config.displacement_body_fraction", "a number <= 1");
  if (finite(config.min_fvg_pips, "config.min_fvg_pips") < 0) invalid("config.min_fvg_pips", "a number >= 0");
  string(config.smt_symbol, "config.smt_symbol");
  for (const field of ["enable_draw", "enable_calendar", "enable_smt", "enable_po3",
    "enable_displacement", "enable_mss", "enable_ifvg", "enable_bpr", "enable_cs", "enable_vix"]) {
    boolean(config[field], `config.${field}`);
  }
  if (config.enable_smt === true) nonempty(config.smt_symbol, "config.smt_symbol");
  const sessions = array(config.sessions, "config.sessions");
  if (sessions.length !== 3) invalid("config.sessions", "exactly three sessions");
  sessions.forEach((entry, index) => {
    const path = `config.sessions[${index}]`;
    const session = object(entry, path);
    nonempty(session.name, `${path}.name`);
    integer(session.start_minute, `${path}.start_minute`, 0, 1439);
    integer(session.end_minute, `${path}.end_minute`, 0, 1439);
  });
}

export function validateSnapshot(input: unknown): Snapshot {
  const value = object(input, "snapshot");
  if (typeof value.schema_version !== "string" || !/^1\.\d+$/.test(value.schema_version)) {
    invalid("schema_version", "a supported 1.x version string");
  }
  for (const field of ["library_version", "symbol", "timeframe"]) nonempty(value[field], field);
  enumeration(value.time_basis, "time_basis", ["broker"]);
  enumeration(value.status, "status", statuses);
  if (Object.hasOwn(value, "message")) string(value.message, "message");
  timestamp(value.as_of, "as_of", true);
  validateConfig(value.config);
  array(value.modules, "modules").forEach((entry, index) => {
    const path = `modules[${index}]`;
    const module = object(entry, path);
    enumeration(module.concept, `${path}.concept`, concepts);
    enumeration(module.status, `${path}.status`, statuses);
    timestamp(module.as_of, `${path}.as_of`, true);
    boolean(module.truncated, `${path}.truncated`);
    string(module.message, `${path}.message`);
  });
  const ids = new Set<string>();
  array(value.records, "records").forEach((entry, index) => {
    const path = `records[${index}]`;
    const record = object(entry, path);
    for (const field of ["id", "state"]) nonempty(record[field], `${path}.${field}`);
    const id = record.id as string;
    if (ids.has(id)) invalid(`${path}.id`, "a unique record id");
    ids.add(id);
    enumeration(record.concept, `${path}.concept`, concepts);
    for (const field of ["source_time", "confirmed_at", "updated_at"]) timestamp(record[field], `${path}.${field}`);
    for (const field of ["period_start", "period_end"]) timestamp(record[field], `${path}.${field}`, true);
    enumeration(record.direction, `${path}.direction`, directions);
    const lower = finite(record.lower, `${path}.lower`);
    const upper = finite(record.upper, `${path}.upper`);
    if (lower > upper) invalid(path, "lower <= upper");
    boolean(record.active, `${path}.active`);
    array(record.related_ids, `${path}.related_ids`).forEach((id, item) => nonempty(id, `${path}.related_ids[${item}]`));
    for (const field of ["reference_price", "comparison_price", "strength"]) {
      finite(record[field], `${path}.${field}`);
    }
    string(record.reason, `${path}.reason`);
  });
  return value as Snapshot;
}

export function renderSnapshot(snapshot: Snapshot, filters: Filters = {}): string {
  const lines = [
    `status=${snapshot.status} symbol=${snapshot.symbol} timeframe=${snapshot.timeframe} as_of=${snapshot.as_of ?? "null"} time_basis=broker`,
  ];
  const records = snapshot.records.filter((record) =>
    (filters.concept === undefined || record.concept === filters.concept) &&
    (filters.direction === undefined || record.direction === filters.direction),
  ).sort((left, right) => left.id < right.id ? -1 : left.id > right.id ? 1 : 0);
  for (const record of records) {
    lines.push([record.id, record.concept, record.direction, record.state,
      fixedPrice(record.lower), fixedPrice(record.upper)].join("\t"));
  }
  return lines.join("\n") + "\n";
}

function fixedPrice(value: number): string {
  // Round the exact binary64 value, avoiding an intermediate floating-point
  // multiplication or decimal conversion that could move a rounding boundary.
  const bytes = new DataView(new ArrayBuffer(8));
  bytes.setFloat64(0, value, false);
  const bits = bytes.getBigUint64(0, false);
  const negative = (bits >> 63n) !== 0n;
  const encodedExponent = Number((bits >> 52n) & 0x7ffn);
  if (encodedExponent === 0x7ff) invalid("price", "a finite number");
  const fraction = bits & ((1n << 52n) - 1n);
  const significand = encodedExponent === 0 ? fraction : fraction | (1n << 52n);
  const exponent = encodedExponent === 0 ? -1074 : encodedExponent - 1023 - 52;
  const scale = 100000000n;
  const numerator = significand * scale;
  let rounded: bigint;
  if (exponent >= 0) {
    rounded = numerator << BigInt(exponent);
  } else {
    const denominator = 1n << BigInt(-exponent);
    rounded = numerator / denominator;
    const twiceRemainder = (numerator % denominator) * 2n;
    if (twiceRemainder > denominator ||
        (twiceRemainder === denominator && (rounded & 1n) !== 0n)) {
      rounded += 1n;
    }
  }
  const sign = negative && rounded !== 0n ? "-" : "";
  return `${sign}${rounded / scale}.${(rounded % scale).toString().padStart(8, "0")}`;
}

const usage = "Usage: node dist/read_snapshot.js SNAPSHOT.json [--concept CONCEPT] [--direction bullish|bearish|neutral]";
export function parseArguments(args: string[]): { path: string; filters: Filters } {
  const filters: Filters = {};
  let path: string | undefined;
  for (let index = 0; index < args.length; index++) {
    const argument = args[index]!;
    if (argument === "--concept" || argument === "--direction") {
      const value = args[++index];
      if (value === undefined || value.startsWith("--")) throw new Error(`${argument} requires a value`);
      if (argument === "--concept") {
        if (filters.concept !== undefined) throw new Error("--concept may only be specified once");
        if (!/^[A-Z][A-Z0-9_]*$/.test(value)) throw new Error("--concept must be an uppercase concept name");
        filters.concept = value;
      } else {
        if (filters.direction !== undefined) throw new Error("--direction may only be specified once");
        filters.direction = enumeration(value, "--direction", directions) as Direction;
      }
    } else if (argument.startsWith("--")) {
      throw new Error(`Unknown option: ${argument}`);
    } else if (path === undefined) {
      path = argument;
    } else {
      throw new Error("Only one snapshot path is allowed");
    }
  }
  if (path === undefined) throw new Error(usage);
  return { path, filters };
}

function main(): void {
  if (process.argv.slice(2).includes("--help")) {
    process.stdout.write(usage + "\n");
    return;
  }
  try {
    const { path, filters } = parseArguments(process.argv.slice(2));
    const snapshot = validateSnapshot(JSON.parse(readFileSync(path, "utf8")) as unknown);
    process.stdout.write(renderSnapshot(snapshot, filters));
  } catch (error) {
    process.stderr.write(`Error: ${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  }
}

if (process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
