"""Failure regressions for evidence returned by the real MQL5 runtime."""

from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
spec = importlib.util.spec_from_file_location("run_mql5_tests", TOOLS / "run_mql5_tests.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.report = self.root / runtime.REPORT_NAME
        self.valid = {"run_id": "current", "suite": "fixture", "assertions": 3,
                      "failed": 0, "failures": []}

    def write_report(self, value):
        self.report.write_text(json.dumps(value), encoding="utf-8")

    def test_valid_current_report(self):
        self.write_report(self.valid)
        self.assertEqual(runtime.verify_report(self.report, "current", 0), self.valid)

    def test_missing_stale_and_wrong_run_reports(self):
        with self.assertRaisesRegex(RuntimeError, "fresh report"):
            runtime.verify_report(self.report, "current", 0)
        self.write_report(self.valid)
        os.utime(self.report, (1, 1))
        with self.assertRaisesRegex(RuntimeError, "fresh report"):
            runtime.verify_report(self.report, "current", 2)
        with self.assertRaisesRegex(RuntimeError, "this test invocation"):
            runtime.verify_report(self.report, "different", 0)

    def test_empty_or_malformed_report_never_passes(self):
        variants = [[], None, True, {}, {**self.valid, "suite": ""},
                    {**self.valid, "suite": False}, {**self.valid, "assertions": 2},
                    {**self.valid, "assertions": True}, {**self.valid, "assertions": 3.0},
                    {**self.valid, "failed": False}, {**self.valid, "failed": -1},
                    {**self.valid, "failures": {}}, {**self.valid, "failed": 1},
                    {**self.valid, "failures": ["failure"]}]
        for field in self.valid:
            variants.append({key: value for key, value in self.valid.items() if key != field})
        for value in variants:
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                self.write_report(value)
                runtime.verify_report(self.report, "current", 0)

    def test_invalid_json_and_duplicate_properties_rejected(self):
        for data in [b"{", b"\xff", b'{"run_id":NaN}', b'{"run_id":"old","run_id":"current"}']:
            with self.subTest(data=data), self.assertRaises(RuntimeError):
                self.report.write_bytes(data)
                runtime.verify_report(self.report, "current", 0)

    def test_default_discovery_contains_all_nested_mql5_tests(self):
        tests = self.root / "Tests"
        (tests / "nested").mkdir(parents=True)
        (tests / "SmokeTest.mq5").touch()
        (tests / "nested/TestCustom.mq5").touch()
        (tests / "TestHarness.mqh").touch()
        with patch.object(runtime, "ROOT", self.root):
            self.assertEqual(runtime.collect_tests([]), [Path("SmokeTest.mq5"), Path("nested/TestCustom.mq5")])
            with self.assertRaises(RuntimeError):
                runtime.collect_tests(["../outside.mq5"])

    def test_partial_failure_never_publishes_artifact_manifest(self):
        for folder in ("Include", "Tests", "standard-includes"):
            (self.root / folder).mkdir()
        for name in ("First.mq5", "Second.mq5"):
            (self.root / "Tests" / name).touch()
        compiler = Mock(includes=self.root / "standard-includes")
        with patch.object(runtime, "ROOT", self.root), \
             patch.object(runtime, "discover_compiler", return_value=compiler), \
             patch.object(runtime, "discover_runtime", return_value=(self.root / "terminal.exe", self.root / "symbols.dat")), \
             patch.object(runtime, "compile_source"), \
             patch.object(runtime, "run_test", side_effect=[self.valid, RuntimeError("second test failed")]), \
             patch("sys.stdout", new_callable=io.StringIO), \
             patch("sys.stderr", new_callable=io.StringIO):
            self.assertEqual(runtime.main(["--artifacts", str(self.root / "artifacts")]), 1)
        self.assertEqual(list((self.root / "artifacts").rglob("manifest.json")), [])


class SnapshotBridgeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.fixture = self.root / runtime.SNAPSHOT_NAME
        self.schema = self.root / "snapshot.schema.json"
        self.schema.write_text(json.dumps({"$schema": "https://json-schema.org/draft/2020-12/schema",
                                          "type": "object", "required": ["symbol"],
                                          "properties": {"symbol": {"type": "string", "minLength": 1}}}), encoding="utf-8")
        self.data = '{"symbol":"ユーロ/円"}\n'.encode("utf-8")
        self.fixture.write_bytes(self.data)

    def test_exact_valid_utf8_bytes_returned(self):
        self.assertEqual(runtime.verify_snapshot_fixture(self.fixture, self.schema, 0), self.data)

    def test_missing_and_stale_snapshot_rejected(self):
        os.utime(self.fixture, (1, 1))
        with self.assertRaisesRegex(RuntimeError, "fresh snapshot"):
            runtime.verify_snapshot_fixture(self.fixture, self.schema, 2)
        self.fixture.unlink()
        with self.assertRaisesRegex(RuntimeError, "fresh snapshot"):
            runtime.verify_snapshot_fixture(self.fixture, self.schema, 0)

    def test_missing_or_invalid_schema_is_not_skipped(self):
        self.schema.unlink()
        with self.assertRaisesRegex(RuntimeError, "Schema is required"):
            runtime.verify_snapshot_fixture(self.fixture, self.schema, 0)
        self.schema.write_text('{"type":"not-a-json-type"}')
        with self.assertRaisesRegex(RuntimeError, "Schema validation"):
            runtime.verify_snapshot_fixture(self.fixture, self.schema, 0)

    def test_missing_jsonschema_is_not_skipped(self):
        with patch.dict(sys.modules, {"jsonschema": None}), self.assertRaisesRegex(RuntimeError, "jsonschema is required"):
            runtime.verify_snapshot_fixture(self.fixture, self.schema, 0)

    def test_malformed_or_schema_invalid_snapshots_rejected(self):
        invalid = [b"\xef\xbb\xbf" + self.data, self.data + b"\x00", b"\xff", b"{",
                   b'{"symbol":NaN}', b'{"symbol":"A","unexpected":1e9999}',
                   b'{"symbol":"A","symbol":"B"}',
                   b'{}', b'[]', b'{"symbol":123}', b'{"symbol":""}']
        for data in invalid:
            with self.subTest(data=data), self.assertRaises(RuntimeError):
                self.fixture.write_bytes(data)
                runtime.verify_snapshot_fixture(self.fixture, self.schema, 0)

    def test_artifacts_preserve_exact_bytes_and_never_overwrite(self):
        stage = self.root / "terminal"
        files = stage / "MQL5/Files"
        files.mkdir(parents=True)
        report_bytes = b'{"run_id":"current"}\n'
        (files / runtime.REPORT_NAME).write_bytes(report_bytes)
        destination = self.root / "artifacts"
        result = runtime.preserve_artifacts(stage, {"run_id": "current"}, destination, self.data)
        self.assertEqual((destination / result["report"]).read_bytes(), report_bytes)
        self.assertEqual((destination / result["snapshot"]).read_bytes(), self.data)
        self.assertEqual(result["snapshot_sha256"], hashlib.sha256(self.data).hexdigest())
        with self.assertRaises(FileExistsError):
            runtime.preserve_artifacts(stage, {"run_id": "current"}, destination, self.data)

    def test_smoke_artifact_has_no_snapshot_dependency(self):
        stage = self.root / "terminal"
        files = stage / "MQL5/Files"
        files.mkdir(parents=True)
        (files / runtime.REPORT_NAME).write_text('{}')
        result = runtime.preserve_artifacts(stage, {"run_id": "smoke"}, self.root / "out", None)
        self.assertEqual(set(result), {"report"})


if __name__ == "__main__":
    unittest.main()
