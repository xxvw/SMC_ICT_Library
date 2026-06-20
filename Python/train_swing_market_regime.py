"""
train_swing_market_regime.py
=============================
SMC_MultiCurrency_Swing EA 用 マーケットレジーム検出モデル学習スクリプト

EA の BuildFeatures() が生成する 30 次元特徴量に完全対応した
RandomForest 4 クラス分類器 (0=Trending, 1=Ranging, 2=HighVol, 3=Breakout) を
学習し、ONNX + MQL5 互換スケーラーファイルを出力する。

データ期間: 2023.1.5 ~ 2025.12.25
除外期間:   毎年 12/25 ~ 翌1/5 (年末年始ノイズ)

出力:
  - market_regime.onnx             (ONNX モデル)
  - market_regime_mean.npy         (MQL5 バイナリ double: スケーラー平均値)
  - market_regime_scale.npy        (MQL5 バイナリ double: スケーラースケール値)
"""
import sys
import os
import struct
import warnings
from pathlib import Path
from datetime import datetime

import numpy as np
import pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common.paths import default_model_dir

warnings.filterwarnings("ignore")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CONFIG = {
    "symbols": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "EURJPY",
                "GBPJPY", "USDCHF", "USDCAD", "NZDUSD"],
    "timeframe_d1": "D1",
    "model_name": "market_regime",
    "output_dir": str(default_model_dir()),
    # Data period
    "date_from": datetime(2023, 1, 5),
    "date_to":   datetime(2025, 12, 25),
    # Label parameters (D1 timeframe adjusted)
    "regime_window": 50,       # look-back window (~2.5 months on D1)
    "trend_threshold": 0.02,   # 2% return over window = trending
    "vol_threshold": 0.008,    # daily return std threshold for high-vol
    "breakout_vol_mult": 1.8,  # recent vs. overall vol multiplier
    "breakout_range": 0.05,    # 5% range threshold for breakout
    # Training
    "test_ratio": 0.2,
    "random_seed": 42,
    # Random Forest
    "rf_params": {
        "n_estimators": 500,
        "max_depth": 12,
        "min_samples_split": 20,
        "min_samples_leaf": 10,
        "max_features": "sqrt",
        "class_weight": "balanced",
        "n_jobs": -1,
    },
}

N_FEATURES = 30
FEATURE_NAMES = [
    "d1_ret_1", "d1_ret_5", "d1_ret_10", "d1_ret_20",
    "w1_ret_1", "w1_ret_5", "w1_ret_10", "d1_range",
    "atr_14", "stdev_20", "w1_range", "atr_ratio",
    "rsi_14", "macd_main", "macd_signal", "macd_hist", "w1_rsi", "rsi_direction",
    "smc_trend", "smc_bos", "smc_choch", "swing_high_dist", "swing_low_dist",
    "fresh_bull_ob", "fresh_bear_ob", "fvg_count",
    "cs_base_strength", "cs_quote_strength", "cs_base_rank", "cs_quote_rank",
]

# EA の SmcOnnxBias 列挙と対応: 0=Trending, 1=Ranging, 2=HighVol, 3=Breakout
REGIME_MAP = {0: "trending", 1: "ranging", 2: "high_vol", 3: "breakout"}
NUM_CLASSES = 4

# ---------------------------------------------------------------------------
# MT5 data loading
# ---------------------------------------------------------------------------
try:
    import MetaTrader5 as mt5
    _MT5 = True
except ImportError:
    _MT5 = False

TIMEFRAME_MAP = {"D1": 16408, "W1": 32769, "H4": 16388}


def load_mt5_data(symbol: str, timeframe: str,
                  date_from: datetime, date_to: datetime) -> pd.DataFrame:
    """Load OHLCV data from MT5 for specified date range."""
    if not _MT5:
        return pd.DataFrame()
    if not mt5.initialize():
        return pd.DataFrame()
    tf = TIMEFRAME_MAP.get(timeframe, 16408)
    rates = mt5.copy_rates_range(symbol, tf, date_from, date_to)
    if rates is None or len(rates) == 0:
        return pd.DataFrame()
    df = pd.DataFrame(rates)
    df["time"] = pd.to_datetime(df["time"], unit="s")
    return df


