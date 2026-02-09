"""
03_ob_quality_scorer.py - オーダーブロック品質スコア / Order Block Quality Scorer
==================================================================================
LightGBM 回帰 (0-1スコア): OBの品質を予測
Features: OBサイズ, インパルス強度, トレンド内位置, 経過時間
Labels:  OBの成功率 (価格がOBを尊重するか)

LightGBM regression model that scores Order Blocks from 0 to 1
based on how likely price is to respect them upon revisit.
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

warnings.filterwarnings("ignore")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CONFIG = {
    "symbol": "EURUSD",
    "timeframe": "M5",
    "n_bars": 100_000,
    "model_name": "ob_quality_scorer",
    "output_dir": "../Files/models/",
    # OB detection
    "impulse_min_pips": 10.0,
    "ob_max_age": 100,           # max bars since OB formed to be revisited
    "respect_threshold": 0.5,    # fraction of OB zone price must touch
    # Training
    "test_ratio": 0.2,
    "optuna_trials": 30,
    "random_seed": 42,
}

# ---------------------------------------------------------------------------
# Order Block detection
# ---------------------------------------------------------------------------
def detect_order_blocks(df: pd.DataFrame, pip_size: float = 0.0001) -> pd.DataFrame:
    """Detect bullish and bearish Order Blocks based on impulse moves."""
    records = []
    close = df["close"].values
    open_ = df["open"].values
    high = df["high"].values
    low = df["low"].values

    for i in range(3, len(df) - CONFIG["ob_max_age"]):
        # Bullish OB: last bearish candle before strong bullish impulse
        impulse = close[i] - close[i - 1]
        if impulse > CONFIG["impulse_min_pips"] * pip_size and close[i - 1] < open_[i - 1]:
            records.append({
                "idx": i - 1, "direction": 1,
                "ob_high": high[i - 1], "ob_low": low[i - 1],
                "ob_size": high[i - 1] - low[i - 1],
                "impulse_size": impulse,
            })
        # Bearish OB: last bullish candle before strong bearish impulse
        if impulse < -CONFIG["impulse_min_pips"] * pip_size and close[i - 1] > open_[i - 1]:
            records.append({
                "idx": i - 1, "direction": -1,
                "ob_high": high[i - 1], "ob_low": low[i - 1],
                "ob_size": high[i - 1] - low[i - 1],
                "impulse_size": abs(impulse),
            })
    return pd.DataFrame(records)

# ---------------------------------------------------------------------------
# Feature engineering
# ---------------------------------------------------------------------------
def create_features(df: pd.DataFrame, obs: pd.DataFrame) -> pd.DataFrame:
    """Build features for each detected Order Block."""
    fe = FeatureEngineer(df)
    atr14 = fe.atr(14)
    sma50 = df["close"].rolling(50).mean()
    rows = []

    for _, ob in obs.iterrows():
        i = int(ob["idx"])
        if i < 50:
            continue
        row = {
            "ob_dir": ob["direction"],
            "ob_size_atr": ob["ob_size"] / atr14.iloc[i] if atr14.iloc[i] > 0 else 0,
            "impulse_atr": ob["impulse_size"] / atr14.iloc[i] if atr14.iloc[i] > 0 else 0,
            "impulse_ob_ratio": ob["impulse_size"] / (ob["ob_size"] + 1e-10),
            "trend_alignment": ob["direction"] * ((df["close"].iloc[i] - sma50.iloc[i]) / (atr14.iloc[i] + 1e-10)),
            "vol_environment": atr14.iloc[i] / atr14.iloc[max(0, i - 100):i].mean() if atr14.iloc[max(0, i - 100):i].mean() > 0 else 1,
            "position_in_range": (df["close"].iloc[i] - df["low"].iloc[max(0, i - 50):i].min()) / (df["high"].iloc[max(0, i - 50):i].max() - df["low"].iloc[max(0, i - 50):i].min() + 1e-10),
            "prior_structure_count": fe.count_structure_breaks(i, lookback=50),
            "return_pre_ob": (df["close"].iloc[i] / df["close"].iloc[max(0, i - 10)]) - 1,
            "candle_count_trend": fe.consecutive_direction(i, ob["direction"]),
            "ob_body_ratio": abs(df["close"].iloc[i] - df["open"].iloc[i]) / (ob["ob_size"] + 1e-10),
            "bar_idx": i,
        }
        rows.append(row)
    return pd.DataFrame(rows)

# ---------------------------------------------------------------------------
# Label creation (regression target 0–1)
# ---------------------------------------------------------------------------
def create_labels(df: pd.DataFrame, feat_df: pd.DataFrame, obs: pd.DataFrame) -> pd.Series:
    """Score each OB: 1.0 = perfectly respected, 0.0 = completely invalidated."""
    scores = []
    for idx_row, (_, row) in enumerate(feat_df.iterrows()):
        i = int(row["bar_idx"])
        ob = obs.iloc[idx_row]
        direction = int(ob["direction"])
        ob_h, ob_l = ob["ob_high"], ob["ob_low"]
        ob_mid = (ob_h + ob_l) / 2.0

        touched, respected = False, False
        best_reaction = 0.0
        for j in range(i + 1, min(i + CONFIG["ob_max_age"] + 1, len(df))):
            if direction == 1 and df["low"].iloc[j] <= ob_h:
                touched = True
                reaction = (df["close"].iloc[j] - ob_mid) / (ob_h - ob_l + 1e-10)
                best_reaction = max(best_reaction, reaction)
                if df["close"].iloc[j] < ob_l:
                    respected = False
                    break
                respected = True
            elif direction == -1 and df["high"].iloc[j] >= ob_l:
                touched = True
                reaction = (ob_mid - df["close"].iloc[j]) / (ob_h - ob_l + 1e-10)
                best_reaction = max(best_reaction, reaction)
                if df["close"].iloc[j] > ob_h:
                    respected = False
                    break
                respected = True

        if not touched:
            score = 0.5
        elif respected:
            score = min(1.0, 0.5 + best_reaction * 0.25)
        else:
            score = max(0.0, 0.3 - best_reaction * 0.1)
        scores.append(score)
    return pd.Series(scores, name="label")

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("=" * 60)
    print(f" OB Quality Scorer — {CONFIG['symbol']} {CONFIG['timeframe']}")
    print(f" {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 60)

    loader = DataLoader(CONFIG["symbol"], CONFIG["timeframe"])
    df = loader.load(CONFIG["n_bars"])
    print(f"[DATA]  Loaded {len(df):,} bars")

    obs = detect_order_blocks(df)
    print(f"[OB]    Detected {len(obs):,} order blocks")

    feat_df = create_features(df, obs)
    labels = create_labels(df, feat_df, obs)
    feature_cols = [c for c in feat_df.columns if c != "bar_idx"]
    X = feat_df[feature_cols].values
    y = labels.values
    print(f"[FEAT]  {len(feature_cols)} features, {len(X):,} samples")
    print(f"[DIST]  Score mean={y.mean():.3f}, std={y.std():.3f}")

    split = int(len(X) * (1 - CONFIG["test_ratio"]))
    X_train, X_test = X[:split], X[split:]
    y_train, y_test = y[:split], y[split:]

    trainer = ModelTrainer(task="regression", seed=CONFIG["random_seed"])
    best_params = trainer.optimize_lgbm(X_train, y_train, n_trials=CONFIG["optuna_trials"])
    model = trainer.train_lgbm(X_train, y_train, best_params)

    metrics = trainer.evaluate_regression(model, X_test, y_test)
    print(f"\n[EVAL]  MAE  : {metrics['mae']:.4f}")
    print(f"[EVAL]  RMSE : {metrics['rmse']:.4f}")
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
