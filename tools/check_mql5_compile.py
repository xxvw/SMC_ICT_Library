#!/usr/bin/env python3
"""Compile MQL5 entry points with MetaEditor in a fresh, disposable workspace.

Configuration: MQL5_METAEDITOR, MQL5_INCLUDE_DIR (the standard Include folder),
MQL5_WINE and WINEPREFIX. Native Windows and the official macOS MT5 Wine app
are discovered automatically. This command never starts the trading terminal.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIRS = ("Experts", "Indicators", "Scripts", "tests")
SUMMARY = re.compile(r"(?:Result:\s*)?(\d+)\s+errors?,\s*(\d+)\s+warnings?", re.I)
MAC_WINE = Path("/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine")
MAC_PREFIX = Path.home() / "Library/Application Support/net.metaquotes.wine.metatrader5"


@dataclass(frozen=True)
class Compiler:
    executable: Path
    includes: Path
    wine: Path | None = None
    prefix: Path | None = None

    def environment(self) -> dict[str, str]:
        env = os.environ.copy()
        if self.wine:
            env["WINEDEBUG"] = "-all"
            env["MVK_CONFIG_LOG_LEVEL"] = "0"
            if self.prefix:
                env["WINEPREFIX"] = str(self.prefix)
        return env

    def windows_path(self, path: Path) -> str:
        if not self.wine:
            return str(path.resolve())
        # Resolve against actual Wine drive mappings, including custom prefixes.
        assert self.prefix is not None
        resolved = path.resolve()
        drives = self.prefix / "dosdevices"
        matches: list[tuple[int, str]] = []
        for drive in drives.glob("?:"):
            try:
                target = drive.resolve(strict=True)
                relative = resolved.relative_to(target)
            except (OSError, ValueError):
                continue
            matches.append((len(target.parts), str(drive.name).upper() + "\\" + str(relative).replace("/", "\\")))
        if not matches:
            raise RuntimeError(f"No Wine drive maps {path}; configure a drive in {drives}.")
        return max(matches)[1]


def discover_compiler() -> Compiler:
    native = os.name == "nt"
    prefix = Path(os.environ.get("WINEPREFIX", str(MAC_PREFIX if MAC_PREFIX.is_dir() else Path.home() / ".wine"))).expanduser()
    explicit = os.environ.get("MQL5_METAEDITOR") or os.environ.get("METAEDITOR_PATH")
    candidates = [Path(explicit).expanduser()] if explicit else []
    if not explicit:
        for name in ("MetaEditor64.exe", "metaeditor64.exe", "metaeditor.exe"):
            found = shutil.which(name)
            if found:
                candidates.append(Path(found))
        if native:
            for variable in ("ProgramFiles", "ProgramFiles(x86)"):
                if os.environ.get(variable):
                    candidates.append(Path(os.environ[variable]) / "MetaTrader 5/MetaEditor64.exe")
        else:
            candidates.extend(prefix.glob("drive_c/Program Files/MetaTrader 5/[Mm]eta[Ee]ditor64.exe"))
    executable = next((path.resolve() for path in candidates if path.is_file()), None)
    if executable is None:
        raise RuntimeError("MetaEditor was not found. Install MT5 and set MQL5_METAEDITOR to MetaEditor64.exe (a host filesystem path). Compilation is required, not skipped.")
    include_option = os.environ.get("MQL5_INCLUDE_DIR")
    includes = Path(include_option).expanduser() if include_option else executable.parent / "MQL5/Include"
    if not includes.is_dir() or not (includes / "Trade/Trade.mqh").is_file():
        raise RuntimeError(f"MT5 standard includes were not found in {includes}. Set MQL5_INCLUDE_DIR to the terminal's MQL5/Include directory.")
    if native:
        return Compiler(executable, includes.resolve())
    wine_option = os.environ.get("MQL5_WINE") or os.environ.get("WINE")
    wine = Path(wine_option).expanduser() if wine_option else MAC_WINE if MAC_WINE.is_file() else Path(shutil.which("wine") or "/nonexistent/wine")
    if not wine.is_file() or not prefix.is_dir():
        raise RuntimeError("Wine was not found or its prefix does not exist. Set MQL5_WINE to the Wine executable and WINEPREFIX to your existing MT5 prefix.")
    return Compiler(executable, includes.resolve(), wine.resolve(), prefix.resolve())


def decode_log(data: bytes) -> str:
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16")
    if b"\x00" in data[:200]:
        return data.decode("utf-16-le")
    return data.decode("utf-8-sig")


def verify_compilation(log: Path, artifact: Path, started: float) -> tuple[int, int]:
    """Require fresh log, a complete zero-error summary and a fresh binary.

    MetaEditor can report errors with exit status zero, or succeed with a
    nonzero status under Wine. Its process status is deliberately not evidence.
    """
    for path, label in ((log, "compilation log"), (artifact, "EX5 artifact")):
        if not path.is_file():
            if path == artifact:
                break  # Report compiler diagnostics before the missing binary.
            raise RuntimeError(f"Missing {label}: {path}")
        if path.stat().st_mtime < started:
            raise RuntimeError(f"Stale {label}: {path}")
    try:
        text = decode_log(log.read_bytes())
    except UnicodeError as exc:
        raise RuntimeError(f"Unreadable compilation log: {log}: {exc}") from exc
    summaries = SUMMARY.findall(text)
    if not summaries:
        raise RuntimeError(f"Compilation log has no result summary:\n{text[-12000:]}")
    errors, warnings = map(int, summaries[-1])
    if errors:
        raise RuntimeError(f"MetaEditor reported {errors} error(s):\n{text[-16000:]}")
    if not artifact.is_file() or artifact.stat().st_size == 0:
        raise RuntimeError(f"Missing or empty EX5 artifact: {artifact}")
    if artifact.stat().st_mtime < started:
        raise RuntimeError(f"Stale EX5 artifact: {artifact}")
    return errors, warnings


def compile_source(compiler: Compiler, source: Path, stage: Path, timeout: int) -> int:
    log, artifact = source.with_suffix(".log"), source.with_suffix(".ex5")
    # These paths are private to this invocation; delete even copied artifacts.
    log.unlink(missing_ok=True)
    artifact.unlink(missing_ok=True)
    command = ([str(compiler.wine)] if compiler.wine else []) + [
        str(compiler.executable),
        f"/compile:{compiler.windows_path(source)}",
        f"/include:{compiler.windows_path(stage)}",
        "/log",
    ]
    # Round down for filesystems with coarse timestamp resolution. Fresh staging
    # plus deletion above is what prevents artifacts from previous invocations.
    started = float(int(time.time()))
    try:
        completed = subprocess.run(command, env=compiler.environment(), capture_output=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"MetaEditor timed out after {timeout}s for {source.name}") from exc
    try:
        _, warnings = verify_compilation(log, artifact, started)
    except RuntimeError as exc:
        tail = (completed.stdout + completed.stderr).decode("utf-8", errors="replace")[-2000:]
        # Wine graphics diagnostics add no value on successful compilations.
        raise RuntimeError(f"{exc}\nMetaEditor exit status: {completed.returncode}\n{tail}") from exc
    return warnings


def collect_sources(root: Path, selected: list[str]) -> list[Path]:
    if selected:
        sources = []
        for name in selected:
            candidate = (root / name).resolve()
            try:
                relative = candidate.relative_to(root.resolve())
            except ValueError as exc:
                raise RuntimeError(f"Source must be inside the repository: {name}") from exc
            if relative.parts[0] not in SOURCE_DIRS or candidate.suffix.lower() != ".mq5" or not candidate.is_file():
                raise RuntimeError(f"Expected an existing .mq5 entry point under {', '.join(SOURCE_DIRS)}: {name}")
            sources.append(relative)
        return sorted(set(sources))
    return sorted(path.relative_to(root) for folder in SOURCE_DIRS for path in (root / folder).rglob("*.mq5"))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", action="append", default=[], help="Compile only this repository-relative .mq5 path (repeatable; full validation must omit this option).")
    parser.add_argument("--timeout", type=int, default=120, help="Maximum seconds per compilation (default: 120).")
    args = parser.parse_args(argv)
    try:
        if args.timeout <= 0:
            raise RuntimeError("--timeout must be positive")
        sources = collect_sources(ROOT, args.source)
        if not sources:
            raise RuntimeError("No MQL5 entry points found.")
        compiler = discover_compiler()
        with tempfile.TemporaryDirectory(prefix="smc-mql5-") as directory:
            stage = Path(directory)
            shutil.copytree(compiler.includes, stage / "Include")
            shutil.copytree(ROOT / "Include", stage / "Include", dirs_exist_ok=True)
            for folder in SOURCE_DIRS:
                if (ROOT / folder).is_dir():
                    shutil.copytree(ROOT / folder, stage / folder)
            failures = []
            for source in sources:
                try:
                    warnings = compile_source(compiler, stage / source, stage, args.timeout)
                    print(f"PASS {source}: 0 errors, {warnings} warnings (fresh EX5)", flush=True)
                except (RuntimeError, OSError) as exc:
                    failures.append(source)
                    print(f"FAIL {source}: {exc}", file=sys.stderr, flush=True)
            if failures:
                return 1
        print(f"MetaEditor compilation passed for {len(sources)} entry point(s).")
        return 0
    except (RuntimeError, OSError) as exc:
        print(f"MQL5 compilation failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
