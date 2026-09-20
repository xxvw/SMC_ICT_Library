#!/usr/bin/env python3
"""Validate an immutable commit locally; never publish a GitHub status."""

from __future__ import annotations

import argparse
import io
import json
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_PROFILE = "bootstrap"
PROFILES = {
    "bootstrap": [
        ("python", [sys.executable, "tools/check_python.py"]),
        ("mql5-static", [sys.executable, "tools/check_mql5_static.py"]),
        ("validation-tests", [sys.executable, "-m", "unittest", "discover", "-s", "tools/tests"]),
    ],
}


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=root, text=True).strip()


def require_clean(root: Path) -> None:
    if git(root, "status", "--porcelain", "--untracked-files=all"):
        raise ValueError("Commit or stash changes before validating or publishing.")


def parse_push_updates(lines: list[str]) -> list[str]:
    """Inspect destination refs, including aliases and deletions of main."""
    commits: list[str] = []
    for line in lines:
        fields = line.split()
        if len(fields) != 4:
            raise ValueError("Invalid pre-push input.")
        _, local_sha, remote_ref, _ = fields
        if remote_ref == "refs/heads/main":
            raise ValueError("Direct pushes to main are forbidden; open a pull request.")
        if set(local_sha) != {"0"} and local_sha not in commits:
            commits.append(local_sha)
    return commits


def run_check(root: Path, name: str, command: list[str]) -> dict:
    print(f"[{name}] {' '.join(command)}", flush=True)
    try:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True)
        output = result.stdout + result.stderr
        print(output, end="" if output.endswith("\n") else "\n", flush=True)
        return {"name": name, "command": command, "returncode": result.returncode,
                "success": result.returncode == 0, "output": output[-12000:]}
    except OSError as exc:
        print(str(exc), file=sys.stderr)
        return {"name": name, "command": command, "returncode": None,
                "success": False, "output": str(exc)}


def write_report(path: Path, report: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def validate(root: Path, revision: str, profile: str, report_path: Path) -> bool:
    report = {"schema_version": 1, "profile": profile, "success": False,
              "completed": False, "checks": [],
              "started_at": datetime.now(timezone.utc).isoformat()}
    # Invalidate any earlier successful report even when setup or a tool fails.
    write_report(report_path, report)
    try:
        if profile not in PROFILES:
            raise ValueError(f"Unknown validation profile: {profile}")
        if not hasattr(tarfile, "data_filter"):
            raise ValueError("Python 3.11.8 or newer is required for safe archive extraction.")
        require_clean(root)
        commit = git(root, "rev-parse", "--verify", f"{revision}^{{commit}}")
        base = git(root, "rev-parse", "--verify", "origin/main^{commit}")
        report.update(commit_sha=commit, base_sha=base)
        archive = subprocess.check_output(["git", "archive", "--format=tar", commit], cwd=root)
        with tempfile.TemporaryDirectory(prefix="smc-validation-") as directory:
            snapshot = Path(directory).resolve()
            with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
                # The archive comes from git, but disallow paths/symlinks escaping it.
                for member in bundle.getmembers():
                    destination = (snapshot / member.name).resolve()
                    if not destination.is_relative_to(snapshot):
                        raise ValueError("Archive path escapes the validation checkout.")
                    if member.issym() or member.islnk():
                        target = (destination.parent / member.linkname).resolve()
                        if not target.is_relative_to(snapshot):
                            raise ValueError("Archive link escapes the validation checkout.")
                bundle.extractall(snapshot, filter="data")
            for name, command in PROFILES[profile]:
                report["checks"].append(run_check(snapshot, name, command))
                write_report(report_path, report)
        require_clean(root)
        if git(root, "rev-parse", "origin/main^{commit}") != base:
            raise ValueError("origin/main changed during validation; rerun checks.")
        report["completed"] = True
        report["success"] = all(check["success"] for check in report["checks"])
    except (OSError, ValueError, subprocess.CalledProcessError, tarfile.TarError) as exc:
        report["error"] = str(exc)
        print(str(exc), file=sys.stderr)
    except KeyboardInterrupt:
        report["error"] = "Validation interrupted."
        print(report["error"], file=sys.stderr)
    finally:
        report["finished_at"] = datetime.now(timezone.utc).isoformat()
        write_report(report_path, report)
    return report["success"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=PROFILES, default=REQUIRED_PROFILE)
    parser.add_argument("--commit", default="HEAD")
    parser.add_argument("--report", type=Path, default=ROOT / ".validation/report.json")
    parser.add_argument("--pre-push", action="store_true", help="Read Git pre-push ref updates from stdin")
    args = parser.parse_args()
    if args.pre_push:
        try:
            commits = parse_push_updates(sys.stdin.readlines())
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 1
        for commit in commits:
            if not validate(ROOT, commit, "bootstrap", ROOT / f".validation/push-{commit}.json"):
                return 1
        return 0
    return 0 if validate(ROOT, args.commit, args.profile, args.report.resolve()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
