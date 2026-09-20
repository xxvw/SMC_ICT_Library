#!/usr/bin/env python3
"""Validate and print an SMC snapshot using only the Python standard library."""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

STATUSES = {"READY", "PARTIAL", "NOT_READY", "ERROR", "DISABLED"}
DIRECTIONS = {"bullish", "bearish", "neutral"}
TIMESTAMP = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\Z")
CONCEPT = re.compile(r"[A-Z][A-Z0-9_]*\Z")
CONCEPTS = {
    "SWING_HIGH", "SWING_LOW", "BOS", "CHOCH", "ORDER_BLOCK", "FVG", "LIQUIDITY",
    "PREMIUM_DISCOUNT", "OTE", "KILL_ZONE", "BREAKER", "DISPLACEMENT", "MSS", "IFVG",
    "BPR", "PREVIOUS_DAY_HIGH", "PREVIOUS_DAY_LOW", "PREVIOUS_WEEK_HIGH",
    "PREVIOUS_WEEK_LOW", "SESSION_HIGH", "SESSION_LOW", "DAILY_GAP", "WEEKLY_GAP",
    "SMT", "PO3",
}
POSITIVE_INTEGERS = (
    "lookback_bars", "max_records_per_concept", "swing_strength", "displacement_baseline",
    "max_zone_age", "bpr_max_separation", "po3_expiry_bars",
)
INTEGER_MAXIMA = (100000, 100000, 5000, 5000, 10000, 10000, 10000)
FLAGS = (
    "enable_draw", "enable_calendar", "enable_smt", "enable_po3", "enable_displacement",
    "enable_mss", "enable_ifvg", "enable_bpr", "enable_cs", "enable_vix",
)


