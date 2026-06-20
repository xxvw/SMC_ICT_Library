"""
04_bos_choch_detector.py - BOS/CHoCH検出器 / Structure Break Detector
======================================================================
LSTM 3クラス分類: BOS(Break of Structure) / CHoCH(Change of Character) / None
Features: 正規化された価格シーケンスデータ (OHLC)
Labels:  次のN本における構造ブレイクのタイプ

LSTM-based 3-class sequence classifier that detects Break of Structure
(BOS), Change of Character (CHoCH), or no structure event using
normalized OHLC price windows.
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
    "model_name": "bos_choch_detector",
    "output_dir": str(default_model_dir()),
    # Sequence parameters
    "seq_length": 30,         # lookback bars for LSTM input
    "future_bars": 10,        # look-ahead for labelling
    "swing_period": 10,       # swing point detection window
    # LSTM architecture
    "lstm_units": 64,
    "dropout": 0.2,
    "epochs": 50,
    "batch_size": 256,
    "learning_rate": 0.001,
    # Training
    "test_ratio": 0.2,
    "random_seed": 42,
}

LABEL_MAP = {0: "none", 1: "BOS", 2: "CHoCH"}

# ---------------------------------------------------------------------------
# Structure break labelling
# ---------------------------------------------------------------------------
def detect_swing_points(df: pd.DataFrame, period: int):
    """Identify swing highs and swing lows."""
    swing_highs = np.full(len(df), np.nan)
    swing_lows = np.full(len(df), np.nan)
    high, low = df["high"].values, df["low"].values

    for i in range(period, len(df) - period):
        if high[i] == max(high[i - period:i + period + 1]):
            swing_highs[i] = high[i]
        if low[i] == min(low[i - period:i + period + 1]):
            swing_lows[i] = low[i]
    return swing_highs, swing_lows

def create_labels(df: pd.DataFrame) -> pd.Series:
    """Label each bar: 0=none, 1=BOS, 2=CHoCH."""
    sp = CONFIG["swing_period"]
    fb = CONFIG["future_bars"]
    swing_highs, swing_lows = detect_swing_points(df, sp)

    labels = np.zeros(len(df), dtype=int)
    last_sh = np.nan
    last_sl = np.nan
    trend = 0  # 1=bullish, -1=bearish, 0=undefined

    for i in range(sp, len(df) - fb):
        if not np.isnan(swing_highs[i]):
            last_sh = swing_highs[i]
        if not np.isnan(swing_lows[i]):
            last_sl = swing_lows[i]

        if np.isnan(last_sh) or np.isnan(last_sl):
            continue

        future_high = df["high"].iloc[i + 1:i + fb + 1].max()
        future_low = df["low"].iloc[i + 1:i + fb + 1].min()

        if trend >= 0 and future_high > last_sh:
            labels[i] = 1   # BOS (continuation)
        elif trend >= 0 and future_low < last_sl:
            labels[i] = 2   # CHoCH (reversal)
        elif trend < 0 and future_low < last_sl:
            labels[i] = 1   # BOS (continuation)
        elif trend < 0 and future_high > last_sh:
            labels[i] = 2   # CHoCH (reversal)

        # Update trend
        if future_high > last_sh:
            trend = 1
        elif future_low < last_sl:
            trend = -1

    return pd.Series(labels, name="label")

# ---------------------------------------------------------------------------
# Sequence creation for LSTM
# ---------------------------------------------------------------------------
def create_sequences(df: pd.DataFrame, labels: pd.Series):
    """Create normalized OHLC sequences for LSTM input."""
    seq_len = CONFIG["seq_length"]
    ohlc = df[["open", "high", "low", "close"]].values
    X_seqs, y_seqs = [], []

    for i in range(seq_len, len(df) - CONFIG["future_bars"]):
        window = ohlc[i - seq_len:i].copy()
        # Normalize: scale to [0,1] within each window
        w_min = window.min()
        w_range = window.max() - w_min
        if w_range < 1e-10:
            continue
        window = (window - w_min) / w_range
        X_seqs.append(window)
        y_seqs.append(labels.iloc[i])

    return np.array(X_seqs, dtype=np.float32), np.array(y_seqs, dtype=np.int64)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("=" * 60)
    print(f" BOS/CHoCH Detector — {CONFIG['symbol']} {CONFIG['timeframe']}")
    print(f" {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 60)

    # 1. Load data
    loader = DataLoader(CONFIG["symbol"], CONFIG["timeframe"])
    df = loader.load(CONFIG["n_bars"])
    print(f"[DATA]  Loaded {len(df):,} bars")

    # 2. Labels & sequences
    labels = create_labels(df)
    X, y = create_sequences(df, labels)
    print(f"[SEQ]   Shape: {X.shape}, Labels: {dict(zip(*np.unique(y, return_counts=True)))}")

    # 3. Train/test split
    split = int(len(X) * (1 - CONFIG["test_ratio"]))
    X_train, X_test = X[:split], X[split:]
    y_train, y_test = y[:split], y[split:]

    # 4. Build and train LSTM
    trainer = ModelTrainer(task="multiclass", num_class=3, seed=CONFIG["random_seed"])
    model = trainer.build_lstm(
        input_shape=(CONFIG["seq_length"], 4),
        num_classes=3,
        units=CONFIG["lstm_units"],
        dropout=CONFIG["dropout"],
        lr=CONFIG["learning_rate"],
    )
    history = trainer.train_lstm(
        model, X_train, y_train,
        X_val=X_test, y_val=y_test,
        epochs=CONFIG["epochs"],
        batch_size=CONFIG["batch_size"],
    )

    # 5. Evaluate
    metrics = trainer.evaluate_lstm(model, X_test, y_test, label_names=list(LABEL_MAP.values()))
    print(f"\n[EVAL]  Accuracy : {metrics['accuracy']:.4f}")
    print(f"[EVAL]  F1-macro : {metrics['f1_macro']:.4f}")
    print(f"[EVAL]  Confusion matrix:\n{metrics['confusion_matrix']}")

    # 6. Export to ONNX
    output_path = os.path.join(CONFIG["output_dir"], CONFIG["model_name"])
    os.makedirs(output_path, exist_ok=True)
    onnx_path = trainer.export_lstm_onnx(model, CONFIG["seq_length"], 4, output_path)
    print(f"\n[ONNX]  Exported → {onnx_path}")

    # 7. Training curve summary
    final_loss = history.history["loss"][-1]
    final_val = history.history.get("val_loss", [0])[-1]
    print(f"\n[HIST]  Final loss: {final_loss:.4f}, val_loss: {final_val:.4f}")

    print("\n" + "=" * 60)
    print(" Training complete.")
    print(f" Model : {CONFIG['model_name']}")
    print(f" ONNX  : {onnx_path}")
    print("=" * 60)

if __name__ == "__main__":
    main()
