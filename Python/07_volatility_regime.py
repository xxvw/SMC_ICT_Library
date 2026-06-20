"""
07_volatility_regime.py - ボラティリティレジーム分類 / Volatility Regime Classifier
=====================================================================================
RandomForest 4クラス分類: low / normal / high / extreme
Features: ATR比率, リターンボラティリティ, 出来高
Labels:  ボラティリティレジーム分類

RandomForest 4-class classifier that identifies the current volatility
regime to help size positions and filter trade setups.
"""
import sys
import os
import warnings
import numpy as np
import pandas as pd
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common.data_loader import DataLoader
from common.feature_base import FeatureEngineer
from common.model_utils import ModelTrainer
from common.paths import default_model_dir

warnings.filterwarnings("ignore")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CONFIG = {
    "symbol": "EURUSD",
    "timeframe": "M5",
    "n_bars": 100_000,
    "model_name": "volatility_regime_4c",
    "output_dir": str(default_model_dir()),
    # Regime thresholds (percentiles of ATR distribution)
    "low_pct": 25,
    "normal_pct": 60,
    "high_pct": 90,
    # ATR reference period
    "regime_atr_period": 14,
    "regime_ref_window": 500,  # rolling window to compute percentiles
    # Training
    "test_ratio": 0.2,
    "optuna_trials": 30,
    "random_seed": 42,
}

LABEL_MAP = {0: "low", 1: "normal", 2: "high", 3: "extreme"}

# ---------------------------------------------------------------------------
# Feature engineering
# ---------------------------------------------------------------------------
def create_features(df: pd.DataFrame) -> pd.DataFrame:
    """Build volatility-centric feature matrix."""
    fe = FeatureEngineer(df)
    # ATR features
    for p in [7, 14, 28, 50]:
        df[f"atr_{p}"] = fe.atr(p)
    df["atr_7_14_ratio"] = df["atr_7"] / df["atr_14"].replace(0, np.nan)
    df["atr_14_50_ratio"] = df["atr_14"] / df["atr_50"].replace(0, np.nan)
    df["atr_14_28_ratio"] = df["atr_14"] / df["atr_28"].replace(0, np.nan)
    # Returns-based volatility
    df["ret_1"] = df["close"].pct_change()
    for w in [5, 10, 20, 50]:
        df[f"ret_std_{w}"] = df["ret_1"].rolling(w).std()
    df["ret_std_5_20_ratio"] = df["ret_std_5"] / df["ret_std_20"].replace(0, np.nan)
    # Range-based features
    df["range_pct"] = (df["high"] - df["low"]) / df["close"]
    df["range_avg_10"] = df["range_pct"].rolling(10).mean()
    df["range_avg_50"] = df["range_pct"].rolling(50).mean()
    df["range_ratio"] = df["range_avg_10"] / df["range_avg_50"].replace(0, np.nan)
    # Body-to-range ratio (indecision indicator)
    df["body_range"] = abs(df["close"] - df["open"]) / (df["high"] - df["low"] + 1e-10)
    df["body_range_avg5"] = df["body_range"].rolling(5).mean()
    # Volume-based (tick_volume as proxy)
    if "tick_volume" in df.columns:
        df["vol_sma10"] = df["tick_volume"].rolling(10).mean()
        df["vol_sma50"] = df["tick_volume"].rolling(50).mean()
        df["vol_ratio"] = df["vol_sma10"] / df["vol_sma50"].replace(0, np.nan)
    else:
        df["vol_ratio"] = 1.0
    # Parkinson volatility estimator
    df["parkinson"] = np.sqrt((1 / (4 * np.log(2))) * (np.log(df["high"] / df["low"]) ** 2))
    df["parkinson_avg10"] = df["parkinson"].rolling(10).mean()
    return df

# ---------------------------------------------------------------------------
# Label creation
# ---------------------------------------------------------------------------
def create_labels(df: pd.DataFrame) -> pd.Series:
    """Classify volatility regime using rolling ATR percentile."""
    atr = df[f"atr_{CONFIG['regime_atr_period']}"]
    ref = CONFIG["regime_ref_window"]

    labels = pd.Series(1, index=df.index, name="label")  # default=normal
    for i in range(ref, len(df)):
        window = atr.iloc[i - ref:i]
        pct = (window < atr.iloc[i]).sum() / len(window) * 100
        if pct < CONFIG["low_pct"]:
            labels.iloc[i] = 0   # low
        elif pct < CONFIG["normal_pct"]:
            labels.iloc[i] = 1   # normal
        elif pct < CONFIG["high_pct"]:
            labels.iloc[i] = 2   # high
        else:
            labels.iloc[i] = 3   # extreme
    return labels

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("=" * 60)
    print(f" Volatility Regime — {CONFIG['symbol']} {CONFIG['timeframe']}")
    print(f" {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 60)

    loader = DataLoader(CONFIG["symbol"], CONFIG["timeframe"])
    df = loader.load(CONFIG["n_bars"])
    print(f"[DATA]  Loaded {len(df):,} bars")

    df = create_features(df)
    df["label"] = create_labels(df)
    df.dropna(inplace=True)
    feature_cols = [c for c in df.columns if c not in ["open", "high", "low", "close",
                                                         "tick_volume", "real_volume",
                                                         "spread", "time", "label",
                                                         "ret_1"]]
    X = df[feature_cols]
    y = df["label"]
    print(f"[FEAT]  {len(feature_cols)} features, {len(X):,} samples")
    print(f"[DIST]  {dict(y.value_counts().sort_index())}")

    split = int(len(X) * (1 - CONFIG["test_ratio"]))
    X_train, X_test = X.iloc[:split], X.iloc[split:]
    y_train, y_test = y.iloc[:split], y.iloc[split:]

    # Train RandomForest
    trainer = ModelTrainer(task="multiclass", num_class=4, seed=CONFIG["random_seed"])
    best_params = trainer.optimize_rf(X_train, y_train, n_trials=CONFIG["optuna_trials"])
    model = trainer.train_rf(X_train, y_train, best_params)

    metrics = trainer.evaluate(model, X_test, y_test, label_names=list(LABEL_MAP.values()))
    print(f"\n[EVAL]  Accuracy : {metrics['accuracy']:.4f}")
    print(f"[EVAL]  F1-macro : {metrics['f1_macro']:.4f}")
    print(f"[EVAL]  Confusion matrix:\n{metrics['confusion_matrix']}")

    importance = trainer.feature_importance(model, feature_cols, top_n=10)
    print("\n[IMP]   Top features:")
    for feat, score in importance:
        print(f"        {feat:30s} {score:.4f}")

    output_path = os.path.join(CONFIG["output_dir"], CONFIG["model_name"])
    os.makedirs(output_path, exist_ok=True)
    onnx_path = trainer.export_onnx(model, feature_cols, output_path)
    print(f"\n[ONNX]  Exported → {onnx_path}")

    print("\n" + "=" * 60)
    print(" Training complete.")
    print(f" Model : {CONFIG['model_name']}")
    print(f" ONNX  : {onnx_path}")
    print("=" * 60)

if __name__ == "__main__":
    main()
