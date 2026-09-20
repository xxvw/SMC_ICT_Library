#!/usr/bin/env python3
"""Run real MQL5 fixtures, then validate their exports with all six readers."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

import run_mql5_tests as runtime
from check_all import EXAMPLE_LANGUAGES, write_report

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = EXAMPLE_LANGUAGES


def artifact_path(directory: Path, value: object, started: float) -> Path:
    if not isinstance(value, str) or not value or Path(value).is_absolute():
        raise ValueError("An artifact must have a relative path inside its runtime run.")
    relative = Path(value)
    if ".." in relative.parts:
        raise ValueError("Artifact paths must not traverse outside their runtime run.")
    path = (directory / relative).resolve()
    if not path.is_relative_to(directory.resolve()):
        raise ValueError("Artifact path escapes its runtime run.")
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"Missing or empty runtime artifact: {value}")
    if path.stat().st_mtime < started:
        raise ValueError(f"Stale runtime artifact: {value}")
    return path


def verified_snapshots(artifacts: Path, expected_sources: list[str], started: float) -> list[dict]:
    """Require complete runtime evidence before a reader consumes any export."""
    manifests = list(artifacts.glob("run-*/manifest.json"))
    if len(manifests) != 1:
        raise ValueError("Expected exactly one fresh runtime manifest.")
    manifest_path = manifests[0]
    directory = manifest_path.parent
    if directory.is_symlink() or not directory.resolve().is_relative_to(artifacts.resolve()):
        raise ValueError("Runtime manifest escapes the fresh artifact directory.")
    if not re.fullmatch(r"run-[0-9a-f]{32}", directory.name):
        raise ValueError("Runtime artifact directory has no unique invocation ID.")
    artifact_path(directory, "manifest.json", started)
    manifest = runtime.strict_json(manifest_path.read_text(encoding="utf-8"))
    results = manifest.get("tests") if isinstance(manifest, dict) else None
    if not expected_sources or not isinstance(results, list) or not results:
        raise ValueError("Runtime validation must execute at least one fixture.")
    if any(not isinstance(result, dict) for result in results):
        raise ValueError("Invalid runtime manifest entry.")
    sources = [result.get("source") for result in results]
    if len(sources) != len(set(sources)) or set(sources) != set(expected_sources):
        raise ValueError("Runtime manifest must cover every discovered fixture exactly once.")
    run_ids = [result.get("run_id") for result in results]
    if any(not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{32}", value) for value in run_ids):
        raise ValueError("Runtime manifest has an invalid test invocation ID.")
    if len(run_ids) != len(set(run_ids)):
        raise ValueError("Runtime fixtures must have unique invocation IDs.")
    snapshots = []
    for result in results:
        files = result.get("artifacts")
        if not isinstance(files, dict):
            raise ValueError("A runtime fixture has no artifact evidence.")

        def fixture_artifact(value: object) -> Path:
            folder = directory / result["run_id"]
            if folder.is_symlink() or not isinstance(value, str) or Path(value).parts[:1] != (result["run_id"],):
                raise ValueError("An artifact belongs to a different runtime fixture.")
            path = artifact_path(directory, value, started)
            if not path.is_relative_to(folder.resolve()):
                raise ValueError("An artifact escapes its fixture invocation directory.")
            return path

        report_path = fixture_artifact(files.get("report"))
        report = runtime.verify_report(report_path, result["run_id"], started)
        if any(report.get(field) != result.get(field)
               for field in ("suite", "assertions", "failed", "failures")):
            raise ValueError("Runtime manifest disagrees with its assertion report.")
        if result.get("suite") == "snapshot_export" or "snapshot" in files:
            path = fixture_artifact(files.get("snapshot"))
            checksum = hashlib.sha256(path.read_bytes()).hexdigest()
            if files.get("snapshot_sha256") != checksum:
                raise ValueError("Runtime snapshot checksum does not match the manifest.")
            snapshots.append({"source": result["source"], "path": str(path), "sha256": checksum})
    if not snapshots:
        raise ValueError("Runtime fixtures produced no generated MT5 snapshot to test.")
    return snapshots


def check_readers(root: Path, snapshots: list[dict], report: dict) -> None:
    # Import from this immutable checkout, never from a developer's live worktree.
    import check_examples as examples

    if tuple(examples.LANGUAGES) != LANGUAGES or not snapshots:
        raise ValueError("End-to-end validation requires all six readers and a generated snapshot.")
    fixture = root / "tests/fixtures/snapshot-v1.json"
    schema = root / "schemas/snapshot.schema.json"
    baseline = examples.load_snapshot(fixture, schema)
    expected = (root / "tests/fixtures/snapshot-v1.expected.txt").read_text(encoding="utf-8")
    examples.assert_output(examples.expected_output(baseline), expected, "shared fixture reference")
    inputs = []
    for item in snapshots:
        path = Path(item["path"])
        if hashlib.sha256(path.read_bytes()).hexdigest() != item["sha256"]:
            raise ValueError("Generated snapshot changed before reader validation.")
        snapshot = examples.load_snapshot(path, schema)
        path.with_suffix(".expected.txt").write_text(examples.expected_output(snapshot), encoding="utf-8", newline="\n")
        inputs.append((path, snapshot))
    for language in LANGUAGES:
        print(f"[{language}] Build, unit tests, shared fixture, and {len(inputs)} actual MT5 export(s)", flush=True)
        check = {"language": language, "success": False, "snapshots": 0, "assertions": 0}
        report["checks"].append(check)
        command = examples.prepare_language(root, language, examples.DEFAULT_TIMEOUT, report["versions"])
        for item, additional in zip(snapshots, inputs):
            if hashlib.sha256(additional[0].read_bytes()).hexdigest() != item["sha256"]:
                raise ValueError("Generated snapshot changed during reader validation.")
            check["assertions"] += examples.verify_cli(
                command, root, fixture, baseline, expected, examples.DEFAULT_TIMEOUT, additional,
            )
            check["snapshots"] += 1
        check["success"] = True
    for item in snapshots:
        if hashlib.sha256(Path(item["path"]).read_bytes()).hexdigest() != item["sha256"]:
            raise ValueError("Generated snapshot changed after reader validation.")


def main() -> int:
    report_path = ROOT / ".validation/end-to-end.json"
    report = {"schema_version": 1, "success": False, "completed": False,
              "started_at": datetime.now(timezone.utc).isoformat(),
              "languages": list(LANGUAGES), "versions": {}, "checks": [], "snapshots": []}
    write_report(report_path, report)
    try:
        directory_names = {path.name for path in ROOT.iterdir() if path.is_dir()}
        test_directory = "tests" if "tests" in directory_names else "Tests"
        expected = [f"{test_directory}/{source.as_posix()}" for source in runtime.collect_tests([])]
        compiler = runtime.discover_compiler()
        terminal, _ = runtime.discover_runtime(compiler)
        # The binaries have no reliable noninteractive version command. Their
        # exact hashes identify the installed compiler/runtime used by this run.
        report["versions"]["metaeditor_sha256"] = hashlib.sha256(compiler.executable.read_bytes()).hexdigest()
        report["versions"]["terminal_sha256"] = hashlib.sha256(terminal.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory(prefix="smc-end-to-end-") as temporary:
            artifacts = Path(temporary).resolve()
            started = float(int(time.time()))
            subprocess.run([sys.executable, str(ROOT / "tools/run_mql5_tests.py"),
                            "--artifacts", str(artifacts)], cwd=ROOT, check=True)
            snapshots = verified_snapshots(artifacts, expected, started)
            report["snapshots"] = [{key: value for key, value in item.items() if key != "path"}
                                   for item in snapshots]
            report["runtime_sources"] = expected
            check_readers(ROOT, snapshots, report)
        report["completed"] = True
        report["success"] = len(report["checks"]) == len(LANGUAGES) and all(
            check["success"] and check["snapshots"] == len(report["snapshots"])
            and check["assertions"] > 0 for check in report["checks"])
    except (OSError, ValueError, RuntimeError, ImportError, subprocess.CalledProcessError) as exc:
        report["error"] = str(exc)
        print(f"MT5-to-reader validation failed: {exc}", file=sys.stderr)
    except KeyboardInterrupt:
        report["error"] = "MT5-to-reader validation was interrupted."
        print(report["error"], file=sys.stderr)
    finally:
        report["finished_at"] = datetime.now(timezone.utc).isoformat()
        write_report(report_path, report)
    for name, version in report["versions"].items():
        print(f"[{name}] {version.splitlines()[0]}")
    print(f"Validated {len(report['snapshots'])} generated snapshot(s) across {len(report['checks'])} reader(s).")
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
