"""Fail-closed checks for the cross-language example validation runner."""

from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import check_examples


class RequiredToolTests(unittest.TestCase):
    def test_missing_required_executable_is_a_failure(self):
        with (
            patch("check_examples.shutil.which", return_value=None),
            self.assertRaises(check_examples.ValidationError),
        ):
            check_examples.require_executable("missing-runtime")

    def test_installed_executable_returns_resolved_path(self):
        with patch("check_examples.shutil.which", return_value="/opt/runtime/bin/java"):
            self.assertEqual(
                check_examples.require_executable("java"), "/opt/runtime/bin/java"
            )


class CommandEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.command = ["sample-reader", "snapshot.json"]
        self.directory = Path("/workspace/example")

    def test_success_preserves_stdout_and_stderr_for_validation(self):
        completed = subprocess.CompletedProcess(self.command, 0, b"rows\n", b"notice\n")
        with patch("check_examples.subprocess.run", return_value=completed) as run:
            result = check_examples.run_command(self.command, self.directory, timeout=17)
        self.assertEqual(result.stdout, "rows\n")
        self.assertEqual(result.stderr, "notice\n")
        self.assertEqual(run.call_args.kwargs["cwd"], self.directory)
        self.assertEqual(run.call_args.kwargs["timeout"], 17)
        self.assertTrue(run.call_args.kwargs["capture_output"])
        self.assertFalse(run.call_args.kwargs["text"])
        self.assertFalse(run.call_args.kwargs["check"])

    def test_nonzero_exit_cannot_pass_a_positive_case(self):
        completed = subprocess.CompletedProcess(self.command, 3, b"", b"reader failed\n")
        with (
            patch("check_examples.subprocess.run", return_value=completed),
            self.assertRaises(check_examples.ValidationError),
        ):
            check_examples.run_command(self.command, self.directory)

    def test_zero_exit_cannot_pass_a_negative_case(self):
        completed = subprocess.CompletedProcess(self.command, 0, b"accepted invalid data\n", b"")
        with (
            patch("check_examples.subprocess.run", return_value=completed),
            self.assertRaises(check_examples.ValidationError),
        ):
            check_examples.run_command(
                self.command, self.directory, expect_success=False
            )

    def test_nonzero_exit_passes_an_expected_rejection(self):
        completed = subprocess.CompletedProcess(self.command, 2, b"", b"invalid snapshot\n")
        with patch("check_examples.subprocess.run", return_value=completed):
            result = check_examples.run_command(
                self.command, self.directory, expect_success=False
            )
        self.assertEqual(result.returncode, 2)

    def test_signal_exit_is_not_a_successful_input_rejection(self):
        completed = subprocess.CompletedProcess(self.command, -9, b"", b"killed\n")
        with patch("check_examples.subprocess.run", return_value=completed), self.assertRaises(
            check_examples.ValidationError
        ):
            check_examples.run_command(self.command, self.directory, expect_success=False)

    def test_timeout_cannot_be_mistaken_for_expected_rejection(self):
        for expect_success in (True, False):
            with (
                self.subTest(expect_success=expect_success),
                patch(
                    "check_examples.subprocess.run",
                    side_effect=subprocess.TimeoutExpired(self.command, 1),
                ),
                self.assertRaises(check_examples.ValidationError),
            ):
                check_examples.run_command(
                    self.command,
                    self.directory,
                    timeout=1,
                    expect_success=expect_success,
                )

    def test_launch_failure_cannot_be_mistaken_for_expected_rejection(self):
        for expect_success in (True, False):
            with (
                self.subTest(expect_success=expect_success),
                patch(
                    "check_examples.subprocess.run", side_effect=FileNotFoundError("absent")
                ),
                self.assertRaises(check_examples.ValidationError),
            ):
                check_examples.run_command(
                    self.command, self.directory, expect_success=expect_success
                )

    def test_crlf_output_is_preserved_and_rejected_against_lf_contract(self):
        completed = subprocess.CompletedProcess(self.command, 0, b"header\r\nrow\r\n", b"")
        with patch("check_examples.subprocess.run", return_value=completed):
            result = check_examples.run_command(self.command, self.directory)
        self.assertEqual(result.stdout, "header\r\nrow\r\n")
        with self.assertRaises(check_examples.ValidationError):
            check_examples.assert_output(result.stdout, "header\nrow\n", "sample")

    def test_invalid_utf8_on_either_stream_fails_validation(self):
        for stdout, stderr in ((b"invalid \xff", b""), (b"", b"invalid \xff")):
            for expect_success in (True, False):
                completed = subprocess.CompletedProcess(
                    self.command, 0 if expect_success else 2, stdout, stderr
                )
                with (
                    self.subTest(stdout=stdout, stderr=stderr, expect_success=expect_success),
                    patch("check_examples.subprocess.run", return_value=completed),
                    self.assertRaises(check_examples.ValidationError),
                ):
                    check_examples.run_command(
                        self.command, self.directory, expect_success=expect_success
                    )


class OutputEvidenceTests(unittest.TestCase):
    def test_exact_stdout_is_accepted(self):
        check_examples.assert_output("header\nrow\n", "header\nrow\n", "sample")

    def test_changed_row_missing_row_and_extra_logging_are_rejected(self):
        expected = "header\nrow\n"
        for actual in ("header\nwrong-row\n", "header\n", "debug\nheader\nrow\n"):
            with self.subTest(actual=actual), self.assertRaises(check_examples.ValidationError):
                check_examples.assert_output(actual, expected, "sample")


