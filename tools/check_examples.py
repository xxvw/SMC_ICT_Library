#!/usr/bin/env python3
"""Build and test the snapshot readers locally, then compare their CLI contracts."""

from __future__ import annotations

import argparse
import difflib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from contextlib import ExitStack
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ("python", "typescript", "go", "csharp", "rust", "java")
DEFAULT_TIMEOUT = 300


class ValidationError(RuntimeError):
    """A required tool, build, unit test, or CLI contract check failed."""


def require_executable(name: str) -> str:
    executable = shutil.which(name)
    if executable is None:
        raise ValidationError(f"Required executable is missing from PATH: {name}")
    return executable


def run_command(command: list[str], cwd: Path, timeout: int = DEFAULT_TIMEOUT,
                expect_success: bool = True) -> subprocess.CompletedProcess[str]:
    try:
        completed = subprocess.run(command, cwd=cwd, capture_output=True, text=False,
                                   check=False, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise ValidationError(f"Command timed out after {timeout}s: {' '.join(command)}") from exc
    except OSError as exc:
        raise ValidationError(f"Could not execute {' '.join(command)}: {exc}") from exc
    try:
        result = subprocess.CompletedProcess(
            completed.args, completed.returncode,
            completed.stdout.decode("utf-8"), completed.stderr.decode("utf-8"))
    except UnicodeError as exc:
        raise ValidationError(f"Command emitted invalid UTF-8: {' '.join(command)}") from exc
    if result.returncode < 0:
        raise ValidationError(f"Command terminated by signal {-result.returncode}: {' '.join(command)}")
    if (result.returncode == 0) != expect_success:
        expectation = "success" if expect_success else "a nonzero exit code"
        details = (result.stdout + result.stderr)[-12000:]
        raise ValidationError(f"Expected {expectation}, got exit {result.returncode}: "
                              f"{' '.join(command)}\n{details}")
    return result


def assert_output(actual: str, expected: str, label: str) -> None:
    if actual != expected:
        difference = "".join(difflib.unified_diff(
            expected.splitlines(keepends=True), actual.splitlines(keepends=True),
            fromfile="expected", tofile="actual"))
        raise ValidationError(f"{label}: output differs from the contract\n{difference[:12000]}")


def expected_output(snapshot: dict[str, Any], concept: str | None = None,
                    direction: str | None = None) -> str:
    """Independent formatter: never import an example's parser or output code."""
    as_of = snapshot["as_of"] if snapshot["as_of"] is not None else "null"
    lines = [(f"status={snapshot['status']} symbol={snapshot['symbol']} "
              f"timeframe={snapshot['timeframe']} as_of={as_of} time_basis=broker")]

    def price(value: float) -> str:
        # Python's fixed format rounds the exact binary64 value, with ties to even.
        rendered = f"{float(value):.8f}"
        return "0.00000000" if rendered == "-0.00000000" else rendered

    for record in sorted(snapshot["records"], key=lambda item: item["id"]):
        if concept is not None and record["concept"] != concept:
            continue
        if direction is not None and record["direction"] != direction:
            continue
        lines.append("\t".join((record["id"], record["concept"], record["direction"],
                                record["state"], price(record["lower"]),
                                price(record["upper"]))))
    return "\n".join(lines) + "\n"


def reject_constant(value: str) -> None:
    raise ValidationError(f"Nonfinite JSON number is forbidden: {value}")


def load_snapshot(path: Path, schema_path: Path) -> dict[str, Any]:
    try:
        from jsonschema import Draft202012Validator
        from jsonschema.exceptions import SchemaError
        from jsonschema.exceptions import ValidationError as SchemaValidationError
    except ImportError as exc:
        raise ValidationError("Install the development requirements: jsonschema is required.") from exc
    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        snapshot = json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_constant)
        Draft202012Validator.check_schema(schema)
        Draft202012Validator(schema).validate(snapshot)
    except (OSError, ValueError, SchemaError, SchemaValidationError) as exc:
        raise ValidationError(f"Invalid snapshot or schema at {path}: {exc}") from exc

    def check_numbers(value: Any) -> None:
        if type(value) in (int, float):
            try:
                finite = math.isfinite(value)
            except OverflowError:
                finite = False
            if not finite:
                raise ValidationError(f"{path}: number is not a finite floating-point value")
        if isinstance(value, dict):
            for item in value.values():
                check_numbers(item)
        elif isinstance(value, list):
            for item in value:
                check_numbers(item)

    def check_timestamp(value: str | None) -> None:
        if value is not None:
            try:
                datetime.fromisoformat(value)
            except ValueError as exc:
                raise ValidationError(f"{path}: invalid broker calendar timestamp {value}") from exc

    check_numbers(snapshot)
    check_timestamp(snapshot["as_of"])
    for module in snapshot["modules"]:
        check_timestamp(module["as_of"])
    identifiers: set[str] = set()
    for record in snapshot["records"]:
        if record["id"] in identifiers or record["lower"] > record["upper"]:
            raise ValidationError(f"{path}: duplicate record ID or reversed price bounds")
        identifiers.add(record["id"])
        for field in ("source_time", "confirmed_at", "updated_at", "period_start", "period_end"):
            check_timestamp(record[field])
    return snapshot


