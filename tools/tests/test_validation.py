"""Regression checks for the local validation and publication boundary."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import check_all
import check_end_to_end
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
            "schema_version": check_all.REPORT_SCHEMA_VERSION, "profile": check_all.REQUIRED_PROFILE,
            "success": True, "completed": True, "commit_sha": HEAD, "base_sha": BASE,
            "profile_fingerprint": check_all.profile_fingerprint(check_all.ROOT, check_all.REQUIRED_PROFILE),
            "environment": {"python": "3.13.0"},
            "checks": [{"name": name, "command": command, "success": True, "returncode": 0}
                       for name, command in check_all.profile_commands(check_all.ROOT, check_all.REQUIRED_PROFILE)],
        }
        evidence = {
            "success": True, "completed": True,
            "languages": list(check_all.EXAMPLE_LANGUAGES), "snapshots": [{"sha256": "a" * 64}],
            "checks": [{"language": name, "success": True, "snapshots": 1, "assertions": 11}
                       for name in check_all.EXAMPLE_LANGUAGES],
            "versions": {name: "test-version" for name in
                         ("python", "node", "npm", "go", "dotnet", "cargo", "rustc", "mvn", "java",
                          "metaeditor_sha256", "terminal_sha256")},
        }
        next(check for check in self.report["checks"] if check["name"] == "mt5-examples")["evidence"] = evidence
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

    def test_fast_or_obsolete_profile_cannot_publish(self):
        for profile in ("fast", "bootstrap"):
            with self.subTest(profile=profile), self.assertRaises(ValueError):
                verify_report(self.report | {"profile": profile}, HEAD, BASE, self.pull)

    def test_changed_command_fingerprint_or_missing_version_cannot_publish(self):
        checks = copy.deepcopy(self.report["checks"])
        checks[-1]["command"].append("--skip-runtime")
        for changes in ({"checks": checks}, {"profile_fingerprint": "old-profile"}, {"environment": {}}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                verify_report(self.report | changes, HEAD, BASE, self.pull)

    def test_missing_or_incomplete_end_to_end_evidence_cannot_publish(self):
        original = self.report["checks"][-1]["evidence"]
        for evidence in (None, original | {"snapshots": []}, original | {"checks": original["checks"][:-1]},
                         original | {"versions": {}}):
            checks = copy.deepcopy(self.report["checks"])
            checks[-1]["evidence"] = evidence
            with self.subTest(evidence=evidence), self.assertRaises(ValueError):
                verify_report(self.report | {"checks": checks}, HEAD, BASE, self.pull)


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

    def test_profile_fingerprint_changes_with_commands_and_tool_contents(self):
        tools = self.root / "tools"
        tools.mkdir()
        checker = tools / "fixture.py"
        checker.write_text("print('version one')")
        with patch.dict(check_all.PROFILES, self.profile):
            first = check_all.profile_fingerprint(self.root, "fixture")
            checker.write_text("print('version two')")
            self.assertNotEqual(first, check_all.profile_fingerprint(self.root, "fixture"))
            checker.write_text("print('version one')")
            self.profile["fixture"][0][1].append("--different")
            self.assertNotEqual(first, check_all.profile_fingerprint(self.root, "fixture"))


class RuntimeArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.run = self.root / ("run-" + "a" * 32)
        self.run.mkdir()
        self.invocation = "b" * 32
        self.folder = self.run / self.invocation
        self.folder.mkdir()
        self.snapshot = self.folder / "snapshot-fixture.json"
        self.snapshot.write_text("{}")
        self.assertion_report = self.folder / "smc-test-report.json"
        self.result = {"source": "Tests/export.mq5", "run_id": self.invocation,
                       "suite": "snapshot_export", "assertions": 3, "failed": 0, "failures": [],
                       "artifacts": {"report": f"{self.invocation}/smc-test-report.json",
                                     "snapshot": f"{self.invocation}/snapshot-fixture.json",
                                     "snapshot_sha256": hashlib.sha256(b"{}").hexdigest()}}
        self.assertion_report.write_text(json.dumps(self.result))
        self.manifest = self.run / "manifest.json"
        self.write_manifest([self.result])

    def write_manifest(self, results):
        self.manifest.write_text(json.dumps({"tests": results}))

    def verify(self, started=0):
        return check_end_to_end.verified_snapshots(self.root, ["Tests/export.mq5"], started)

    def test_valid_export_is_bound_to_report_and_checksum(self):
        actual = self.verify()
        self.assertEqual(actual[0]["path"], str(self.snapshot))
        self.assertEqual(actual[0]["sha256"], self.result["artifacts"]["snapshot_sha256"])

    def test_missing_or_modified_export_is_rejected(self):
        self.snapshot.write_text('{"changed": true}')
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.verify()
        self.snapshot.unlink()
        with self.assertRaisesRegex(ValueError, "Missing"):
            self.verify()

    def test_zero_missing_duplicate_or_extra_fixtures_are_rejected(self):
        for results in ([], [self.result, self.result], [self.result | {"source": "Tests/other.mq5"}]):
            with self.subTest(results=results), self.assertRaises(ValueError):
                self.write_manifest(results)
                self.verify()

    def test_missing_or_multiple_manifests_are_rejected(self):
        self.manifest.unlink()
        with self.assertRaisesRegex(ValueError, "exactly one"):
            self.verify()
        self.write_manifest([self.result])
        second = self.root / ("run-" + "c" * 32)
        second.mkdir()
        (second / "manifest.json").write_text("{}")
        with self.assertRaisesRegex(ValueError, "exactly one"):
            self.verify()

    def test_stale_report_or_conflicting_assertions_are_rejected(self):
        self.assertion_report.write_text(json.dumps(self.result | {"assertions": 4}))
        with self.assertRaisesRegex(ValueError, "disagrees"):
            self.verify()
        self.assertion_report.write_text(json.dumps(self.result))
        os.utime(self.assertion_report, (0, 0))
        with self.assertRaisesRegex(ValueError, "Stale"):
            self.verify(started=1)

    def test_escaping_or_absent_snapshot_reference_is_rejected(self):
        for value in ("../outside.json", str(self.snapshot), None):
            result = copy.deepcopy(self.result)
            result["artifacts"]["snapshot"] = value
            self.write_manifest([result])
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.verify()

    def test_snapshot_cannot_be_borrowed_from_another_fixture(self):
        second = copy.deepcopy(self.result)
        second.update(source="Tests/export-other.mq5", run_id="c" * 32)
        folder = self.run / second["run_id"]
        folder.mkdir()
        report_path = folder / "smc-test-report.json"
        second["artifacts"]["report"] = f"{second['run_id']}/smc-test-report.json"
        report_path.write_text(json.dumps(second))
        self.write_manifest([self.result, second])
        with self.assertRaisesRegex(ValueError, "different runtime fixture"):
            check_end_to_end.verified_snapshots(
                self.root, [self.result["source"], second["source"]], 0)

    def test_symlinked_runtime_directory_cannot_escape_artifact_root(self):
        outer = self.root / "fresh"
        outer.mkdir()
        (outer / self.run.name).symlink_to(self.run, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "escapes"):
            check_end_to_end.verified_snapshots(outer, [self.result["source"]], 0)

    def test_each_language_is_built_once_for_multiple_generated_snapshots(self):
        root = self.root / "repository"
        fixtures = root / "tests/fixtures"
        fixtures.mkdir(parents=True)
        (fixtures / "snapshot-v1.expected.txt").write_text("expected\n")
        second = self.folder / "second.json"
        second.write_text("{}")
        snapshots = self.verify()
        snapshots.append(snapshots[0] | {"path": str(second)})
        helpers = SimpleNamespace(
            LANGUAGES=check_end_to_end.LANGUAGES, DEFAULT_TIMEOUT=300,
            load_snapshot=Mock(return_value={}), expected_output=Mock(return_value="expected\n"),
            assert_output=Mock(), prepare_language=Mock(return_value=["reader"]),
            verify_cli=Mock(return_value=11),
        )
        report = {"versions": {}, "checks": []}
        with patch.dict(sys.modules, {"check_examples": helpers}):
            check_end_to_end.check_readers(root, snapshots, report)
        self.assertEqual(helpers.prepare_language.call_count, 6)
        self.assertEqual(helpers.verify_cli.call_count, 12)
        self.assertEqual([check["snapshots"] for check in report["checks"]], [2] * 6)


if __name__ == "__main__":
    unittest.main()