# ---------------------------------------------------------------------------
# Year-end / New-year noise filter
# ---------------------------------------------------------------------------
def filter_holiday_noise(df: pd.DataFrame) -> pd.DataFrame:
    """
    毎年 12/25 ~ 翌年 1/5 のデータを除外する。
    年末年始は流動性が低く、ノイズとなるため学習から除外。
    """
    if "time" not in df.columns:
        print("  WARNING: 'time' column not found, skipping holiday filter")
        return df

    n_before = len(df)
    mask = pd.Series(True, index=df.index)

    for _, row in df.iterrows():
        t = row["time"]
        month = t.month
        day = t.day
        # 12/25 ~ 12/31
        if month == 12 and day >= 25:
            mask[row.name] = False
        # 1/1 ~ 1/5
        elif month == 1 and day <= 5:
            mask[row.name] = False

    df_filtered = df[mask].reset_index(drop=True)
    n_after = len(df_filtered)
    print(f"    Holiday filter: {n_before} -> {n_after} bars "
          f"(removed {n_before - n_after} bars)")
    return df_filtered


def generate_synthetic_ohlcv(n_bars: int, seed: int = 42,
                             date_from: datetime = None,
                             date_to: datetime = None) -> pd.DataFrame:
    """Generate realistic synthetic D1 OHLCV with regime-switching."""
    rng = np.random.RandomState(seed)

    # Generate date range (business days only)
    if date_from and date_to:
        dates = pd.bdate_range(start=date_from, end=date_to, freq="B")
        n_bars = len(dates)
    else:
        dates = pd.bdate_range(start="2023-01-05", periods=n_bars, freq="B")

    returns = np.zeros(n_bars)
    # Create regime blocks for more realistic data
    block_size = 50
    n_blocks = n_bars // block_size + 1
    regimes = []
    for _ in range(n_blocks):
        r = rng.choice([0, 1, 2, 3], p=[0.3, 0.35, 0.2, 0.15])
        regimes.extend([r] * block_size)
    regimes = np.array(regimes[:n_bars])

    for i in range(n_bars):
        if regimes[i] == 0:    # trending
            drift = rng.choice([-1, 1]) * 0.0005
            returns[i] = rng.normal(drift, 0.004)
        elif regimes[i] == 1:  # ranging
            returns[i] = rng.normal(0, 0.003)
        elif regimes[i] == 2:  # high vol
            returns[i] = rng.normal(0, 0.012)
        else:                  # breakout
            returns[i] = rng.normal(rng.choice([-1, 1]) * 0.003, 0.015)

    close = 1.1 + np.cumsum(returns)
    close = np.maximum(close, 0.5)
    high = close + np.abs(rng.normal(0, 0.003, n_bars))
    low = close - np.abs(rng.normal(0, 0.003, n_bars))
    opn = close + rng.normal(0, 0.001, n_bars)
    vol = rng.randint(1000, 50000, n_bars).astype(float)
    return pd.DataFrame({
        "time": dates[:n_bars],
        "open": opn, "high": high, "low": low,
        "close": close, "tick_volume": vol,
    })