class UnitTestEvidenceTests(unittest.TestCase):
    def test_zero_tests_or_missing_evidence_never_pass(self):
        outputs = {
            "python": "Ran 0 tests in 0.001s\nOK\n",
            "typescript": "# pass 0\n# skipped 0\n",
            "go": '{"Action":"pass","Package":"example"}\n',
            "csharp": "C# snapshot reader: 0 checks passed\n",
            "rust": "test result: ok. 0 passed; 0 failed; 0 ignored;\n",
            "java": "Tests run: 0, Failures: 0, Errors: 0, Skipped: 0\n",
        }
        for language, output in outputs.items():
            for candidate in (output, "build succeeded without running tests"):
                with self.subTest(language=language, output=candidate), self.assertRaises(
                    check_examples.ValidationError
                ):
                    check_examples.require_unit_tests(language, candidate)

    def test_executed_tests_are_required_for_each_language(self):
        outputs = {
            "python": "Ran 2 tests in 0.001s\nOK\n",
            "typescript": "# pass 2\n# skipped 0\n",
            "go": '{"Action":"pass","Test":"TestSnapshot"}\n',
            "csharp": "C# snapshot reader: 2 checks passed\n",
            "rust": "test result: ok. 2 passed; 0 failed; 0 ignored;\n",
            "java": "Tests run: 2, Failures: 0, Errors: 0, Skipped: 0\n",
        }
        for language, output in outputs.items():
            with self.subTest(language=language):
                self.assertGreater(check_examples.require_unit_tests(language, output), 0)

    def test_skipped_tests_cannot_be_reported_as_complete(self):
        outputs = {
            "python": "Ran 2 tests in 0.001s\nOK (skipped=1)\n",
            "typescript": "# pass 2\n# skipped 1\n",
            "go": '{"Action":"pass","Test":"TestA"}\n{"Action":"skip","Test":"TestB"}\n',
            "rust": "test result: ok. 2 passed; 0 failed; 1 ignored;\n",
            "java": "Tests run: 2, Failures: 0, Errors: 0, Skipped: 1\n",
        }
        for language, output in outputs.items():
            with self.subTest(language=language), self.assertRaises(check_examples.ValidationError):
                check_examples.require_unit_tests(language, output)


class ReferenceOutputTests(unittest.TestCase):
    def setUp(self):
        self.snapshot = {
            "status": "READY",
            "symbol": "EURUSD",
            "timeframe": "M5",
            "as_of": "2026-09-18T12:00:00",
            "records": [
                {
                    "id": "z-fvg",
                    "concept": "FVG",
                    "direction": "bullish",
                    "state": "FRESH",
                    "lower": 1,
                    "upper": 1.25,
                },
                {
                    "id": "a-mss",
                    "concept": "MSS",
                    "direction": "bearish",
                    "state": "CONFIRMED",
                    "lower": 1.125,
                    "upper": 1.125,
                },
                {
                    "id": "b-fvg",
                    "concept": "FVG",
                    "direction": "bearish",
                    "state": "BROKEN",
                    "lower": 1.5,
                    "upper": 2,
                },
            ],
        }
        self.header = (
            "status=READY symbol=EURUSD timeframe=M5 "
            "as_of=2026-09-18T12:00:00 time_basis=broker\n"
        )

    def test_records_sort_by_id_and_prices_have_eight_decimal_places(self):
        expected = (
            self.header
            + "a-mss\tMSS\tbearish\tCONFIRMED\t1.12500000\t1.12500000\n"
            + "b-fvg\tFVG\tbearish\tBROKEN\t1.50000000\t2.00000000\n"
            + "z-fvg\tFVG\tbullish\tFRESH\t1.00000000\t1.25000000\n"
        )
        self.assertEqual(check_examples.expected_output(self.snapshot), expected)
        self.assertEqual(self.snapshot["records"][0]["id"], "z-fvg")

    def test_concept_and_direction_filters_apply_together(self):
        expected = self.header + "b-fvg\tFVG\tbearish\tBROKEN\t1.50000000\t2.00000000\n"
        self.assertEqual(
            check_examples.expected_output(self.snapshot, concept="FVG", direction="bearish"),
            expected,
        )

    def test_unknown_uppercase_concept_is_a_valid_empty_selection(self):
        self.assertEqual(
            check_examples.expected_output(self.snapshot, concept="SYNTHETIC_TEST"),
            self.header,
        )

    def test_no_matching_direction_still_emits_header(self):
        self.assertEqual(
            check_examples.expected_output(self.snapshot, direction="neutral"), self.header
        )

    def test_not_ready_snapshot_keeps_null_timestamp_visible(self):
        snapshot = self.snapshot | {"status": "NOT_READY", "as_of": None, "records": []}
        self.assertEqual(
            check_examples.expected_output(snapshot),
            "status=NOT_READY symbol=EURUSD timeframe=M5 as_of=null time_basis=broker\n",
        )

    def test_reference_rounds_binary64_ties_to_even_and_normalizes_zero(self):
        cases = [
            (0.001953125, "0.00195312"), (-0.001953125, "-0.00195312"),
            (0.005859375, "0.00585938"), (-0.005859375, "-0.00585938"),
            (1.000000005, "1.00000000"), (-1.000000005, "-1.00000000"),
            (-0.0, "0.00000000"), (-1e-12, "0.00000000"),
            (1e21, "1000000000000000000000.00000000"),
            (9007199254740993, "9007199254740992.00000000"),
        ]
        for value, expected in cases:
            snapshot = self.snapshot | {"records": [self.snapshot["records"][0] |
                        {"lower": value, "upper": value}]}
            with self.subTest(value=value):
                prices = check_examples.expected_output(snapshot).splitlines()[1].split("\t")[-2:]
                self.assertEqual(prices, [expected, expected])


if __name__ == "__main__":
    unittest.main()
