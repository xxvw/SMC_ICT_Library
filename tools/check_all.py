#!/usr/bin/env python3
"""Validate an immutable commit locally; never publish a GitHub status."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import platform
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_PROFILE = "full"
REPORT_SCHEMA_VERSION = 2
EXAMPLE_LANGUAGES = ("python", "typescript", "go", "csharp", "rust", "java")
FAST_CHECKS = [
    ("python", [sys.executable, "tools/check_python.py"]),
    ("mql5-static", [sys.executable, "tools/check_mql5_static.py"]),
    ("validation-tests", [sys.executable, "-m", "unittest", "discover", "-s", "tools/tests"]),
    ("docs", [sys.executable, "tools/check_docs.py"]),
]
PROFILES = {
    "fast": FAST_CHECKS,
    "full": [
        *FAST_CHECKS,
        ("mql5-compile", [sys.executable, "tools/check_mql5_compile.py"]),
        ("mt5-examples", [sys.executable, "tools/check_end_to_end.py"]),
    ],
}


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=root, text=True).strip()


def require_clean(root: Path) -> None:
    if git(root, "status", "--porcelain", "--untracked-files=all"):
        raise ValueError("Commit or stash changes before validating or publishing.")


def profile_commands(root: Path, profile: str) -> list[tuple[str, list[str]]]:
    """Pass explicit documentation paths so the checker also works in archives."""
    commands = []
    for name, original in PROFILES[profile]:
        command = list(original)
        if name == "docs":
            if (root / ".git").exists():
                output = subprocess.check_output(
                    ["git", "ls-files", "-z", "--", "*.md", "*.markdown"], cwd=root,
                )
                documents = [path for path in output.decode().split("\0") if path]
            else:
                documents = [path.relative_to(root).as_posix() for path in root.rglob("*")
                             if path.is_file() and path.suffix in {".md", ".markdown"}]
            if not documents:
                raise ValueError("No Markdown documents found for the required link check.")
            command.extend(sorted(documents))
        commands.append((name, command))
    return commands


def normalized_command(command: list[str]) -> list[str]:
    return ["$PYTHON" if argument == sys.executable else argument for argument in command]


def profile_fingerprint(root: Path, profile: str) -> str:
    """Bind evidence to command definitions and the validation tools' contents."""
    files = sorted((root / "tools").rglob("*.py"))
    requirements = root / "requirements-dev.txt"
    if requirements.is_file():
        files.append(requirements)
    definition = {
        "schema_version": REPORT_SCHEMA_VERSION,
        "profile": profile,
        "commands": [(name, normalized_command(command)) for name, command in profile_commands(root, profile)],
        "tools": {path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in files},
    }
    return hashlib.sha256(json.dumps(definition, sort_keys=True).encode()).hexdigest()


def verify_end_to_end_evidence(evidence: dict) -> None:
    if not isinstance(evidence, dict) or evidence.get("success") is not True or evidence.get("completed") is not True:
        raise ValueError("End-to-end validation did not produce complete success evidence.")
    snapshots = evidence.get("snapshots")
    checks = evidence.get("checks")
    if not isinstance(snapshots, list) or not snapshots or not isinstance(checks, list):
        raise ValueError("End-to-end evidence has no generated snapshots or reader results.")
    if evidence.get("languages") != list(EXAMPLE_LANGUAGES) or [check.get("language") for check in checks] != list(EXAMPLE_LANGUAGES):
        raise ValueError("End-to-end evidence does not cover all six readers.")
    if any(check.get("success") is not True or check.get("snapshots") != len(snapshots)
           or type(check.get("assertions")) is not int or check["assertions"] <= 0 for check in checks):
        raise ValueError("A reader did not validate every generated snapshot.")
    versions = evidence.get("versions", {})
    required_versions = ("python", "node", "npm", "go", "dotnet", "cargo", "rustc", "mvn", "java",
                         "metaeditor_sha256", "terminal_sha256")
    if not isinstance(versions, dict) or any(not isinstance(versions.get(name), str) or not versions[name]
                                          for name in required_versions):
        raise ValueError("End-to-end evidence is missing required tool versions.")


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
        check = {"name": name, "command": command, "returncode": result.returncode,
                 "success": result.returncode == 0, "output": output[-12000:]}
        if name == "mt5-examples" and check["success"]:
            evidence = json.loads((root / ".validation/end-to-end.json").read_text(encoding="utf-8"))
            verify_end_to_end_evidence(evidence)
            check["evidence"] = evidence
        return check
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return {"name": name, "command": command, "returncode": None,
                "success": False, "output": str(exc)}


def write_report(path: Path, report: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def validate(root: Path, revision: str, profile: str, report_path: Path) -> bool:
    report = {"schema_version": REPORT_SCHEMA_VERSION, "profile": profile, "success": False,
              "completed": False, "checks": [],
              "environment": {"python": platform.python_version(), "python_executable": sys.executable,
                              "platform": platform.platform()},
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
            report["profile_fingerprint"] = profile_fingerprint(snapshot, profile)
            for name, command in profile_commands(snapshot, profile):
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
            if not validate(ROOT, commit, "fast", ROOT / f".validation/push-{commit}.json"):
                return 1
        return 0
    return 0 if validate(ROOT, args.commit, args.profile, args.report.resolve()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
