"""
02_fvg_fill_predictor.py - FVG充填予測 / Fair Value Gap Fill Predictor
========================================================================
XGBoost 2クラス分類: FVGが将来N本以内に充填されるか予測
Features: FVGサイズ, 相対位置, トレンドコンテキスト, ボラティリティ
Labels:  FVGがN本以内に充填されたか (0/1)

XGBoost binary classifier that predicts whether a detected
Fair Value Gap will be filled within the next N bars.
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
    "model_name": "fvg_fill_predictor",
    "output_dir": str(default_model_dir()),
    # FVG detection
    "min_fvg_pips": 3.0,       # minimum FVG size in pips
    "fill_window": 24,          # bars to check for fill
    # Training
    "test_ratio": 0.2,
    "optuna_trials": 30,
    "random_seed": 42,
}

# ---------------------------------------------------------------------------
# FVG detection
# ---------------------------------------------------------------------------
def detect_fvgs(df: pd.DataFrame, pip_size: float = 0.0001) -> pd.DataFrame:
    """Detect bullish and bearish Fair Value Gaps."""
    records = []
    high = df["high"].values
    low = df["low"].values
    close = df["close"].values
    open_ = df["open"].values

    for i in range(2, len(df) - CONFIG["fill_window"]):
        # Bullish FVG: bar[i] low > bar[i-2] high
        gap_bull = low[i] - high[i - 2]
        if gap_bull > CONFIG["min_fvg_pips"] * pip_size:
            records.append({
                "idx": i, "direction": 1,
                "gap_top": low[i], "gap_bottom": high[i - 2],
                "gap_size": gap_bull,
            })
        # Bearish FVG: bar[i-2] low > bar[i] high
        gap_bear = low[i - 2] - high[i]
        if gap_bear > CONFIG["min_fvg_pips"] * pip_size:
            records.append({
                "idx": i, "direction": -1,
                "gap_top": low[i - 2], "gap_bottom": high[i],
                "gap_size": gap_bear,
            })
    return pd.DataFrame(records)

# ---------------------------------------------------------------------------
# Feature engineering
# ---------------------------------------------------------------------------
def create_features(df: pd.DataFrame, fvgs: pd.DataFrame) -> pd.DataFrame:
    """Build features for each detected FVG."""
    fe = FeatureEngineer(df)
    atr14 = fe.atr(14)
    sma50 = df["close"].rolling(50).mean()
    std20 = df["close"].rolling(20).std()
    rows = []

    for _, fvg in fvgs.iterrows():
        i = int(fvg["idx"])
        if i < 50 or i >= len(df) - CONFIG["fill_window"]:
            continue
        gap_pips = fvg["gap_size"]
        row = {
            "fvg_dir": fvg["direction"],
            "gap_size_atr": gap_pips / atr14.iloc[i] if atr14.iloc[i] > 0 else 0,
            "gap_size_abs": gap_pips,
            "body_ratio": abs(df["close"].iloc[i] - df["open"].iloc[i]) / (df["high"].iloc[i] - df["low"].iloc[i] + 1e-10),
            "trend_pos": (df["close"].iloc[i] - sma50.iloc[i]) / (std20.iloc[i] + 1e-10),
            "vol_ratio": atr14.iloc[i] / atr14.iloc[max(0, i - 50):i].mean() if atr14.iloc[max(0, i - 50):i].mean() > 0 else 1,
            "return_5": (df["close"].iloc[i] / df["close"].iloc[i - 5]) - 1,
            "return_20": (df["close"].iloc[i] / df["close"].iloc[i - 20]) - 1,
            "range_expansion": (df["high"].iloc[i] - df["low"].iloc[i]) / atr14.iloc[i] if atr14.iloc[i] > 0 else 1,
            "gap_position": (fvg["gap_top"] - df["low"].iloc[i - 20:i].min()) / (df["high"].iloc[i - 20:i].max() - df["low"].iloc[i - 20:i].min() + 1e-10),
            "consec_dir": fe.consecutive_direction(i, fvg["direction"]),
            "bar_idx": i,
        }
        rows.append(row)
    return pd.DataFrame(rows)

# ---------------------------------------------------------------------------
# Label creation
# ---------------------------------------------------------------------------
def create_labels(df: pd.DataFrame, features_df: pd.DataFrame) -> pd.Series:
    """Label = 1 if FVG filled within window, else 0."""
    labels = []
    for _, row in features_df.iterrows():
        i = int(row["bar_idx"])
        direction = row["fvg_dir"]
        filled = 0
        for j in range(i + 1, min(i + CONFIG["fill_window"] + 1, len(df))):
            if direction == 1 and df["low"].iloc[j] <= df["high"].iloc[i - 2]:
                filled = 1
                break
            elif direction == -1 and df["high"].iloc[j] >= df["low"].iloc[i - 2]:
                filled = 1
                break
        labels.append(filled)
    return pd.Series(labels, name="label")

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("=" * 60)
    print(f" FVG Fill Predictor — {CONFIG['symbol']} {CONFIG['timeframe']}")
    print(f" {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 60)

    # 1. Load data
    loader = DataLoader(CONFIG["symbol"], CONFIG["timeframe"])
    df = loader.load(CONFIG["n_bars"])
    print(f"[DATA]  Loaded {len(df):,} bars")

    # 2. Detect FVGs
    fvgs = detect_fvgs(df)
    print(f"[FVG]   Detected {len(fvgs):,} FVGs (bull: {(fvgs['direction']==1).sum()}, bear: {(fvgs['direction']==-1).sum()})")

    # 3. Features & labels
    feat_df = create_features(df, fvgs)
    labels = create_labels(df, feat_df)
    feature_cols = [c for c in feat_df.columns if c != "bar_idx"]
    X = feat_df[feature_cols].values
    y = labels.values
    print(f"[FEAT]  {len(feature_cols)} features, {len(X):,} samples")
    print(f"[DIST]  Filled: {y.sum()}, Not: {len(y) - y.sum()}, Ratio: {y.mean():.3f}")

    # 4. Train/test split (chronological)
    split = int(len(X) * (1 - CONFIG["test_ratio"]))
    X_train, X_test = X[:split], X[split:]
    y_train, y_test = y[:split], y[split:]

    # 5. Train XGBoost with Optuna
    trainer = ModelTrainer(task="binary", seed=CONFIG["random_seed"])
    best_params = trainer.optimize_xgb(X_train, y_train, n_trials=CONFIG["optuna_trials"])
    model = trainer.train_xgb(X_train, y_train, best_params)

    # 6. Evaluate
    metrics = trainer.evaluate(model, X_test, y_test, label_names=["not_filled", "filled"])
    print(f"\n[EVAL]  Accuracy : {metrics['accuracy']:.4f}")
    print(f"[EVAL]  AUC-ROC  : {metrics.get('auc_roc', 0):.4f}")
    print(f"[EVAL]  F1       : {metrics['f1_macro']:.4f}")
    print(f"[EVAL]  Confusion matrix:\n{metrics['confusion_matrix']}")

    # 7. Feature importance
    importance = trainer.feature_importance(model, feature_cols, top_n=10)
    print("\n[IMP]   Top features:")
    for feat, score in importance:
        print(f"        {feat:30s} {score:.4f}")

    # 8. Export to ONNX
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
