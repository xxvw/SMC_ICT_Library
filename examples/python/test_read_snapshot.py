"""Small contract tests, plus CLI checks against the shared language fixture."""

import io
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from copy import deepcopy
from pathlib import Path

from read_snapshot import (
    SnapshotError,
    load_snapshot,
    main,
    render_snapshot,
    validate_snapshot,
)

ROOT = Path(__file__).resolve().parents[2]


class SnapshotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = ROOT / "tests/fixtures/snapshot-v1.json"
        cls.snapshot = load_snapshot(cls.fixture)

    def test_shared_expected_output(self):
        expected = (ROOT / "tests/fixtures/snapshot-v1.expected.txt").read_text(encoding="utf-8")
        self.assertEqual(render_snapshot(self.snapshot), expected)

    def test_filters_and_sorting(self):
        snapshot = deepcopy(self.snapshot)
        snapshot["records"].reverse()
        self.assertEqual(render_snapshot(snapshot), render_snapshot(self.snapshot))
        filtered = render_snapshot(snapshot, "IFVG", "bearish").splitlines()
        self.assertEqual(len(filtered), 2)
        self.assertEqual(filtered[1].split("\t")[1:3], ["IFVG", "bearish"])
        self.assertEqual(len(render_snapshot(snapshot, "IFVG", "bullish").splitlines()), 1)

    def test_minor_versions_and_additive_fields(self):
        snapshot = deepcopy(self.snapshot)
        snapshot["schema_version"] = "1.99"
        snapshot["future_field"] = {"anything": True}
        snapshot["records"][0]["future_field"] = [1, 2]
        validate_snapshot(snapshot)

    def test_rejects_malformed_contract(self):
        mutations = [
            lambda x: x.pop("as_of"),
            lambda x: x.update(schema_version="2.0"),
            lambda x: x.update(status="UNKNOWN"),
            lambda x: x.update(as_of="2026-02-30T12:00:00"),
            lambda x: x.update(as_of="2026-09-18T12:00:00Z"),
            lambda x: x["config"].pop("enable_smt"),
            lambda x: x["config"].update(lookback_bars=True),
            lambda x: x["config"].update(lookback_bars=100001),
            lambda x: x["config"].update(enable_smt=True, smt_symbol=""),
            lambda x: x["config"].update(displacement_body_fraction=1.01),
            lambda x: x["config"]["sessions"][0].update(end_minute=1440),
            lambda x: x["modules"][0].update(truncated="false"),
            lambda x: x["records"][0].pop("active"),
            lambda x: x["records"][0].update(direction="long"),
            lambda x: x["records"][0].update(lower=float("nan")),
            lambda x: x["records"][0].update(reference_price=None),
            lambda x: x["records"][0].update(lower=99999, upper=1),
            lambda x: x["records"].append(deepcopy(x["records"][0])),
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                snapshot = deepcopy(self.snapshot)
                mutation(snapshot)
                with self.assertRaises(SnapshotError):
                    validate_snapshot(snapshot)

    def test_cli_success_and_error_streams(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            self.assertEqual(main([str(self.fixture), "--concept", "IFVG"]), 0)
        self.assertIn("\tIFVG\t", stdout.getvalue())
        self.assertEqual(stderr.getvalue(), "")
        with tempfile.TemporaryDirectory() as directory:
            malformed = Path(directory) / "bad.json"
            malformed.write_text('{"lower": NaN}', encoding="utf-8")
            stdout, stderr = io.StringIO(), io.StringIO()
            with redirect_stdout(stdout), redirect_stderr(stderr):
                self.assertEqual(main([str(malformed)]), 1)
            self.assertEqual(stdout.getvalue(), "")
            self.assertIn("error:", stderr.getvalue())

    def test_null_as_of_remains_explicit(self):
        snapshot = deepcopy(self.snapshot)
        snapshot.update(as_of=None, status="NOT_READY", records=[])
        validate_snapshot(snapshot)
        self.assertIn("as_of=null", render_snapshot(snapshot))


if __name__ == "__main__":
    unittest.main()
