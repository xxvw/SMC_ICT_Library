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
import json
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


def discover_runtime(compiler: Compiler) -> tuple[Path, Path]:
    terminal = Path(os.environ.get("MQL5_TERMINAL", str(compiler.executable.parent / "terminal64.exe"))).expanduser()
    symbols = Path(os.environ.get("MQL5_DEFAULT_SYMBOLS", str(terminal.parent / "Bases/Default/symbols/symbols-0.dat"))).expanduser()
    if not terminal.is_file():
        raise RuntimeError("MT5 terminal was not found. Set MQL5_TERMINAL to terminal64.exe.")
    if not symbols.is_file() or symbols.stat().st_size == 0:
        raise RuntimeError("MT5 default symbol definitions were not found. Set MQL5_DEFAULT_SYMBOLS to Bases/Default/symbols/symbols-0.dat from an installed MT5 terminal. Account-specific databases are not needed; runtime tests cannot be skipped.")
    return terminal.resolve(), symbols.resolve()


def collect_tests(selected: list[str]) -> list[Path]:
    sources = [ROOT / name for name in selected] if selected else sorted((ROOT / "Tests").rglob("*.mq5"))
    tests = []
    for source in sources:
        try:
            relative = source.resolve().relative_to(ROOT / "Tests")
        except ValueError as exc:
            raise RuntimeError(f"Tests must be inside Tests/: {source}") from exc
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
        result = json.loads(path.read_text(encoding="utf-8-sig"))
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
             binary: Path, stage: Path, timeout: int) -> dict:
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
        return verify_report(stage / "MQL5/Files" / REPORT_NAME, run_id, started)
    except RuntimeError as exc:
        raise RuntimeError(f"{exc}\nTerminal exit status: {process.returncode}\n{runtime_diagnostics(stage)}") from exc


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", action="append", default=[], help="Run only this repository-relative Tests/*.mq5 file (repeatable).")
    parser.add_argument("--timeout", type=int, default=120, help="Maximum seconds per compilation or runtime execution (default: 120).")
    args = parser.parse_args(argv)
    try:
        if args.timeout <= 0:
            raise RuntimeError("--timeout must be positive")
        tests = collect_tests(args.source)
        compiler = discover_compiler()
        executable, symbols = discover_runtime(compiler)
        with tempfile.TemporaryDirectory(prefix="smc-mql5-runtime-") as directory:
            stage = Path(directory)
            shutil.copytree(compiler.includes, stage / "Include")
            shutil.copytree(ROOT / "Include", stage / "Include", dirs_exist_ok=True)
            shutil.copytree(ROOT / "Tests", stage / "Tests")
            failures = []
            for index, relative in enumerate(tests):
                try:
                    source = stage / "Tests" / relative
                    compile_source(compiler, source, stage, args.timeout)
                    result = run_test(compiler, executable, symbols, source.with_suffix(".ex5"),
                                      stage / f"runtime-{index}", args.timeout)
                    print(f"PASS Tests/{relative}: {result['assertions']} MQL5 assertions", flush=True)
                except (RuntimeError, OSError) as exc:
                    failures.append(relative)
                    print(f"FAIL Tests/{relative}: {exc}", file=sys.stderr, flush=True)
            if failures:
                return 1
        print(f"MQL5 runtime tests passed for {len(tests)} fixture(s).")
        return 0
    except (RuntimeError, OSError) as exc:
        print(f"MQL5 runtime validation failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