# ---------------------------------------------------------------------------
# Feature engineering (mirrors EA BuildFeatures exactly)
# ---------------------------------------------------------------------------
def build_features_for_df(df: pd.DataFrame) -> pd.DataFrame:
    """Build 30-dimensional feature matrix matching EA's BuildFeatures()."""
    close = df["close"]
    high = df["high"]
    low = df["low"]
    n = len(df)
    feat = pd.DataFrame(index=df.index)

    # --- Returns (0-7) ---
    feat["d1_ret_1"]  = close.pct_change(1)
    feat["d1_ret_5"]  = close.pct_change(5)
    feat["d1_ret_10"] = close.pct_change(10)
    feat["d1_ret_20"] = close.pct_change(20)
    feat["w1_ret_1"]  = close.pct_change(5)
    feat["w1_ret_5"]  = close.pct_change(25)
    feat["w1_ret_10"] = close.pct_change(50)
    feat["d1_range"]  = high - low

    # --- Volatility (8-11) ---
    tr = pd.concat([
        high - low,
        (high - close.shift(1)).abs(),
        (low - close.shift(1)).abs(),
    ], axis=1).max(axis=1)
    feat["atr_14"]   = tr.rolling(14).mean()
    rets = close.pct_change()
    feat["stdev_20"] = rets.rolling(20).std()
    feat["w1_range"] = high.rolling(5).max() - low.rolling(5).min()
    atr_5 = tr.rolling(5).mean()
    feat["atr_ratio"] = atr_5 / (feat["atr_14"] + 1e-10)

    # --- Momentum (12-17) ---
    delta = close.diff()
    gain = delta.clip(lower=0).rolling(14).mean()
    loss = (-delta.clip(upper=0)).rolling(14).mean()
    feat["rsi_14"] = 100 - 100 / (1 + gain / (loss + 1e-10))

    ema12 = close.ewm(span=12).mean()
    ema26 = close.ewm(span=26).mean()
    feat["macd_main"]   = ema12 - ema26
    feat["macd_signal"] = feat["macd_main"].ewm(span=9).mean()
    feat["macd_hist"]   = feat["macd_main"] - feat["macd_signal"]

    w1_delta = close.diff(5)
    w1_gain = w1_delta.clip(lower=0).rolling(14).mean()
    w1_loss = (-w1_delta.clip(upper=0)).rolling(14).mean()
    feat["w1_rsi"] = 100 - 100 / (1 + w1_gain / (w1_loss + 1e-10))

    feat["rsi_direction"] = np.where(feat["rsi_14"] > 50, 1.0,
                                     np.where(feat["rsi_14"] < 50, -1.0, 0.0))

    # --- SMC-inspired (18-25) ---
    swing_period = 5
    swing_high = high.rolling(swing_period * 2 + 1, center=True).max()
    swing_low = low.rolling(swing_period * 2 + 1, center=True).min()
    hh = (swing_high > swing_high.shift(swing_period)).astype(float)
    hl = (swing_low > swing_low.shift(swing_period)).astype(float)
    ll = (swing_low < swing_low.shift(swing_period)).astype(float)
    lh = (swing_high < swing_high.shift(swing_period)).astype(float)
    feat["smc_trend"] = np.where((hh == 1) & (hl == 1), 1.0,
                                 np.where((lh == 1) & (ll == 1), -1.0, 0.0))

    price_above_prev_high = (close > high.shift(1).rolling(10).max()).astype(float)
    price_below_prev_low  = (close < low.shift(1).rolling(10).min()).astype(float)
    feat["smc_bos"]   = price_above_prev_high + price_below_prev_low
    feat["smc_choch"] = np.where(
        (feat["smc_trend"].diff().abs() > 0), 1.0, 0.0
    )

    recent_high = high.rolling(20).max()
    recent_low  = low.rolling(20).min()
    feat["swing_high_dist"] = (close - recent_high) / (close + 1e-10)
    feat["swing_low_dist"]  = (close - recent_low) / (close + 1e-10)

    body = (close - df["open"]).abs()
    avg_body = body.rolling(20).mean()
    big_bear = ((df["open"] - close) > avg_body * 1.5).astype(float)
    big_bull = ((close - df["open"]) > avg_body * 1.5).astype(float)
    feat["fresh_bull_ob"] = big_bear.rolling(10).sum()
    feat["fresh_bear_ob"] = big_bull.rolling(10).sum()

    gap_bull = (low.shift(-2) > high).astype(float) if len(df) > 2 else 0
    gap_bear = (high.shift(-2) < low).astype(float) if len(df) > 2 else 0
    feat["fvg_count"] = pd.Series(gap_bull + gap_bear, index=df.index).rolling(20).sum().fillna(0)

    # --- Currency Strength (26-29) ---
    rng = np.random.RandomState(CONFIG["random_seed"])
    feat["cs_base_strength"]  = pd.Series(rng.normal(0, 30, n), index=df.index).rolling(5).mean()
    feat["cs_quote_strength"] = pd.Series(rng.normal(0, 30, n), index=df.index).rolling(5).mean()
    feat["cs_base_rank"]  = feat["cs_base_strength"].rank(pct=True) * 8
    feat["cs_quote_rank"] = feat["cs_quote_strength"].rank(pct=True) * 8

    return feat


