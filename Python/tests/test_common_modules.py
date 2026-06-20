import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from common.data_loader import DataLoader
from common.feature_base import FeatureEngineer
from common.model_utils import ModelTrainer


def sample_ohlc() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "datetime": pd.date_range("2026-01-01", periods=6, freq="h"),
            "open": [1.0, 1.2, 1.1, 1.4, 1.6, 1.5],
            "high": [1.3, 1.4, 1.5, 1.7, 1.8, 1.9],
            "low": [0.9, 1.0, 1.0, 1.2, 1.4, 1.3],
            "close": [1.2, 1.1, 1.4, 1.6, 1.5, 1.8],
            "tick_volume": [100, 110, 120, 130, 140, 150],
        }
    )


class DataLoaderTests(unittest.TestCase):
    def test_instance_loads_csv(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "bars.csv"
            sample_ohlc().to_csv(path, index=False)

            df = DataLoader(csv_path=path).load(6)

        self.assertEqual(len(df), 6)
        self.assertIn("datetime", df.columns)
        self.assertTrue(pd.api.types.is_datetime64_any_dtype(df["datetime"]))

    def test_load_requires_source(self) -> None:
        with self.assertRaises(ValueError):
            DataLoader().load(10)


class FeatureEngineerTests(unittest.TestCase):
    def test_instance_helpers_return_expected_shapes(self) -> None:
        df = sample_ohlc()
        engineer = FeatureEngineer(df)

        self.assertEqual(len(engineer.atr(3)), len(df))
        self.assertEqual(len(engineer.distance_to_swing("high", 3)), len(df))
        self.assertEqual(len(engineer.consecutive_higher("high", 3)), len(df))
        self.assertEqual(len(engineer.consecutive_lower("low", 3)), len(df))
        self.assertIsInstance(engineer.percentile_rank(engineer.atr(3), 3, 3), float)
        self.assertIsInstance(engineer.bars_since_level_touch(4, 1.5, 3), int)
        self.assertIsInstance(engineer.count_structure_breaks(5, 3), int)
        self.assertIsInstance(engineer.consecutive_direction(5, "bullish"), int)

    def test_static_feature_helpers_remain_available(self) -> None:
        df = FeatureEngineer.add_returns(sample_ohlc())

        self.assertIn("return_1", df.columns)
        self.assertIn("return_3", df.columns)
        self.assertNotIn("close", FeatureEngineer.get_feature_names(df))


class ModelTrainerTests(unittest.TestCase):
    def test_static_evaluate_supports_multiclass_metrics(self) -> None:
        metrics = ModelTrainer.evaluate(
            np.array([0, 1, 2]),
            np.array([0, 2, 2]),
            task="classification",
            label_names=["down", "flat", "up"],
        )

        self.assertIn("f1_macro", metrics)
        self.assertIn("confusion_matrix", metrics)
        self.assertEqual(metrics["confusion_matrix"].shape, (3, 3))

    def test_static_evaluate_supports_regression_metrics(self) -> None:
        metrics = ModelTrainer.evaluate(
            np.array([1.0, 2.0, 3.0]),
            np.array([1.0, 2.5, 2.5]),
            task="regression",
        )

        self.assertIn("rmse", metrics)
        self.assertIn("mae", metrics)
        self.assertIn("r2", metrics)

    def test_legacy_instance_evaluate_and_importance(self) -> None:
        class DummyModel:
            feature_importances_ = np.array([0.1, 0.9])

            def predict(self, X):
                return np.array([0, 1, 1])

            def predict_proba(self, X):
                return np.array(
                    [
                        [0.8, 0.2],
                        [0.3, 0.7],
                        [0.2, 0.8],
                    ]
                )

        trainer = ModelTrainer(task="binary", seed=42)
        metrics = trainer.evaluate(
            DummyModel(),
            np.zeros((3, 2)),
            np.array([0, 1, 1]),
            label_names=["no", "yes"],
        )
        importance = trainer.feature_importance(DummyModel(), ["a", "b"])

        self.assertEqual(metrics["accuracy"], 1.0)
        self.assertEqual(importance[0][0], "b")


if __name__ == "__main__":
    unittest.main()