def require_unit_tests(language: str, output: str) -> int:
    """A zero exit code alone does not prove that a test suite executed."""
    passed = skipped = 0
    if language == "go":
        try:
            events = [json.loads(line) for line in output.splitlines() if line.strip()]
            passed = sum(event.get("Action") == "pass" and bool(event.get("Test")) for event in events)
            skipped = sum(event.get("Action") == "skip" for event in events)
        except (ValueError, AttributeError) as exc:
            raise ValidationError("Go unit tests did not emit the expected JSON event stream") from exc
    else:
        patterns = {
            "python": (r"Ran ([0-9]+) tests?", r"skipped=([0-9]+)"),
            "typescript": (r"# pass ([0-9]+)", r"# skipped ([0-9]+)"),
            "csharp": (r"C# snapshot reader: ([0-9]+) checks passed", None),
            "rust": (r"test result: ok\. ([0-9]+) passed;", r"[0-9]+ failed; ([0-9]+) ignored;"),
            "java": (r"Tests run: ([0-9]+),", r"Skipped: ([0-9]+)"),
        }
        if language not in patterns:
            raise ValidationError(f"No unit-test evidence parser for {language}")
        passed_pattern, skipped_pattern = patterns[language]
        passed = sum(int(value) for value in re.findall(passed_pattern, output))
        skipped = sum(int(value) for value in re.findall(skipped_pattern, output)) if skipped_pattern else 0
    if passed < 1 or skipped:
        raise ValidationError(f"{language}: unit-test execution was incomplete "
                              f"(reported executed/passed={passed}, skipped={skipped})")
    return passed


def prepare_language(root: Path, language: str, timeout: int,
                     versions: dict[str, str]) -> list[str]:
    """Run the language's required build and tests, returning its compiled CLI."""
    directory = root / "examples" / language
    if not directory.is_dir():
        raise ValidationError(f"Required example directory is missing: {directory}")

    def tool(name: str, *version_args: str) -> str:
        executable = require_executable(name)
        if name not in versions:
            result = run_command([executable, *version_args], root, min(timeout, 60))
            versions[name] = (result.stdout + result.stderr).strip()
        return executable

    def run(*command: str) -> subprocess.CompletedProcess[str]:
        return run_command(list(command), directory, timeout)

    def tests(*command: str) -> None:
        result = run(*command)
        output = result.stdout if language == "go" else result.stdout + result.stderr
        require_unit_tests(language, output)

    if language == "python":
        python = sys.executable
        if not python:
            raise ValidationError("A Python interpreter is required")
        result = run_command([python, "--version"], root, min(timeout, 60))
        versions["python"] = (result.stdout + result.stderr).strip()
        tests(python, "-m", "unittest", "discover", "-s", ".", "-p", "test_*.py")
        return [python, str(directory / "read_snapshot.py")]
    if language == "typescript":
        node, npm = tool("node", "--version"), tool("npm", "--version")
        run(npm, "ci", "--no-audit", "--no-fund")
        run(npm, "run", "build")
        tests(node, "--test", "--test-reporter=tap", "tests/read_snapshot.test.mjs")
        return [node, str(directory / "dist/read_snapshot.js")]
    if language == "go":
        go = tool("go", "version")
        tests(go, "test", "-json", "-count=1", "./...")
        output = directory / "build" / ("snapshot-reader.exe" if os.name == "nt" else "snapshot-reader")
        output.parent.mkdir(exist_ok=True)
        run(go, "build", "-o", str(output), ".")
        return [str(output)]
    if language == "csharp":
        dotnet = tool("dotnet", "--version")
        run(dotnet, "build", "SnapshotReader.csproj", "--configuration", "Release", "--nologo")
        tests(dotnet, "run", "--project", "tests", "--configuration", "Release", "--",
              str(root / "tests/fixtures/snapshot-v1.json"))
        return [dotnet, str(directory / "bin/Release/net10.0/SnapshotReader.dll")]
    if language == "rust":
        cargo = tool("cargo", "--version")
        tool("rustc", "--version")
        tests(cargo, "test", "--locked")
        run(cargo, "clippy", "--locked", "--all-targets", "--", "-D", "warnings")
        run(cargo, "build", "--locked")
        binary = "smc-snapshot-reader.exe" if os.name == "nt" else "smc-snapshot-reader"
        return [str(directory / "target/debug" / binary)]
    if language == "java":
        maven, java = tool("mvn", "--version"), tool("java", "-version")
        tests(maven, "--batch-mode", "--no-transfer-progress", "-DfailIfNoTests=true",
              "-DskipTests=false", "-Dmaven.test.skip=false", "clean", "verify")
        return [java, "-jar", str(directory / "target/snapshot-reader-1.0.0.jar")]
    raise ValidationError(f"Unknown example language: {language}")