class SnapshotError(ValueError):
    """The file does not implement the supported snapshot contract."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SnapshotError(message)


def object_value(value: Any, path: str) -> dict[str, Any]:
    require(isinstance(value, dict), f"{path} must be an object")
    return value


def fields(value: Any, names: tuple[str, ...], path: str) -> dict[str, Any]:
    obj = object_value(value, path)
    for name in names:
        require(name in obj, f"{path}.{name} is required")
    return obj


def string(value: Any, path: str, *, nonempty: bool = True) -> None:
    require(isinstance(value, str), f"{path} must be a string")
    require(not nonempty or len(value) > 0, f"{path} must not be empty")


def number(value: Any, path: str, *, nullable: bool = False) -> None:
    if nullable and value is None:
        return
    require(type(value) in (int, float), f"{path} must be a number")
    try:
        finite = math.isfinite(value)
    except OverflowError:
        finite = False
    require(finite, f"{path} must be finite")


def timestamp(value: Any, path: str, *, nullable: bool = False) -> None:
    if nullable and value is None:
        return
    string(value, path)
    require(TIMESTAMP.fullmatch(value) is not None,
            f"{path} must be a broker timestamp YYYY-MM-DDTHH:mm:ss without a timezone")
    try:
        datetime.fromisoformat(value)
    except ValueError as exc:
        raise SnapshotError(f"{path} is not a valid date/time") from exc


def enum(value: Any, allowed: set[str], path: str) -> None:
    string(value, path)
    require(value in allowed, f"{path} must be one of {', '.join(sorted(allowed))}")


def integer(value: Any, path: str, minimum: int, maximum: int | None = None) -> None:
    number(value, path)
    require(value == int(value), f"{path} must be an integer")
    require(value >= minimum, f"{path} must be at least {minimum}")
    require(maximum is None or value <= maximum, f"{path} must not exceed {maximum}")


def validate_config(config: Any) -> None:
    fields(config, POSITIVE_INTEGERS + FLAGS + ("smt_radius", "smt_symbol", "sessions",
           "displacement_multiplier", "displacement_body_fraction", "min_fvg_pips"), "config")
    for name, maximum in zip(POSITIVE_INTEGERS, INTEGER_MAXIMA, strict=True):
        integer(config[name], f"config.{name}", 1, maximum)
    integer(config["smt_radius"], "config.smt_radius", 0, 5000)
    for name in FLAGS:
        require(type(config[name]) is bool, f"config.{name} must be boolean")
    for name in ("displacement_multiplier", "displacement_body_fraction", "min_fvg_pips"):
        number(config[name], f"config.{name}")
    require(config["displacement_multiplier"] > 0, "config.displacement_multiplier must be positive")
    require(0 < config["displacement_body_fraction"] <= 1,
            "config.displacement_body_fraction must be in (0, 1]")
    require(config["min_fvg_pips"] >= 0, "config.min_fvg_pips must be nonnegative")
    string(config["smt_symbol"], "config.smt_symbol", nonempty=False)
    require(not config["enable_smt"] or bool(config["smt_symbol"]),
            "config.smt_symbol must not be empty when SMT is enabled")
    require(isinstance(config["sessions"], list) and len(config["sessions"]) == 3,
            "config.sessions must be an array of three sessions")
    for index, session in enumerate(config["sessions"]):
        path = f"config.sessions[{index}]"
        fields(session, ("name", "start_minute", "end_minute"), path)
        string(session["name"], f"{path}.name")
        for name in ("start_minute", "end_minute"):
            integer(session[name], f"{path}.{name}", 0, 1439)


def reject_constant(value: str) -> None:
    raise SnapshotError(f"nonfinite JSON number {value} is not supported")


def load_snapshot(path: str | Path) -> dict[str, Any]:
    with Path(path).open(encoding="utf-8") as source:
        snapshot = json.load(source, parse_constant=reject_constant)
    validate_snapshot(snapshot)
    return snapshot


def validate_snapshot(snapshot: Any) -> None:
    fields(snapshot, ("schema_version", "library_version", "symbol", "timeframe",
                      "time_basis", "as_of", "status", "config", "modules", "records"),
           "snapshot")
    for name in ("schema_version", "library_version", "symbol", "timeframe"):
        string(snapshot[name], name)
    require(re.fullmatch(r"1\.[0-9]+", snapshot["schema_version"]) is not None,
            "schema_version must use supported major version 1 (1.<minor>)")
    require(snapshot["time_basis"] == "broker", "time_basis must be broker")
    timestamp(snapshot["as_of"], "as_of", nullable=True)
    enum(snapshot["status"], STATUSES, "status")
    if "message" in snapshot:
        string(snapshot["message"], "message", nonempty=False)
    validate_config(snapshot["config"])
    require(isinstance(snapshot["modules"], list), "modules must be an array")
    for index, module in enumerate(snapshot["modules"]):
        path = f"modules[{index}]"
        fields(module, ("concept", "status", "as_of", "truncated", "message"), path)
        enum(module["concept"], CONCEPTS, f"{path}.concept")
        enum(module["status"], STATUSES, f"{path}.status")
        timestamp(module["as_of"], f"{path}.as_of", nullable=True)
        require(type(module["truncated"]) is bool, f"{path}.truncated must be boolean")
        string(module["message"], f"{path}.message", nonempty=False)
    require(isinstance(snapshot["records"], list), "records must be an array")
    ids: set[str] = set()
    for index, record in enumerate(snapshot["records"]):
        validate_record(record, f"records[{index}]")
        require(record["id"] not in ids, f"records[{index}].id duplicates {record['id']}")
        ids.add(record["id"])


def validate_record(record: Any, path: str) -> None:
    fields(record, ("id", "concept", "source_time", "confirmed_at", "updated_at",
                    "direction", "lower", "upper", "state", "active", "related_ids",
                    "period_start", "period_end", "reference_price", "comparison_price",
                    "strength", "reason"), path)
    for name in ("id", "concept", "state"):
        string(record[name], f"{path}.{name}")
    enum(record["concept"], CONCEPTS, f"{path}.concept")
    for name in ("source_time", "confirmed_at", "updated_at"):
        timestamp(record[name], f"{path}.{name}")
    for name in ("period_start", "period_end"):
        timestamp(record[name], f"{path}.{name}", nullable=True)
    enum(record["direction"], DIRECTIONS, f"{path}.direction")
    for name in ("lower", "upper"):
        number(record[name], f"{path}.{name}")
    require(record["lower"] <= record["upper"], f"{path}.lower must not exceed upper")
    require(type(record["active"]) is bool, f"{path}.active must be boolean")
    require(isinstance(record["related_ids"], list), f"{path}.related_ids must be an array")
    for index, related_id in enumerate(record["related_ids"]):
        string(related_id, f"{path}.related_ids[{index}]")
    for name in ("reference_price", "comparison_price", "strength"):
        number(record[name], f"{path}.{name}")
    string(record["reason"], f"{path}.reason", nonempty=False)


def format_price(value: float) -> str:
    """Format the binary64 value with round-to-even; rendered zero has no sign."""
    rendered = f"{float(value):.8f}"
    return "0.00000000" if rendered == "-0.00000000" else rendered


def render_snapshot(snapshot: dict[str, Any], concept: str | None = None,
                    direction: str | None = None) -> str:
    as_of = snapshot["as_of"] if snapshot["as_of"] is not None else "null"
    lines = [(f"status={snapshot['status']} symbol={snapshot['symbol']} "
              f"timeframe={snapshot['timeframe']} as_of={as_of} time_basis=broker")]
    for record in sorted(snapshot["records"], key=lambda item: item["id"]):
        if concept is not None and record["concept"] != concept:
            continue
        if direction is not None and record["direction"] != direction:
            continue
        lines.append("\t".join((record["id"], record["concept"], record["direction"],
                                record["state"], format_price(record["lower"]),
                                format_price(record["upper"]))))
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot", help="UTF-8 snapshot JSON path")
    parser.add_argument("--concept", help="uppercase concept, for example IFVG")
    parser.add_argument("--direction", choices=sorted(DIRECTIONS))
    args = parser.parse_args(argv)
    if args.concept is not None and CONCEPT.fullmatch(args.concept) is None:
        parser.error("--concept must be an uppercase concept name")
    try:
        snapshot = load_snapshot(args.snapshot)
        sys.stdout.write(render_snapshot(snapshot, args.concept, args.direction))
        return 0
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
