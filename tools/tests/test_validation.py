"""Regression checks for the local validation and publication boundary."""

from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import check_all
from publish_validation import verify_report


HEAD = "a" * 40
BASE = "b" * 40
ZERO = "0" * 40


class PushPolicyTests(unittest.TestCase):
    def test_main_destination_is_rejected_even_from_feature_ref(self):
        for source, sha in [("refs/heads/feature", HEAD), ("(delete)", ZERO)]:
            with self.subTest(source=source), self.assertRaises(ValueError):
                check_all.parse_push_updates([f"{source} {sha} refs/heads/main {BASE}"])

    def test_non_main_destinations_validate_each_unique_commit(self):
        updates = [f"refs/heads/main {HEAD} refs/heads/feature {BASE}",
                   f"refs/heads/other {HEAD} refs/heads/other {ZERO}",
                   f"(delete) {ZERO} refs/heads/old {BASE}"]
        self.assertEqual(check_all.parse_push_updates(updates), [HEAD])

    def test_malformed_update_is_rejected(self):
        with self.assertRaises(ValueError):
            check_all.parse_push_updates(["refs/heads/feature"])


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.report = {
            "schema_version": 1, "profile": check_all.REQUIRED_PROFILE,
            "success": True, "completed": True, "commit_sha": HEAD, "base_sha": BASE,
            "checks": [{"name": name, "success": True, "returncode": 0}
                       for name, _ in check_all.PROFILES[check_all.REQUIRED_PROFILE]],
        }
        self.pull = {"state": "open", "head": {"sha": HEAD},
                     "base": {"ref": "main", "sha": BASE}}

    def test_matching_complete_report_is_accepted(self):
        verify_report(self.report, HEAD, BASE, self.pull)

    def test_stale_or_mismatched_commit_is_rejected(self):
        cases = [({"commit_sha": "c" * 40}, HEAD, BASE, self.pull),
                 ({"base_sha": "c" * 40}, HEAD, BASE, self.pull),
                 ({}, "c" * 40, BASE, self.pull),
                 ({}, HEAD, "c" * 40, self.pull)]
        remote_mismatch = copy.deepcopy(self.pull)
        remote_mismatch["head"]["sha"] = "c" * 40
        cases.append(({}, HEAD, BASE, remote_mismatch))
        remote_base_changed = copy.deepcopy(self.pull)
        remote_base_changed["base"]["sha"] = "c" * 40
        cases.append(({}, HEAD, BASE, remote_base_changed))
        for changes, head, base, pull in cases:
            with self.subTest(changes=changes, head=head, base=base), self.assertRaises(ValueError):
                verify_report(self.report | changes, head, base, pull)

    def test_incomplete_failed_missing_or_foreign_profile_is_rejected(self):
        cases = [{"completed": False}, {"success": False}, {"profile": "unknown"},
                 {"checks": self.report["checks"][:-1]}]
        for result in (None, 1):
            checks = copy.deepcopy(self.report["checks"])
            checks[0]["returncode"] = result
            cases.append({"checks": checks})
        for changes in cases:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                verify_report(self.report | changes, HEAD, BASE, self.pull)

    def test_closed_or_other_base_pr_is_rejected(self):
        for pull in [self.pull | {"state": "closed"},
                     self.pull | {"base": {"ref": "develop", "sha": BASE}}]:
            with self.assertRaises(ValueError):
                verify_report(self.report, HEAD, BASE, pull)


class CommandTests(unittest.TestCase):
    def test_missing_tool_is_a_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            result = check_all.run_check(Path(directory), "missing", [str(Path(directory) / "absent")])
        self.assertFalse(result["success"])
        self.assertIsNone(result["returncode"])

    def test_nonzero_exit_is_a_failure(self):
        result = check_all.run_check(Path.cwd(), "failure", [sys.executable, "-c", "raise SystemExit(3)"])
        self.assertFalse(result["success"])
        self.assertEqual(result["returncode"], 3)


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Validation Test")
        self.git("config", "user.email", "validation@example.invalid")
        (self.root / ".gitignore").write_text(".validation/\n")
        (self.root / "value.txt").write_text("committed")
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")
        self.sha = self.git("rev-parse", "HEAD")
        self.git("update-ref", "refs/remotes/origin/main", self.sha)
        self.report_path = self.root / ".validation/report.json"
        command = [sys.executable, "-c",
                   "from pathlib import Path; assert Path('value.txt').read_text() == 'committed'; "
                   "assert not Path('.git').exists(); Path('build-artifact').write_text('ok')"]
        self.profile = {"fixture": [("snapshot", command)]}

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True).strip()

    def test_checks_run_in_exact_snapshot_without_touching_source(self):
        with patch.dict(check_all.PROFILES, self.profile):
            self.assertTrue(check_all.validate(self.root, self.sha, "fixture", self.report_path))
        report = json.loads(self.report_path.read_text())
        self.assertEqual(report["commit_sha"], self.sha)
        self.assertEqual(report["base_sha"], self.sha)
        self.assertTrue(report["completed"])
        self.assertFalse((self.root / "build-artifact").exists())
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_dirty_tree_invalidates_previous_success(self):
        self.report_path.parent.mkdir()
        self.report_path.write_text('{"success": true}')
        (self.root / "value.txt").write_text("uncommitted")
        with patch.dict(check_all.PROFILES, self.profile):
            self.assertFalse(check_all.validate(self.root, self.sha, "fixture", self.report_path))
        report = json.loads(self.report_path.read_text())
        self.assertFalse(report["success"])
        self.assertFalse(report["completed"])

    def test_missing_tool_cannot_complete_successfully(self):
        profile = {"fixture": [("missing", [str(self.root / "nonexistent-tool")])]}
        with patch.dict(check_all.PROFILES, profile):
            self.assertFalse(check_all.validate(self.root, self.sha, "fixture", self.report_path))
        report = json.loads(self.report_path.read_text())
        self.assertFalse(report["success"])
        self.assertIsNone(report["checks"][0]["returncode"])


if __name__ == "__main__":
    unittest.main()