def verify_cli(command: list[str], root: Path, fixture: Path, snapshot: dict[str, Any],
               expected: str, timeout: int, additional: tuple[Path, dict[str, Any]] | None) -> int:
    assertions = 0

    def success(path: Path, expected_text: str, *options: str) -> None:
        nonlocal assertions
        result = run_command([*command, str(path), *options], root, timeout)
        assert_output(result.stdout, expected_text, " ".join(command + list(options)))
        assertions += 1

    def failure(path: Path, *options: str) -> None:
        nonlocal assertions
        result = run_command([*command, str(path), *options], root, timeout, expect_success=False)
        assert_output(result.stdout, "", "invalid input must not emit partial snapshot output")
        if not result.stderr.strip():
            raise ValidationError("Rejected input must include an error message on stderr")
        assertions += 1

    success(fixture, expected)
    success(fixture, expected_output(snapshot, "IFVG", "bearish"),
            "--concept", "IFVG", "--direction", "bearish")
    success(fixture, expected_output(snapshot, "SYNTHETIC_TEST"), "--concept", "SYNTHETIC_TEST")
    failure(fixture, "--direction", "invalid")
    failure(fixture, "--concept", "lower-case")
    failure(fixture, "--unknown-option")
    with tempfile.TemporaryDirectory(prefix="smc-example-contract-") as temporary:
        directory = Path(temporary)
        # Include exact halfway values and values whose short decimal spelling
        # hides the binary64 rounding boundary. The CLI must use the parsed double.
        prices = (0.0, -0.0, 5e-324, -5e-324, 1e-12, -1e-12,
                  0.001953125, -0.001953125, 0.005859375, -0.005859375,
                  1.000000005, -1.000000005, 1e21, -1e21, 1e100, -1e100,
                  sys.float_info.max, -sys.float_info.max, 9007199254740993)
        boundaries = json.loads(json.dumps(snapshot))
        template = boundaries["records"][0]
        boundaries["records"] = [template | {"id": f"price-{index:02d}", "lower": price, "upper": price}
                                 for index, price in enumerate(prices)]
        path = directory / "price-boundaries.json"
        path.write_text(json.dumps(boundaries), encoding="utf-8")
        success(path, expected_output(boundaries))
        for index, message in enumerate(("", "Comparison history is unavailable")):
            diagnostic = snapshot | {"message": message}
            path = directory / f"message-valid-{index}.json"
            path.write_text(json.dumps(diagnostic), encoding="utf-8")
            success(path, expected)
        for index, message in enumerate((None, False, 1, [], {})):
            diagnostic = snapshot | {"message": message}
            path = directory / f"message-invalid-{index}.json"
            path.write_text(json.dumps(diagnostic), encoding="utf-8")
            failure(path)
        for label, mutate in (
            ("unsupported-major", lambda value: value.update(schema_version="2.0")),
            ("missing-required", lambda value: value.pop("as_of")),
            ("missing-record-field", lambda value: value["records"][0].pop("lower")),
        ):
            malformed = json.loads(json.dumps(snapshot))
            mutate(malformed)
            path = directory / f"{label}.json"
            path.write_text(json.dumps(malformed), encoding="utf-8")
            # Filtering must never conceal invalid records.
            failure(path, "--concept", "SYNTHETIC_TEST")
    if additional is not None:
        path, actual = additional
        reference = path.with_suffix(".expected.txt")
        assert_output(reference.read_bytes().decode("utf-8"), expected_output(actual),
                      "captured snapshot reference")
        success(path, reference.read_bytes().decode("utf-8"))
        success(path, expected_output(actual, "IFVG", "bearish"),
                "--concept", "IFVG", "--direction", "bearish")
    return assertions


