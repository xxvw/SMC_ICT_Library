"""
05_liquidity_sweep_predictor.py - 流動性スイープ予測 / Liquidity Sweep Predictor
==================================================================================
XGBoost 2クラス分類: 等しい高値/安値のスイープが発生するか予測
Features: 等値H/L近接度, タッチ回数, ボラティリティ, トレンド
Labels:  N本以内にスイープが発生するか (0/1)

XGBoost binary classifier predicting whether equal highs/lows
(liquidity pools) will be swept within the next N bars.
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
    "model_name": "liquidity_sweep_pred",
    "output_dir": str(default_model_dir()),
    # Liquidity detection
    "equal_tolerance_pips": 2.0,  # pips tolerance for "equal" levels
    "lookback": 50,               # bars to look back for equal levels
    "min_touches": 2,             # minimum touches to form liquidity
    "sweep_window": 20,           # bars to check for sweep
    # Training
    "test_ratio": 0.2,
    "optuna_trials": 30,
    "random_seed": 42,
}

# ---------------------------------------------------------------------------
# Liquidity pool detection
# ---------------------------------------------------------------------------
def detect_liquidity_pools(df: pd.DataFrame, pip_size: float = 0.0001) -> pd.DataFrame:
    """Detect equal highs and equal lows forming liquidity pools."""
    tol = CONFIG["equal_tolerance_pips"] * pip_size
    lb = CONFIG["lookback"]
    records = []
    high = df["high"].values
    low = df["low"].values

    for i in range(lb, len(df) - CONFIG["sweep_window"]):
        # Equal highs
        touches_h = 0
        level_h = high[i]
        for j in range(i - lb, i):
            if abs(high[j] - level_h) <= tol:
                touches_h += 1
        if touches_h >= CONFIG["min_touches"]:
            records.append({
                "idx": i, "type": "EQH", "level": level_h,
                "touches": touches_h, "direction": 1,
            })

        # Equal lows
        touches_l = 0
        level_l = low[i]
        for j in range(i - lb, i):
            if abs(low[j] - level_l) <= tol:
                touches_l += 1
        if touches_l >= CONFIG["min_touches"]:
            records.append({
                "idx": i, "type": "EQL", "level": level_l,
                "touches": touches_l, "direction": -1,
            })
    return pd.DataFrame(records)

# ---------------------------------------------------------------------------
# Feature engineering
# ---------------------------------------------------------------------------
def create_features(df: pd.DataFrame, pools: pd.DataFrame) -> pd.DataFrame:
    """Build features for each liquidity pool."""
    fe = FeatureEngineer(df)
    atr14 = fe.atr(14)
    atr50 = fe.atr(50)
    sma20 = df["close"].rolling(20).mean()
    sma50 = df["close"].rolling(50).mean()
    rows = []

    for _, pool in pools.iterrows():
        i = int(pool["idx"])
        if i < 60:
            continue
        level = pool["level"]
        price = df["close"].iloc[i]
        row = {
            "pool_type": 1 if pool["type"] == "EQH" else -1,
            "touch_count": pool["touches"],
            "distance_to_level_atr": abs(price - level) / (atr14.iloc[i] + 1e-10),
            "distance_to_level_pips": abs(price - level),
            "atr_ratio": atr14.iloc[i] / (atr50.iloc[i] + 1e-10),
            "vol_expanding": 1 if atr14.iloc[i] > atr50.iloc[i] else 0,
            "trend_sma": (sma20.iloc[i] - sma50.iloc[i]) / (atr14.iloc[i] + 1e-10),
            "return_5": (df["close"].iloc[i] / df["close"].iloc[i - 5]) - 1,
            "return_10": (df["close"].iloc[i] / df["close"].iloc[i - 10]) - 1,
            "return_20": (df["close"].iloc[i] / df["close"].iloc[i - 20]) - 1,
            "momentum_toward": pool["direction"] * ((df["close"].iloc[i] - df["close"].iloc[i - 5]) / (atr14.iloc[i] + 1e-10)),
            "range_compression": (df["high"].iloc[i - 10:i].max() - df["low"].iloc[i - 10:i].min()) / (df["high"].iloc[i - 50:i].max() - df["low"].iloc[i - 50:i].min() + 1e-10),
            "bars_since_last_touch": fe.bars_since_level_touch(i, level, CONFIG["lookback"]),
            "bar_idx": i,
        }
        rows.append(row)
    return pd.DataFrame(rows)

# ---------------------------------------------------------------------------
# Label creation
# ---------------------------------------------------------------------------
def create_labels(df: pd.DataFrame, feat_df: pd.DataFrame, pools: pd.DataFrame) -> pd.Series:
    """Label = 1 if liquidity pool swept within window, else 0."""
    labels = []
    pool_idx = 0
    for _, row in feat_df.iterrows():
        i = int(row["bar_idx"])
        pool = pools[pools["idx"] == i].iloc[0]
        level = pool["level"]
        swept = 0
        for j in range(i + 1, min(i + CONFIG["sweep_window"] + 1, len(df))):
            if pool["type"] == "EQH" and df["high"].iloc[j] > level:
                swept = 1
                break
            elif pool["type"] == "EQL" and df["low"].iloc[j] < level:
                swept = 1
                break
        labels.append(swept)
    return pd.Series(labels, name="label")

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("=" * 60)
    print(f" Liquidity Sweep Predictor — {CONFIG['symbol']} {CONFIG['timeframe']}")
    print(f" {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 60)

    loader = DataLoader(CONFIG["symbol"], CONFIG["timeframe"])
    df = loader.load(CONFIG["n_bars"])
    print(f"[DATA]  Loaded {len(df):,} bars")

    pools = detect_liquidity_pools(df)
    print(f"[LIQ]   Detected {len(pools):,} liquidity pools (EQH: {(pools['type']=='EQH').sum()}, EQL: {(pools['type']=='EQL').sum()})")

    feat_df = create_features(df, pools)
    labels = create_labels(df, feat_df, pools)
    feature_cols = [c for c in feat_df.columns if c != "bar_idx"]
    X = feat_df[feature_cols].values
    y = labels.values
    print(f"[FEAT]  {len(feature_cols)} features, {len(X):,} samples")
    print(f"[DIST]  Swept: {y.sum()}, Not: {len(y) - y.sum()}, Ratio: {y.mean():.3f}")

    split = int(len(X) * (1 - CONFIG["test_ratio"]))
    X_train, X_test = X[:split], X[split:]
    y_train, y_test = y[:split], y[split:]

    trainer = ModelTrainer(task="binary", seed=CONFIG["random_seed"])
    best_params = trainer.optimize_xgb(X_train, y_train, n_trials=CONFIG["optuna_trials"])
    model = trainer.train_xgb(X_train, y_train, best_params)

    metrics = trainer.evaluate(model, X_test, y_test, label_names=["not_swept", "swept"])
    print(f"\n[EVAL]  Accuracy : {metrics['accuracy']:.4f}")
    print(f"[EVAL]  AUC-ROC  : {metrics.get('auc_roc', 0):.4f}")
    print(f"[EVAL]  F1       : {metrics['f1_macro']:.4f}")
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
