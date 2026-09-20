"""Interoperability checks for MT5 CSV exports and the legacy loader API."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from common import data_loader
from common.data_loader import DataLoader


def bars() -> pd.DataFrame:
    return pd.DataFrame({
        "datetime": ["2026-01-01 03:00:00", "2026-01-01 01:00:00", "2026-01-01 02:00:00"],
        "open": [12, 10, 11],
        "high": [14, 12, 13],
        "low": [11, 9, 10],
        "close": [13, 11, 12],
        "volume": [300, 100, 200],
        "rsi": [60.5, 40.5, 50.5],
    })


class CsvContractTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "bars.csv"

    def write(self, frame=None, encoding="utf-8"):
        (bars() if frame is None else frame).to_csv(self.path, index=False, encoding=encoding)

    def test_utf8_and_legacy_utf16_are_chronological_with_aliases(self):
        for encoding in ("utf-8", "utf-8-sig", "utf-16"):
            with self.subTest(encoding=encoding):
                self.write(encoding=encoding)
                result = DataLoader.load_from_csv(self.path)
                self.assertEqual(result["close"].tolist(), [11, 12, 13])
                self.assertEqual(result["tick_volume"].tolist(), [100, 200, 300])
                self.assertTrue(result["volume"].equals(result["tick_volume"]))
                self.assertEqual(result["rsi"].tolist(), [40.5, 50.5, 60.5])

    def test_tick_volume_alias_is_preserved(self):
        self.write(bars().rename(columns={"volume": "tick_volume"}))
        result = DataLoader.load_from_csv(self.path)
        self.assertTrue(result["volume"].equals(result["tick_volume"]))

    def test_instance_load_returns_recent_n_after_sorting(self):
        self.write()
        result = DataLoader(csv_path=self.path).load(2)
        self.assertEqual(result["close"].tolist(), [12, 13])
        self.assertEqual(result.index.tolist(), [0, 1])
        self.assertEqual(len(DataLoader(csv_path=self.path).load(100)), 3)

    def test_start_date_is_inclusive_upper_bound_like_mt5(self):
        self.write()
        result = DataLoader(csv_path=self.path).load(1, start_date=pd.Timestamp("2026-01-01 02:00:00"))
        self.assertEqual(result["close"].tolist(), [12])
        with self.assertRaisesRegex(ValueError, "No CSV bars"):
            DataLoader(csv_path=self.path).load(1, start_date=pd.Timestamp("2025-01-01"))

    def test_legacy_separate_date_time_columns(self):
        frame = bars()
        frame["date"] = frame["datetime"].str[:10]
        frame["time"] = frame.pop("datetime").str[11:]
        self.write(frame)
        self.assertEqual(DataLoader.load_from_csv(self.path)["datetime"].dt.hour.tolist(), [1, 2, 3])

    def test_legacy_time_column_and_normalized_headers(self):
        self.write(bars().rename(columns={"datetime": " Time ", "open": " OPEN "}))
        self.assertEqual(DataLoader.load_from_csv(self.path)["datetime"].dt.hour.tolist(), [1, 2, 3])

    def test_duplicate_or_missing_timestamps_rejected(self):
        for value in ("2026-01-01 01:00:00", None, "not-a-time"):
            with self.subTest(value=value):
                frame = bars()
                frame.loc[0, "datetime"] = value
                self.write(frame)
                with self.assertRaises(ValueError):
                    DataLoader.load_from_csv(self.path)

    def test_missing_ohlc_and_empty_inputs_rejected(self):
        for frame in (bars().drop(columns="close"), bars().drop(columns="datetime"), bars().iloc[:0]):
            self.write(frame)
            with self.assertRaises(ValueError):
                DataLoader.load_from_csv(self.path)

    def test_invalid_prices_and_volume_rejected(self):
        for column, value in (("high", 9), ("low", 20), ("close", np.inf), ("open", np.nan),
                              ("volume", -1), ("volume", 0.5), ("close", "bad")):
            with self.subTest(column=column, value=value):
                frame = bars().astype({column: object})
                frame.loc[0, column] = value
                self.write(frame)
                with self.assertRaises(ValueError):
                    DataLoader.load_from_csv(self.path)

    def test_conflicting_volume_aliases_rejected(self):
        frame = bars()
        frame["tick_volume"] = frame["volume"] + 1
        self.write(frame)
        with self.assertRaisesRegex(ValueError, "aliases disagree"):
            DataLoader.load_from_csv(self.path)

    def test_duplicate_normalized_columns_rejected(self):
        frame = bars()
        frame[" OPEN "] = frame["open"]
        self.write(frame)
        with self.assertRaisesRegex(ValueError, "Duplicate column"):
            DataLoader.load_from_csv(self.path)

    def test_exact_duplicate_headers_rejected_before_pandas_renames_them(self):
        self.path.write_text(
            "datetime,open,open,high,low,close\n"
            "2026-01-01 01:00:00,10,99,12,9,11\n",
            encoding="utf-8",
        )
        with self.assertRaisesRegex(ValueError, "Duplicate column"):
            DataLoader.load_from_csv(self.path)

    def test_invalid_requested_bar_count_rejected(self):
        self.write()
        for n_bars in (0, -1, True, 1.5):
            with self.subTest(n_bars=n_bars), self.assertRaises(ValueError):
                DataLoader(csv_path=self.path).load(n_bars)

    def test_missing_file_is_explicit(self):
        with self.assertRaises(FileNotFoundError):
            DataLoader.load_from_csv(self.path)


class Mt5ContractTests(unittest.TestCase):
    def terminal(self):
        mock = Mock()
        mock.initialize.return_value = True
        frame = bars().rename(columns={"volume": "tick_volume"})
        frame["time"] = pd.to_datetime(frame.pop("datetime")).astype("int64") // 10**9
        mock.copy_rates_from_pos.return_value = frame.to_records(index=False)
        mock.copy_rates_from.return_value = frame.to_records(index=False)
        return mock

    def test_completed_bars_use_same_validation_and_shutdown(self):
        terminal = self.terminal()
        with patch.object(data_loader, "_MT5_AVAILABLE", True), patch.object(data_loader, "mt5", terminal, create=True):
            result = DataLoader.load_from_mt5("TEST", "H1", 3)
        terminal.copy_rates_from_pos.assert_called_once_with("TEST", 16385, 1, 3)
        terminal.shutdown.assert_called_once()
        self.assertEqual(result["close"].tolist(), [11, 12, 13])
        self.assertIn("volume", result)

    def test_shutdown_on_invalid_or_missing_data(self):
        for returned in (None, []):
            terminal = self.terminal()
            terminal.copy_rates_from_pos.return_value = returned
            with patch.object(data_loader, "_MT5_AVAILABLE", True), patch.object(data_loader, "mt5", terminal, create=True):
                with self.assertRaises(RuntimeError):
                    DataLoader.load_from_mt5("TEST", "H1", 3)
            terminal.shutdown.assert_called_once()


class OptionalDependenciesTests(unittest.TestCase):
    def test_missing_ml_dependencies_leave_data_helpers_available(self):
        # A fresh interpreter avoids modules cached by the full validation suite.
        script = """
