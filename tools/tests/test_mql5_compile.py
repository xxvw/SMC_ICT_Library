"""Compiler evidence tests; no installed MetaEditor or Wine is needed."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

from tools.check_mql5_compile import (
    Compiler,
    collect_sources,
    compile_source,
    decode_log,
    verify_compilation,
)


class CompilationEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.source = self.root / "sample.mq5"
        self.source.write_text("void OnStart() {}", encoding="utf-8")
        self.log = self.source.with_suffix(".log")
        self.artifact = self.source.with_suffix(".ex5")
        self.started = float(int(time.time()))
        self.compiler = Compiler(self.root / "MetaEditor64.exe", self.root / "Include")

    def evidence(self, summary="Result: 0 errors, 0 warnings", binary=True):
        self.log.write_text(summary, encoding="utf-16")
        if binary:
            self.artifact.write_bytes(b"fresh compiled output")

    def test_utf16_bom_and_unmarked_utf16_logs(self):
        message = "Result: 0 errors, 2 warnings"
        self.assertEqual(decode_log(message.encode("utf-16")), message)
        self.assertEqual(decode_log(message.encode("utf-16-le")), message)
        self.assertEqual(decode_log(message.encode("utf-8-sig")), message)

    def test_fresh_compilation_with_warnings(self):
        self.evidence("Result: 0 errors, 2 warnings, 250 msec elapsed")
        self.assertEqual(verify_compilation(self.log, self.artifact, self.started), (0, 2))

    def test_exit_zero_does_not_hide_compiler_errors(self):
        def run(*args, **kwargs):
            self.evidence("sample.mq5(1,1): error 149: unexpected token\nResult: 1 errors, 0 warnings", binary=False)
            return subprocess.CompletedProcess(args[0], 0, b"", b"")

        with patch("tools.check_mql5_compile.subprocess.run", side_effect=run):
            with self.assertRaisesRegex(RuntimeError, "MetaEditor reported 1 error"):
                compile_source(self.compiler, self.source, self.root, 5)

    def test_nonzero_exit_with_fresh_successful_evidence_passes(self):
        def run(*args, **kwargs):
            self.evidence()
            return subprocess.CompletedProcess(args[0], 1, b"", b"")

        with patch("tools.check_mql5_compile.subprocess.run", side_effect=run):
            self.assertEqual(compile_source(self.compiler, self.source, self.root, 5), 0)

    def test_previous_log_and_binary_are_removed_before_invocation(self):
        self.evidence()

        def run(*args, **kwargs):
            self.assertFalse(self.log.exists())
            self.assertFalse(self.artifact.exists())
            self.assertNotIn("/s", args[0])
            return subprocess.CompletedProcess(args[0], 0, b"", b"")

        with patch("tools.check_mql5_compile.subprocess.run", side_effect=run):
            with self.assertRaisesRegex(RuntimeError, "Missing compilation log"):
                compile_source(self.compiler, self.source, self.root, 5)

    def test_missing_log_fails(self):
        self.artifact.write_bytes(b"binary")
        with self.assertRaisesRegex(RuntimeError, "Missing compilation log"):
            verify_compilation(self.log, self.artifact, self.started)

    def test_missing_or_empty_binary_fails(self):
        self.evidence(binary=False)
        with self.assertRaisesRegex(RuntimeError, "Missing or empty EX5"):
            verify_compilation(self.log, self.artifact, self.started)
        self.artifact.touch()
        with self.assertRaisesRegex(RuntimeError, "Missing or empty EX5"):
            verify_compilation(self.log, self.artifact, self.started)

    def test_stale_log_fails_even_if_binary_is_fresh(self):
        self.evidence()
        os.utime(self.log, (self.started - 60, self.started - 60))
        with self.assertRaisesRegex(RuntimeError, "Stale compilation log"):
            verify_compilation(self.log, self.artifact, self.started)

    def test_stale_binary_fails_even_if_log_is_fresh(self):
        self.evidence()
        os.utime(self.artifact, (self.started - 60, self.started - 60))
        with self.assertRaisesRegex(RuntimeError, "Stale EX5 artifact"):
            verify_compilation(self.log, self.artifact, self.started)

    def test_truncated_log_without_summary_fails(self):
        self.evidence("compiling sample.mq5\ngenerating code 50%")
        with self.assertRaisesRegex(RuntimeError, "no result summary"):
            verify_compilation(self.log, self.artifact, self.started)

    def test_timeout_fails(self):
        with patch("tools.check_mql5_compile.subprocess.run", side_effect=subprocess.TimeoutExpired("MetaEditor", 5)):
            with self.assertRaisesRegex(RuntimeError, "timed out"):
                compile_source(self.compiler, self.source, self.root, 5)


class SourceDiscoveryTests(unittest.TestCase):
    def test_default_includes_all_entrypoints_and_nested_tests(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            expected = [Path("Experts/EA.mq5"), Path("Indicators/View.mq5"), Path("Scripts/Export.mq5"), Path("Tests/nested/Suite.mq5")]
            for path in expected:
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                (root / path).touch()
            self.assertEqual(collect_sources(root, []), expected)
            self.assertEqual(collect_sources(root, ["Tests/nested/Suite.mq5"]), [expected[-1]])

    def test_selected_source_must_be_an_existing_repository_entrypoint(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for invalid in ("../outside.mq5", "Experts/missing.mq5", "Include/header.mqh"):
                with self.subTest(invalid=invalid), self.assertRaises(RuntimeError):
                    collect_sources(root, [invalid])

    @unittest.skipIf(os.name == "nt", "Wine drive mapping is only used on Unix")
    def test_wine_mapping_prefers_most_specific_actual_drive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prefix = root / "prefix"
            (prefix / "dosdevices").mkdir(parents=True)
            (prefix / "drive_c").mkdir()
            (prefix / "dosdevices/z:").symlink_to("/")
            (prefix / "dosdevices/c:").symlink_to("../drive_c")
            compiler = Compiler(root / "editor", root / "includes", root / "wine", prefix)
            self.assertEqual(compiler.windows_path(prefix / "drive_c/Program Files/MetaEditor64.exe"), r"C:\Program Files\MetaEditor64.exe")
            self.assertTrue(compiler.windows_path(root / "stage/Source.mq5").startswith("Z:\\"))


if __name__ == "__main__":
    unittest.main()
