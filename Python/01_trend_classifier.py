"""
01_trend_classifier.py - トレンド分類器 / Trend Classifier
============================================================
LightGBM 3クラス分類: 上昇(bullish) / 下降(bearish) / レンジ(ranging)
Features: リターン, ボラティリティ, SMC特徴量
Labels:  将来N本のバー方向に基づく (up/down/flat - 閾値ベース)

LightGBM 3-class classifier for market trend direction.
Uses returns, volatility, and SMC-derived features to predict
whether the next N bars will be bullish, bearish, or ranging.
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
    "model_name": "trend_classifier_3c",
    "output_dir": str(default_model_dir()),
    # Label parameters
    "future_bars": 12,          # look-ahead window for labelling
    "trend_threshold": 0.0003,  # ±threshold → bullish/bearish; inside → ranging
    # Training
    "test_ratio": 0.2,
    "optuna_trials": 30,
    "random_seed": 42,
}

LABEL_MAP = {0: "bearish", 1: "ranging", 2: "bullish"}

# ---------------------------------------------------------------------------
# Feature engineering
# ---------------------------------------------------------------------------
def create_features(df: pd.DataFrame) -> pd.DataFrame:
    """Build feature matrix from OHLCV data."""
    fe = FeatureEngineer(df)
    # Returns & momentum
    for p in [1, 3, 5, 10, 20]:
        df[f"return_{p}"] = df["close"].pct_change(p)
    # Volatility proxies
    df["atr_14"] = fe.atr(14)
    df["atr_50"] = fe.atr(50)
    df["atr_ratio"] = df["atr_14"] / df["atr_50"].replace(0, np.nan)
    df["range_body_ratio"] = (df["high"] - df["low"]) / (abs(df["close"] - df["open"]) + 1e-10)
    # Rolling statistics
    for w in [10, 20, 50]:
        df[f"sma_{w}"] = df["close"].rolling(w).mean()
        df[f"std_{w}"] = df["close"].rolling(w).std()
    df["price_vs_sma20"] = (df["close"] - df["sma_20"]) / df["sma_20"].replace(0, np.nan)
    df["price_vs_sma50"] = (df["close"] - df["sma_50"]) / df["sma_50"].replace(0, np.nan)
    # SMC-inspired features
    df["swing_high_dist"] = fe.distance_to_swing("high", 20)
    df["swing_low_dist"] = fe.distance_to_swing("low", 20)
    df["higher_highs"] = fe.consecutive_higher("high", 5)
    df["lower_lows"] = fe.consecutive_lower("low", 5)
    return df

# ---------------------------------------------------------------------------
# Label creation
# ---------------------------------------------------------------------------
def create_labels(df: pd.DataFrame) -> pd.Series:
    """Label each bar: 0=bearish, 1=ranging, 2=bullish."""
    future_ret = df["close"].shift(-CONFIG["future_bars"]) / df["close"] - 1
    labels = pd.Series(1, index=df.index, name="label")  # default = ranging
    labels[future_ret > CONFIG["trend_threshold"]] = 2    # bullish
    labels[future_ret < -CONFIG["trend_threshold"]] = 0   # bearish
    return labels

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("=" * 60)
    print(f" Trend Classifier — {CONFIG['symbol']} {CONFIG['timeframe']}")
    print(f" {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 60)

    # 1. Load data
    loader = DataLoader(CONFIG["symbol"], CONFIG["timeframe"])
    df = loader.load(CONFIG["n_bars"])
    print(f"[DATA]  Loaded {len(df):,} bars")

    # 2. Features & labels
    df = create_features(df)
    df["label"] = create_labels(df)
    df.dropna(inplace=True)
    feature_cols = [c for c in df.columns if c not in ["open", "high", "low", "close",
                                                         "tick_volume", "real_volume",
                                                         "spread", "time", "label"]]
    X, y = df[feature_cols], df["label"]
    print(f"[FEAT]  {len(feature_cols)} features, {len(X):,} samples")
    print(f"[DIST]  {dict(y.value_counts().sort_index())}")

    # 3. Train/test split (time-series aware)
    split = int(len(X) * (1 - CONFIG["test_ratio"]))
    X_train, X_test = X.iloc[:split], X.iloc[split:]
    y_train, y_test = y.iloc[:split], y.iloc[split:]

    # 4. Train with optional Optuna HPO
    trainer = ModelTrainer(task="multiclass", num_class=3, seed=CONFIG["random_seed"])
    best_params = trainer.optimize_lgbm(X_train, y_train, n_trials=CONFIG["optuna_trials"])
    model = trainer.train_lgbm(X_train, y_train, best_params)

    # 5. Evaluate
    metrics = trainer.evaluate(model, X_test, y_test, label_names=list(LABEL_MAP.values()))
    print(f"\n[EVAL]  Accuracy : {metrics['accuracy']:.4f}")
    print(f"[EVAL]  F1-macro : {metrics['f1_macro']:.4f}")
    print(f"[EVAL]  Confusion matrix:\n{metrics['confusion_matrix']}")

    # 6. Feature importance
    importance = trainer.feature_importance(model, feature_cols, top_n=10)
    print("\n[IMP]   Top-10 features:")
    for feat, score in importance:
        print(f"        {feat:30s} {score:.4f}")

    # 7. Export to ONNX
    output_path = os.path.join(CONFIG["output_dir"], CONFIG["model_name"])
    os.makedirs(output_path, exist_ok=True)
    onnx_path = trainer.export_onnx(model, feature_cols, output_path)
    print(f"\n[ONNX]  Exported → {onnx_path}")

    # 8. Summary
    print("\n" + "=" * 60)
    print(" Training complete.")
    print(f" Model : {CONFIG['model_name']}")
    print(f" ONNX  : {onnx_path}")
    print("=" * 60)

if __name__ == "__main__":
    main()