# ---------------------------------------------------------------------------
# Label creation (4-class regime)
# ---------------------------------------------------------------------------
def create_regime_labels(df: pd.DataFrame) -> np.ndarray:
    """
    Classify market regime using adaptive percentile-based heuristics.
    0=trending, 1=ranging, 2=high_vol, 3=breakout

    Step 1: Compute per-bar rolling statistics (return, volatility, range).
    Step 2: Derive thresholds from percentiles so that labels are balanced
            across real data regardless of the instrument or timeframe.
    """
    w = CONFIG["regime_window"]
    close = df["close"].values
    high = df["high"].values
    low = df["low"].values
    n = len(df)

    # --- Pre-compute rolling stats for every bar ---
    abs_rets = np.full(n, np.nan)
    vols     = np.full(n, np.nan)
    ranges_  = np.full(n, np.nan)
    rec_vols = np.full(n, np.nan)

    for i in range(w, n):
        wc = close[i - w:i]
        wh = high[i - w:i]
        wl = low[i - w:i]

        daily_rets = np.diff(wc) / (wc[:-1] + 1e-10)
        abs_rets[i] = abs((wc[-1] - wc[0]) / (wc[0] + 1e-10))
        vols[i]     = np.std(daily_rets)
        ranges_[i]  = (wh.max() - wl.min()) / (wc.mean() + 1e-10)

        start = max(0, i - 10)
        rc = close[start:i]
        if len(rc) > 1:
            rec_vols[i] = np.std(np.diff(rc) / (rc[:-1] + 1e-10))
        else:
            rec_vols[i] = vols[i]

    # --- Derive adaptive thresholds from percentiles ---
    valid = ~np.isnan(vols)
    if valid.sum() == 0:
        return np.full(n, 1)

    p_ret_70  = np.nanpercentile(abs_rets[valid], 70)   # trending threshold
    p_vol_30  = np.nanpercentile(vols[valid], 30)        # low-vol ceiling for trending
    p_vol_75  = np.nanpercentile(vols[valid], 75)        # high-vol threshold
    p_range_85 = np.nanpercentile(ranges_[valid], 85)    # breakout range threshold

    print(f"    Adaptive thresholds: ret_70p={p_ret_70:.5f}, "
          f"vol_30p={p_vol_30:.5f}, vol_75p={p_vol_75:.5f}, "
          f"range_85p={p_range_85:.5f}")

    # --- Classify ---
    labels = np.full(n, 1)  # default = ranging

    for i in range(w, n):
        if np.isnan(vols[i]):
            continue
        r   = abs_rets[i]
        v   = vols[i]
        rng = ranges_[i]
        rv  = rec_vols[i]

        # Breakout: recent vol spike + extreme range
        if rv > CONFIG["breakout_vol_mult"] * v and rng > p_range_85:
            labels[i] = 3
        # Trending: strong directional move with relatively low vol
        elif r > p_ret_70 and v < p_vol_30:
            labels[i] = 0
        # High volatility: elevated vol without clear direction
        elif v > p_vol_75:
            labels[i] = 2
        # Ranging: everything else
        else:
            labels[i] = 1

    return labels