import importlib.abc
import sys
class NoML(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path=None, target=None):
        if fullname.split('.')[0] == 'sklearn':
            raise ModuleNotFoundError('scikit-learn deliberately unavailable')
sys.meta_path.insert(0, NoML())
from common import DataLoader, FeatureEngineer
assert callable(DataLoader) and callable(FeatureEngineer)
assert 'common.model_utils' not in sys.modules
try:
    from common import ModelTrainer
except ModuleNotFoundError:
    pass
else:
    raise AssertionError('ML dependency should be unavailable')
from common import DataLoader as StillAvailable
assert StillAvailable is DataLoader
"""
        result = subprocess.run(
            [sys.executable, "-c", script],
            cwd=Path(__file__).resolve().parents[1],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


class SharedValidationTests(unittest.TestCase):
    def test_invalid_splits_rejected(self):
        for train, val in ((0, 0.2), (0.9, 0.2), (0.8, 0.2), (0.8, -0.1), (np.nan, 0.1)):
            with self.subTest(train=train, val=val), self.assertRaises(ValueError):
                DataLoader.train_val_test_split(bars(), train, val)

    def test_invalid_sequence_parameters_rejected(self):
        for length, target in ((0, 0), (-1, 0), (True, 0), (2, -1), (2, 3)):
            with self.subTest(length=length, target=target), self.assertRaises(ValueError):
                DataLoader.create_sequences(np.ones((5, 3)), length, target)


if __name__ == "__main__":
    unittest.main()
