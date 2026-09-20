#!/usr/bin/env python3
"""Publish local/validation only for the pushed, freshly validated PR head."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

from check_all import PROFILES, REQUIRED_PROFILE, ROOT, git, require_clean


def verify_report(report: dict, head: str, base: str, pull: dict) -> None:
    if report.get("schema_version") != 1 or report.get("profile") != REQUIRED_PROFILE:
        raise ValueError(f"A current {REQUIRED_PROFILE} validation report is required.")
    if report.get("success") is not True or report.get("completed") is not True:
        raise ValueError("Validation failed or did not complete.")
    expected = [name for name, _ in PROFILES[REQUIRED_PROFILE]]
    checks = report.get("checks", [])
    if [check.get("name") for check in checks] != expected:
        raise ValueError("The report does not contain every required check.")
    if any(check.get("success") is not True or check.get("returncode") != 0 for check in checks):
        raise ValueError("A required check failed or was not run.")
    if report.get("commit_sha") != head or pull.get("head", {}).get("sha") != head:
        raise ValueError("Tested commit, local HEAD, and pushed PR head must match.")
    if report.get("base_sha") != base or pull.get("base", {}).get("sha") != base:
        raise ValueError("main changed; update the branch and rerun validation.")
    if pull.get("state") != "open" or pull.get("base", {}).get("ref") != "main":
        raise ValueError("An open pull request targeting main is required.")


def gh_json(*args: str) -> dict:
    return json.loads(subprocess.check_output(["gh", *args], cwd=ROOT, text=True))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pr", required=True, type=int, help="Open PR number in the origin repository")
    parser.add_argument("--report", type=Path, default=ROOT / ".validation/report.json")
    args = parser.parse_args()
    try:
        require_clean(ROOT)
        report = json.loads(args.report.read_text(encoding="utf-8"))
        subprocess.run(["git", "fetch", "origin", "main:refs/remotes/origin/main"], cwd=ROOT, check=True)
        head = git(ROOT, "rev-parse", "HEAD")
        base = git(ROOT, "rev-parse", "origin/main")
        origin = git(ROOT, "remote", "get-url", "origin")
        repository_info = gh_json("repo", "view", origin, "--json", "nameWithOwner,url")
        repository = repository_info["nameWithOwner"]
        hostname = urlparse(repository_info["url"]).hostname
        if not hostname:
            raise ValueError("Unable to resolve the origin GitHub host.")
        pull = gh_json("api", "--hostname", hostname, f"repos/{repository}/pulls/{args.pr}")
        verify_report(report, head, base, pull)
        subprocess.run(["git", "merge-base", "--is-ancestor", base, head], cwd=ROOT, check=True)
        require_clean(ROOT)
        if git(ROOT, "rev-parse", "HEAD") != head:
            raise ValueError("HEAD changed while checking the report.")
        subprocess.run([
            "gh", "api", "--hostname", hostname, "--method", "POST", f"repos/{repository}/statuses/{head}",
            "-f", "state=success", "-f", "context=local/validation",
            "-f", f"description=Local {REQUIRED_PROFILE} checks passed against main {base[:12]}",
        ], cwd=ROOT, check=True)
        print(f"Published local/validation for {head} (PR #{args.pr}).")
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as exc:
        print(f"Validation status was not published: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