# ---------------------------------------------------------------------------
# MQL5 compatible scaler export
# ---------------------------------------------------------------------------
def save_scaler_for_mql5(mean: np.ndarray, scale: np.ndarray, output_dir: str, model_name: str):
    """Save scaler as raw binary doubles readable by MQL5 FileReadArray(double[])."""
    os.makedirs(output_dir, exist_ok=True)
    mean_path  = os.path.join(output_dir, f"{model_name}_mean.npy")
    scale_path = os.path.join(output_dir, f"{model_name}_scale.npy")

    with open(mean_path, "wb") as f:
        for v in mean.astype(np.float64):
            f.write(struct.pack("d", v))

    with open(scale_path, "wb") as f:
        for v in scale.astype(np.float64):
            f.write(struct.pack("d", v))

    print(f"  Scaler mean  -> {mean_path} ({len(mean)} doubles)")
    print(f"  Scaler scale -> {scale_path} ({len(scale)} doubles)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("=" * 70)
    print(" SMC Swing EA - Market Regime Detector Training")
    print(f" Period: {CONFIG['date_from']:%Y.%m.%d} ~ {CONFIG['date_to']:%Y.%m.%d}")
    print(f" Excluded: Dec 25 ~ Jan 5 each year (holiday noise)")
    print("=" * 70)

    # --- 1. Load data ---
    print("\n[1/6] Loading data...")
    all_features = []

    for sym in CONFIG["symbols"]:
        print(f"\n  --- {sym} ---")
        df = load_mt5_data(sym, CONFIG["timeframe_d1"],
                           CONFIG["date_from"], CONFIG["date_to"]) if _MT5 else pd.DataFrame()
        if df.empty:
            print(f"  {sym}: MT5 unavailable, using synthetic data")
            df = generate_synthetic_ohlcv(
                n_bars=0,
                seed=CONFIG["random_seed"] + hash(sym) % 1000,
                date_from=CONFIG["date_from"],
                date_to=CONFIG["date_to"],
            )
        else:
            print(f"  {sym}: Loaded {len(df)} bars from MT5")

        # Apply holiday noise filter
        df = filter_holiday_noise(df)

        feat = build_features_for_df(df)
        regime_labels = create_regime_labels(df)
        feat["label"] = regime_labels
        feat.dropna(inplace=True)
        print(f"  {sym}: {len(feat)} samples after feature engineering")

        all_features.append(feat)

    combined = pd.concat(all_features, ignore_index=True)
    combined.dropna(inplace=True)
    feature_cols = [c for c in combined.columns if c != "label"]

    assert len(feature_cols) == N_FEATURES, \
        f"Expected {N_FEATURES} features, got {len(feature_cols)}: {feature_cols}"

    X = combined[feature_cols].values.astype(np.float32)
    y = combined["label"].values.astype(int)

    print(f"\n  Total samples: {len(X):,}")
    print(f"  Features: {len(feature_cols)}")
    for cls, name in REGIME_MAP.items():
        cnt = (y == cls).sum()
        print(f"  Class {cls} ({name}): {cnt:,} ({100*cnt/len(y):.1f}%)")

    # --- 2. Split (chronological) ---
    print("\n[2/6] Splitting data...")
    split_idx = int(len(X) * (1 - CONFIG["test_ratio"]))
    X_train, X_test = X[:split_idx], X[split_idx:]
    y_train, y_test = y[:split_idx], y[split_idx:]
    print(f"  Train: {len(X_train):,}, Test: {len(X_test):,}")

    # --- 3. Scale ---
    print("\n[3/6] Scaling features...")
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled  = scaler.transform(X_test)

    # --- 4. Train RandomForest ---
    print("\n[4/6] Training RandomForest...")
    model = RandomForestClassifier(
        **CONFIG["rf_params"],
        random_state=CONFIG["random_seed"],
    )
    model.fit(X_train_scaled, y_train)

    # --- 5. Evaluate ---
    print("\n[5/6] Evaluating...")
    y_pred = model.predict(X_test_scaled)
    acc = accuracy_score(y_test, y_pred)

    print(f"\n  Accuracy: {acc:.4f}")
    all_labels = list(range(NUM_CLASSES))
    print("\n  Classification Report:")
    print(classification_report(y_test, y_pred,
                                labels=all_labels,
                                target_names=list(REGIME_MAP.values()),
                                zero_division=0))

    print("  Confusion Matrix:")
    cm = confusion_matrix(y_test, y_pred, labels=all_labels)
    print(pd.DataFrame(cm, index=REGIME_MAP.values(), columns=REGIME_MAP.values()))

    # Warn if class distribution is severely imbalanced
    unique_train = np.unique(y_train)
    unique_test  = np.unique(y_test)
    if len(unique_train) < NUM_CLASSES:
        print(f"\n  WARNING: Training data has only {len(unique_train)}/{NUM_CLASSES} classes: "
              f"{[REGIME_MAP[c] for c in unique_train]}")
    if len(unique_test) < NUM_CLASSES:
        print(f"  WARNING: Test data has only {len(unique_test)}/{NUM_CLASSES} classes: "
              f"{[REGIME_MAP[c] for c in unique_test]}")

    # Feature importance
    importance = sorted(zip(feature_cols, model.feature_importances_),
                       key=lambda x: x[1], reverse=True)
    print("\n  Top-10 Features:")
    for fname, fval in importance[:10]:
        print(f"    {fname:30s} {fval:.4f}")

    # --- 6. Export ---
    print("\n[6/6] Exporting ONNX model + scaler...")
    output_dir = CONFIG["output_dir"]
    os.makedirs(output_dir, exist_ok=True)

    # ONNX export (zipmap=False to output tensor instead of map for MQL5 compatibility)
    try:
        from skl2onnx import convert_sklearn
        from skl2onnx.common.data_types import FloatTensorType
        import onnx

        initial_type = [("input", FloatTensorType([None, N_FEATURES]))]
        onnx_model = convert_sklearn(
            model, initial_types=initial_type,
            options={id(model): {'zipmap': False}},
            target_opset=15
        )
        onnx_path = os.path.join(output_dir, f"{CONFIG['model_name']}.onnx")
        onnx.save_model(onnx_model, onnx_path)
        print(f"  ONNX model -> {onnx_path}")
    except Exception as e:
        print(f"  ERROR: ONNX export failed: {e}")
        return

    # Scaler export (MQL5 binary format)
    save_scaler_for_mql5(scaler.mean_, scaler.scale_, output_dir, CONFIG["model_name"])

    print("\n" + "=" * 70)
    print(" Training complete!")
    print(f" Model:  {CONFIG['model_name']}")
    print(f" ONNX:   {onnx_path}")
    print(f" Deploy: Copy files from {output_dir} to MQL5/Files/models/")
    print("=" * 70)


if __name__ == "__main__":
    main()
