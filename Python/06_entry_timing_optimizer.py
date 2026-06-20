"""
06_entry_timing_optimizer.py - エントリータイミング最適化 / Entry Timing Optimizer
===================================================================================
LightGBM 回帰: 最適なエントリー待機バー数を予測
Features: ゾーン位置, マーケットコンテキスト, ボラティリティ
Labels:  最適エントリーまでのバー数

LightGBM regression model that predicts the optimal number of bars
to wait before entering a trade once a zone (OB/FVG) is identified.
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
    "model_name": "entry_timing_opt",
    "output_dir": str(default_model_dir()),
    # Zone / signal parameters
    "zone_lookback": 50,
    "max_wait_bars": 30,         # maximum bars to look for best entry
    "impulse_threshold": 0.0005, # min impulse to define a zone
    # Training
    "test_ratio": 0.2,
    "optuna_trials": 30,
    "random_seed": 42,
}

# ---------------------------------------------------------------------------
# Zone detection (simplified OB/FVG zones)
# ---------------------------------------------------------------------------
def detect_zones(df: pd.DataFrame) -> pd.DataFrame:
    """Detect potential entry zones from impulse moves."""
    records = []
    close = df["close"].values
    high = df["high"].values
    low = df["low"].values
    threshold = CONFIG["impulse_threshold"]

    for i in range(3, len(df) - CONFIG["max_wait_bars"]):
        impulse = close[i] - close[i - 1]
        if abs(impulse) > threshold:
            direction = 1 if impulse > 0 else -1
            records.append({
                "idx": i,
                "direction": direction,
                "zone_high": high[i - 1],
                "zone_low": low[i - 1],
                "impulse_size": abs(impulse),
            })
    return pd.DataFrame(records)

# ---------------------------------------------------------------------------
# Feature engineering
# ---------------------------------------------------------------------------
def create_features(df: pd.DataFrame, zones: pd.DataFrame) -> pd.DataFrame:
    """Build features describing market context at each zone."""
    fe = FeatureEngineer(df)
    atr14 = fe.atr(14)
    atr50 = fe.atr(50)
    sma20 = df["close"].rolling(20).mean()
    sma50 = df["close"].rolling(50).mean()
    std20 = df["close"].rolling(20).std()
    rows = []

    for _, zone in zones.iterrows():
        i = int(zone["idx"])
        if i < 60:
            continue
        zone_mid = (zone["zone_high"] + zone["zone_low"]) / 2
        row = {
            "zone_dir": zone["direction"],
            "impulse_atr": zone["impulse_size"] / (atr14.iloc[i] + 1e-10),
            "zone_size_atr": (zone["zone_high"] - zone["zone_low"]) / (atr14.iloc[i] + 1e-10),
            "zone_position": (zone_mid - df["low"].iloc[i - 50:i].min()) / (df["high"].iloc[i - 50:i].max() - df["low"].iloc[i - 50:i].min() + 1e-10),
            "trend_strength": (sma20.iloc[i] - sma50.iloc[i]) / (std20.iloc[i] + 1e-10),
            "atr_ratio": atr14.iloc[i] / (atr50.iloc[i] + 1e-10),
            "vol_percentile": fe.percentile_rank(atr14, i, 100),
            "return_5": (df["close"].iloc[i] / df["close"].iloc[i - 5]) - 1,
            "return_10": (df["close"].iloc[i] / df["close"].iloc[i - 10]) - 1,
            "body_avg_5": np.mean([abs(df["close"].iloc[j] - df["open"].iloc[j]) for j in range(i - 5, i)]) / (atr14.iloc[i] + 1e-10),
            "wick_ratio_5": np.mean([(df["high"].iloc[j] - df["low"].iloc[j] - abs(df["close"].iloc[j] - df["open"].iloc[j])) / (df["high"].iloc[j] - df["low"].iloc[j] + 1e-10) for j in range(i - 5, i)]),
            "range_20_atr": (df["high"].iloc[i - 20:i].max() - df["low"].iloc[i - 20:i].min()) / (atr14.iloc[i] * 20 + 1e-10),
            "bar_idx": i,
        }
        rows.append(row)
    return pd.DataFrame(rows)

# ---------------------------------------------------------------------------
# Label creation (optimal bars to wait)
# ---------------------------------------------------------------------------
def create_labels(df: pd.DataFrame, feat_df: pd.DataFrame, zones: pd.DataFrame) -> pd.Series:
    """Find optimal wait time = bar with best price for entry within window."""
    labels = []
    zone_map = zones.set_index("idx")

    for _, row in feat_df.iterrows():
        i = int(row["bar_idx"])
        zone = zone_map.loc[i]
        direction = int(zone["direction"])
        best_bar = 0
        best_price = df["close"].iloc[i]

        for j in range(1, CONFIG["max_wait_bars"] + 1):
            if i + j >= len(df):
                break
            price = df["close"].iloc[i + j]
            # For bullish zone: want lowest entry; bearish: want highest
            if direction == 1 and price < best_price:
                best_price = price
                best_bar = j
            elif direction == -1 and price > best_price:
                best_price = price
                best_bar = j

        labels.append(best_bar)
    return pd.Series(labels, name="label", dtype=float)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("=" * 60)
    print(f" Entry Timing Optimizer — {CONFIG['symbol']} {CONFIG['timeframe']}")
    print(f" {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 60)

    loader = DataLoader(CONFIG["symbol"], CONFIG["timeframe"])
    df = loader.load(CONFIG["n_bars"])
    print(f"[DATA]  Loaded {len(df):,} bars")

    zones = detect_zones(df)
    print(f"[ZONE]  Detected {len(zones):,} entry zones")

    feat_df = create_features(df, zones)
    labels = create_labels(df, feat_df, zones)
    feature_cols = [c for c in feat_df.columns if c != "bar_idx"]
    X = feat_df[feature_cols].values
    y = labels.values
    print(f"[FEAT]  {len(feature_cols)} features, {len(X):,} samples")
    print(f"[DIST]  Wait bars — mean={y.mean():.1f}, median={np.median(y):.1f}, max={y.max():.0f}")

    split = int(len(X) * (1 - CONFIG["test_ratio"]))
    X_train, X_test = X[:split], X[split:]
    y_train, y_test = y[:split], y[split:]

    trainer = ModelTrainer(task="regression", seed=CONFIG["random_seed"])
    best_params = trainer.optimize_lgbm(X_train, y_train, n_trials=CONFIG["optuna_trials"])
    model = trainer.train_lgbm(X_train, y_train, best_params)

    metrics = trainer.evaluate_regression(model, X_test, y_test)
    print(f"\n[EVAL]  MAE  : {metrics['mae']:.2f} bars")
    print(f"[EVAL]  RMSE : {metrics['rmse']:.2f} bars")
    print(f"[EVAL]  R²   : {metrics['r2']:.4f}")

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