def write_report(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--language", action="append", choices=LANGUAGES,
                        help="Validate one language; repeat to select several. Default: all six.")
    parser.add_argument("--snapshot", type=Path,
                        help="Also validate a generated MT5 snapshot against the schema and every selected CLI")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT,
                        help="Maximum seconds per subprocess (default: 300)")
    parser.add_argument("--report", type=Path, default=ROOT / ".validation/examples-report.json")
    args = parser.parse_args(argv)
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    languages = list(dict.fromkeys(args.language or LANGUAGES))
    report: dict[str, Any] = {
        "schema_version": 1, "success": False, "completed": False,
        "started_at": datetime.now(timezone.utc).isoformat(),
        "languages": languages, "versions": {}, "checks": [],
    }
    temporary_inputs = ExitStack()
    try:
        write_report(args.report, report)
        fixture = ROOT / "tests/fixtures/snapshot-v1.json"
        schema_path = ROOT / "schemas/snapshot.schema.json"
        snapshot = load_snapshot(fixture, schema_path)
        expected = (ROOT / "tests/fixtures/snapshot-v1.expected.txt").read_text(encoding="utf-8")
        assert_output(expected_output(snapshot), expected, "shared fixture's independent reference")
        additional = None
        if args.snapshot is not None:
            source = args.snapshot.resolve()
            directory = Path(temporary_inputs.enter_context(
                tempfile.TemporaryDirectory(prefix="smc-export-validation-")))
            # Capture one complete export; live MT5 may replace the source on its next bar.
            path = directory / "snapshot.json"
            path.write_bytes(source.read_bytes())
            additional = (path, load_snapshot(path, schema_path))
            path.with_suffix(".expected.txt").write_text(
                expected_output(additional[1]), encoding="utf-8", newline="\n")
            report["snapshot"] = str(source)
        for language in languages:
            print(f"[{language}] Building, running unit tests, and checking the CLI contract", flush=True)
            check: dict[str, Any] = {"language": language, "success": False}
            report["checks"].append(check)
            try:
                command = prepare_language(ROOT, language, args.timeout, report["versions"])
                check["assertions"] = verify_cli(command, ROOT, fixture, snapshot, expected,
                                                  args.timeout, additional)
                check["success"] = True
                print(f"[{language}] Passed unit tests and {check['assertions']} CLI assertions", flush=True)
            except ValidationError as exc:
                check["error"] = str(exc)
                print(f"[{language}] FAILED: {exc}", file=sys.stderr, flush=True)
            write_report(args.report, report)
        report["completed"] = True
        report["success"] = all(check["success"] for check in report["checks"])
    except (OSError, ValueError, ValidationError) as exc:
        report["error"] = str(exc)
        print(f"Example validation failed: {exc}", file=sys.stderr)
    except KeyboardInterrupt:
        report["error"] = "Example validation interrupted; incomplete checks cannot pass."
        print(report["error"], file=sys.stderr)
    finally:
        temporary_inputs.close()
        report["finished_at"] = datetime.now(timezone.utc).isoformat()
        write_report(args.report, report)
    for name, version in report["versions"].items():
        print(f"[{name} version] {version.splitlines()[0]}")
    print(f"Report: {args.report.resolve()}", flush=True)
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
