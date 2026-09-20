#!/usr/bin/env python3
"""Compile and run synthetic MQL5 fixtures in a fresh, account-free terminal.

Requires check_mql5_compile.py's MetaEditor/Wine configuration. MQL5_TERMINAL
can select terminal64.exe and MQL5_DEFAULT_SYMBOLS can select MT5's public
Bases/Default/symbols/symbols-0.dat. No trading-account configuration, broker
history, profiles or credentials are copied. Only reviewed, trusted tests may
run here: a portable terminal is process/data isolation, not a security sandbox.

Startup format: https://www.metatrader5.com/en/terminal/help/start_advanced/start
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

from check_mql5_compile import Compiler, compile_source, decode_log, discover_compiler

ROOT = Path(__file__).resolve().parents[1]
REPORT_NAME = "smc-test-report.json"
SNAPSHOT_NAME = "snapshot-fixture.json"


def strict_json(text: str):
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"Duplicate JSON property: {key}")
            result[key] = value
        return result

    def reject_constant(value):
        raise ValueError(f"Non-finite JSON number: {value}")

    def finite_float(value):
        number = float(value)
        if not math.isfinite(number):
            raise ValueError(f"Non-finite JSON number: {value}")
        return number

    return json.loads(text, object_pairs_hook=unique_object, parse_constant=reject_constant,
                      parse_float=finite_float)


def discover_runtime(compiler: Compiler) -> tuple[Path, Path]:
    terminal = Path(os.environ.get("MQL5_TERMINAL", str(compiler.executable.parent / "terminal64.exe"))).expanduser()
    symbols = Path(os.environ.get("MQL5_DEFAULT_SYMBOLS", str(terminal.parent / "Bases/Default/symbols/symbols-0.dat"))).expanduser()
    if not terminal.is_file():
        raise RuntimeError("MT5 terminal was not found. Set MQL5_TERMINAL to terminal64.exe.")
    if not symbols.is_file() or symbols.stat().st_size == 0:
        raise RuntimeError("MT5 default symbol definitions were not found. Set MQL5_DEFAULT_SYMBOLS to Bases/Default/symbols/symbols-0.dat from an installed MT5 terminal. Account-specific databases are not needed; runtime tests cannot be skipped.")
    return terminal.resolve(), symbols.resolve()


def collect_tests(selected: list[str]) -> list[Path]:
    sources = [ROOT / name for name in selected] if selected else sorted((ROOT / "tests").rglob("*.mq5"))
    tests = []
    for source in sources:
        try:
            relative = source.resolve().relative_to((ROOT / "tests").resolve())
        except ValueError as exc:
            raise RuntimeError(f"Tests must be inside tests/: {source}") from exc
        if not source.is_file() or source.suffix.lower() != ".mq5":
            raise RuntimeError(f"Expected an existing MQL5 test script: {source}")
        tests.append(relative)
    if not tests:
        raise RuntimeError("No MQL5 runtime tests found.")
    return sorted(set(tests))


def verify_report(path: Path, run_id: str, started: float) -> dict:
    if not path.is_file() or path.stat().st_mtime < started:
        raise RuntimeError("Runtime test did not produce a fresh report.")
    try:
        result = strict_json(path.read_text(encoding="utf-8-sig"))
    except (ValueError, UnicodeError) as exc:
        raise RuntimeError(f"Malformed MQL5 test report: {exc}") from exc
    if not isinstance(result, dict) or result.get("run_id") != run_id:
        raise RuntimeError("MQL5 report does not match this test invocation.")
    if not isinstance(result.get("suite"), str) or not result["suite"]:
        raise RuntimeError("MQL5 report has no suite name.")
    # TestBegin contributes two safety checks. At least one fixture assertion
    # must also execute, preventing an empty suite from passing the gate.
    if type(result.get("assertions")) is not int or result["assertions"] < 3:
        raise RuntimeError("MQL5 test did not execute any fixture assertions.")
    if type(result.get("failed")) is not int or not isinstance(result.get("failures"), list):
        raise RuntimeError("MQL5 report has invalid failure counters.")
    if result["failed"] != 0 or result["failures"]:
        raise RuntimeError(f"{result['suite']}: {result['failed']} assertion failure(s): {result['failures']}")
    return result


def verify_snapshot_fixture(path: Path, schema_path: Path, started: float) -> bytes:
    """Validate the exact UTF-8 bytes emitted by the real MQL5 exporter."""
    if not path.is_file() or path.stat().st_mtime < started:
        raise RuntimeError("Snapshot export test did not produce a fresh snapshot fixture.")
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf") or b"\x00" in data:
        raise RuntimeError("Snapshot fixture must be UTF-8 without BOM or NUL bytes.")
    try:
        snapshot = strict_json(data.decode("utf-8"))
    except (ValueError, UnicodeError) as exc:
        raise RuntimeError(f"Malformed snapshot fixture: {exc}") from exc
    if not schema_path.is_file():
        raise RuntimeError(f"Snapshot JSON Schema is required for snapshot_export: {schema_path}")
    try:
        import jsonschema
    except ImportError as exc:
        raise RuntimeError("jsonschema is required for snapshot_export; use the project's development Python environment.") from exc
    try:
        schema = strict_json(schema_path.read_text(encoding="utf-8"))
        jsonschema.Draft202012Validator.check_schema(schema)
        jsonschema.Draft202012Validator(schema).validate(snapshot)
    except (ValueError, UnicodeError, jsonschema.exceptions.SchemaError,
            jsonschema.exceptions.ValidationError) as exc:
        raise RuntimeError(f"Snapshot fixture failed JSON Schema validation: {exc}") from exc
    return data


def preserve_artifacts(stage: Path, result: dict, destination: Path,
                       snapshot: bytes | None) -> dict:
    """Preserve only verified artifacts, under a non-overwriting run UUID."""
    folder = destination / result["run_id"]
    folder.mkdir(parents=True, exist_ok=False)
    report = folder / REPORT_NAME
    shutil.copyfile(stage / "MQL5/Files" / REPORT_NAME, report)
    artifacts = {"report": str(report.relative_to(destination))}
    if snapshot is not None:
        fixture = folder / SNAPSHOT_NAME
        fixture.write_bytes(snapshot)
        artifacts["snapshot"] = str(fixture.relative_to(destination))
        artifacts["snapshot_sha256"] = hashlib.sha256(snapshot).hexdigest()
    return artifacts


def runtime_diagnostics(terminal: Path) -> str:
    chunks = []
    for folder in (terminal / "logs", terminal / "MQL5/logs"):
        for path in sorted(folder.glob("*.log"))[-2:]:
            try:
                chunks.append(f"{path.relative_to(terminal)}:\n{decode_log(path.read_bytes())[-4000:]}")
            except (OSError, UnicodeError):
                continue
    return "\n".join(chunks)


def run_test(compiler: Compiler, executable: Path, symbols: Path,
             binary: Path, stage: Path, timeout: int,
             artifacts: Path | None = None) -> dict:
    """Run exactly one fresh binary with a unique report in its own terminal."""
    stage.mkdir()
    terminal = stage / "terminal64.exe"
    # Never hardlink the original executable: a terminal self-update must not
    # modify the installed copy. No existing terminal config is read or copied.
    shutil.copyfile(executable, terminal)
    symbol_target = stage / "Bases/Default/symbols/symbols-0.dat"
    symbol_target.parent.mkdir(parents=True)
    shutil.copyfile(symbols, symbol_target)
    scripts = stage / "MQL5/Scripts/SMCTests"
    scripts.mkdir(parents=True)
    shutil.copyfile(binary, scripts / "Fixture.ex5")
    run_id = uuid.uuid4().hex
    presets = stage / "MQL5/Presets"
    presets.mkdir(parents=True)
    (presets / "fixture.set").write_text(f"SMC_TestRunId={run_id}\n", encoding="utf-16")
    configuration = stage / "runtime.ini"
    configuration.write_text(
        "[Common]\nLogin=0\nKeepPrivate=0\nNewsEnable=0\n"
        "[Experts]\nEnabled=0\nAllowLiveTrading=0\nAllowDllImport=0\n"
        "[StartUp]\nScript=SMCTests\\Fixture\nSymbol=EURUSD\nPeriod=M1\n"
        "ScriptParameters=fixture.set\nShutdownTerminal=1\n",
        encoding="utf-16",
    )
    command = ([str(compiler.wine)] if compiler.wine else []) + [
        str(terminal), "/portable", f"/config:{compiler.windows_path(configuration)}",
    ]
    started = float(int(time.time()))
    with (stage / "process.log").open("wb") as output:
        process = subprocess.Popen(command, env=compiler.environment(), cwd=stage,
                                   stdout=output, stderr=subprocess.STDOUT)
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
            raise RuntimeError(f"MQL5 fixture timed out after {timeout}s.\n{runtime_diagnostics(stage)}") from exc
        except BaseException:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
            raise
    # Wine/MT5 can return 1 after a successful TerminalClose(0). Require the
    # fresh, complete assertion report rather than interpreting the exit code.
    try:
        result = verify_report(stage / "MQL5/Files" / REPORT_NAME, run_id, started)
        snapshot = None
        if result["suite"] == "snapshot_export":
            snapshot = verify_snapshot_fixture(stage / "MQL5/Files" / SNAPSHOT_NAME,
                                               ROOT / "schemas/snapshot.schema.json", started)
        if artifacts is not None:
            result["artifacts"] = preserve_artifacts(stage, result, artifacts, snapshot)
        return result
    except RuntimeError as exc:
        raise RuntimeError(f"{exc}\nTerminal exit status: {process.returncode}\n{runtime_diagnostics(stage)}") from exc


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", action="append", default=[], help="Run only this repository-relative tests/*.mq5 file (repeatable).")
    parser.add_argument("--timeout", type=int, default=120, help="Maximum seconds per compilation or runtime execution (default: 120).")
    parser.add_argument("--artifacts", type=Path, help="Preserve verified reports and MT5 snapshot bytes in a unique run directory here. A manifest is published only if every selected test passes.")
    args = parser.parse_args(argv)
    try:
        if args.timeout <= 0:
            raise RuntimeError("--timeout must be positive")
        tests = collect_tests(args.source)
        compiler = discover_compiler()
        executable, symbols = discover_runtime(compiler)
        artifacts = None
        if args.artifacts is not None:
            artifacts = args.artifacts.expanduser().resolve() / ("run-" + uuid.uuid4().hex)
            artifacts.mkdir(parents=True, exist_ok=False)
        results = []
        with tempfile.TemporaryDirectory(prefix="smc-mql5-runtime-") as directory:
            stage = Path(directory)
            shutil.copytree(compiler.includes, stage / "Include")
            shutil.copytree(ROOT / "Include", stage / "Include", dirs_exist_ok=True)
            shutil.copytree(ROOT / "tests", stage / "tests")
            failures = []
            for index, relative in enumerate(tests):
                try:
                    source = stage / "tests" / relative
                    compile_source(compiler, source, stage, args.timeout)
                    result = run_test(compiler, executable, symbols, source.with_suffix(".ex5"),
                                      stage / f"runtime-{index}", args.timeout, artifacts)
                    results.append({"source": f"tests/{relative}", **result})
                    print(f"PASS tests/{relative}: {result['assertions']} MQL5 assertions", flush=True)
                except (RuntimeError, OSError) as exc:
                    failures.append(relative)
                    print(f"FAIL tests/{relative}: {exc}", file=sys.stderr, flush=True)
            if failures:
                return 1
        if artifacts is not None:
            manifest = artifacts / "manifest.json"
            manifest.write_text(json.dumps({"tests": results}, indent=2) + "\n", encoding="utf-8")
            print(f"Runtime artifacts: {manifest}")
        print(f"MQL5 runtime tests passed for {len(tests)} fixture(s).")
        return 0
    except (RuntimeError, OSError) as exc:
        print(f"MQL5 runtime validation failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
