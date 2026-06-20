"""
08_session_pattern.py - セッションパターン予測 / Session Pattern Predictor
===========================================================================
LightGBM 3クラス分類: up / down / flat (セッション方向)
Features: 時間特徴, セッション情報, オープニングレンジ
Labels:  セッション方向

LightGBM 3-class classifier that predicts session (Asian/London/NY)
directional outcome based on time features, session context,
and opening range characteristics.
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
    "model_name": "session_pattern_3c",
    "output_dir": str(default_model_dir()),
    # Session definitions (UTC hours)
    "sessions": {
        "asian":  (0, 8),
        "london": (8, 16),
        "newyork": (13, 21),
    },
    "direction_threshold": 0.0002,  # pips threshold for up/down vs flat
    "opening_range_bars": 6,         # first N bars define opening range
    # Training
    "test_ratio": 0.2,
    "optuna_trials": 30,
    "random_seed": 42,
}

LABEL_MAP = {0: "down", 1: "flat", 2: "up"}

# ---------------------------------------------------------------------------
# Session segmentation
# ---------------------------------------------------------------------------
def segment_sessions(df: pd.DataFrame) -> pd.DataFrame:
    """Split data into session blocks and compute per-session features."""
    if "time" not in df.columns:
        df["time"] = df.index

    df["hour"] = pd.to_datetime(df["time"]).dt.hour
    df["minute"] = pd.to_datetime(df["time"]).dt.minute
    df["day_of_week"] = pd.to_datetime(df["time"]).dt.dayofweek
    df["day_of_month"] = pd.to_datetime(df["time"]).dt.day

    records = []
    or_bars = CONFIG["opening_range_bars"]

    for session_name, (start_h, end_h) in CONFIG["sessions"].items():
        mask = (df["hour"] >= start_h) & (df["hour"] < end_h)
        session_df = df[mask]

        # Group by date
        session_df = session_df.copy()
        session_df["date"] = pd.to_datetime(session_df["time"]).dt.date
        for date, group in session_df.groupby("date"):
            if len(group) < or_bars + 5:
                continue
            first_idx = group.index[0]
            global_pos = df.index.get_loc(first_idx)
            if global_pos < 100:
                continue
            records.append({
                "global_idx": global_pos,
                "session": session_name,
                "date": date,
                "group_indices": group.index.tolist(),
            })
    return pd.DataFrame(records)

# ---------------------------------------------------------------------------
# Feature engineering
# ---------------------------------------------------------------------------
def create_features(df: pd.DataFrame, sessions: pd.DataFrame) -> pd.DataFrame:
    """Build per-session features."""
    fe = FeatureEngineer(df)
    atr14 = fe.atr(14)
    or_bars = CONFIG["opening_range_bars"]
    rows = []

    for _, sess in sessions.iterrows():
        gi = sess["global_idx"]
        indices = sess["group_indices"]
        if len(indices) < or_bars + 1:
            continue

        # Opening range
        or_slice = df.loc[indices[:or_bars]]
        or_high = or_slice["high"].max()
        or_low = or_slice["low"].min()
        or_range = or_high - or_low
        or_close = or_slice["close"].iloc[-1]
        or_open = or_slice["open"].iloc[0]
        or_direction = 1 if or_close > or_open else (-1 if or_close < or_open else 0)

        # Previous session close
        prev_close = df["close"].iloc[gi - 1] if gi > 0 else or_open
        gap = (or_open - prev_close) / (atr14.iloc[gi] + 1e-10)

        # Time features
        hour = df["hour"].iloc[gi] if "hour" in df.columns else 0
        dow = df["day_of_week"].iloc[gi] if "day_of_week" in df.columns else 0

        row = {
            "session_id": ["asian", "london", "newyork"].index(sess["session"]),
            "hour_sin": np.sin(2 * np.pi * hour / 24),
            "hour_cos": np.cos(2 * np.pi * hour / 24),
            "dow_sin": np.sin(2 * np.pi * dow / 5),
            "dow_cos": np.cos(2 * np.pi * dow / 5),
            "or_range_atr": or_range / (atr14.iloc[gi] + 1e-10),
            "or_direction": or_direction,
            "or_body_ratio": abs(or_close - or_open) / (or_range + 1e-10),
            "gap_atr": gap,
            "prev_session_return": (df["close"].iloc[gi] - df["close"].iloc[max(0, gi - 60)]) / (atr14.iloc[gi] + 1e-10),
            "atr_14": atr14.iloc[gi],
            "atr_ratio": atr14.iloc[gi] / atr14.iloc[max(0, gi - 200):gi].mean() if atr14.iloc[max(0, gi - 200):gi].mean() > 0 else 1,
            "return_5": (df["close"].iloc[gi] / df["close"].iloc[max(0, gi - 5)]) - 1,
            "return_20": (df["close"].iloc[gi] / df["close"].iloc[max(0, gi - 20)]) - 1,
            "price_vs_sma50": (df["close"].iloc[gi] - df["close"].iloc[max(0, gi - 50):gi].mean()) / (atr14.iloc[gi] + 1e-10),
            "global_idx": gi,
            "group_indices": indices,
        }
        rows.append(row)
    return pd.DataFrame(rows)

# ---------------------------------------------------------------------------
# Label creation
# ---------------------------------------------------------------------------
def create_labels(df: pd.DataFrame, feat_df: pd.DataFrame) -> pd.Series:
    """Label session direction: 0=down, 1=flat, 2=up."""
    labels = []
    for _, row in feat_df.iterrows():
        indices = row["group_indices"]
        if len(indices) < 2:
            labels.append(1)
            continue
        session_open = df["open"].loc[indices[0]]
        session_close = df["close"].loc[indices[-1]]
        ret = (session_close - session_open) / session_open

        if ret > CONFIG["direction_threshold"]:
            labels.append(2)   # up
        elif ret < -CONFIG["direction_threshold"]:
            labels.append(0)   # down
        else:
            labels.append(1)   # flat
    return pd.Series(labels, name="label")

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("=" * 60)
    print(f" Session Pattern — {CONFIG['symbol']} {CONFIG['timeframe']}")
    print(f" {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 60)

    loader = DataLoader(CONFIG["symbol"], CONFIG["timeframe"])
    df = loader.load(CONFIG["n_bars"])
    print(f"[DATA]  Loaded {len(df):,} bars")

    sessions = segment_sessions(df)
    print(f"[SESS]  Segmented {len(sessions):,} session blocks")

    feat_df = create_features(df, sessions)
    labels = create_labels(df, feat_df)
    feature_cols = [c for c in feat_df.columns if c not in ["global_idx", "group_indices"]]
    X = feat_df[feature_cols]
    y = labels
    print(f"[FEAT]  {len(feature_cols)} features, {len(X):,} samples")
    print(f"[DIST]  {dict(y.value_counts().sort_index())}")

    split = int(len(X) * (1 - CONFIG["test_ratio"]))
    X_train, X_test = X.iloc[:split], X.iloc[split:]
    y_train, y_test = y.iloc[:split], y.iloc[split:]

    trainer = ModelTrainer(task="multiclass", num_class=3, seed=CONFIG["random_seed"])
    best_params = trainer.optimize_lgbm(X_train, y_train, n_trials=CONFIG["optuna_trials"])
    model = trainer.train_lgbm(X_train, y_train, best_params)

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
