"""
12 - SL/TP最適化器 / Stop-Loss & Take-Profit Optimizer
========================================================
XGBoostマルチ出力回帰: エントリーコンテキスト(ボラティリティ、トレンド、
OBサイズ、FVGサイズ)から、最適なSLとTP(pips)を予測する。

XGBoost multi-output regression: Predicts optimal SL and TP in pips
from entry context features (volatility, trend, order block size, FVG size),
measured from actual trade outcomes.
"""
import sys
import os
import warnings
import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common.paths import default_model_dir

try:
    from common.data_loader import DataLoader
    from common.feature_base import FeatureEngineer
    from common.model_utils import ModelTrainer
except ImportError:
    DataLoader = FeatureEngineer = ModelTrainer = None

warnings.filterwarnings("ignore")

CONFIG = {
    'symbol': 'EURUSD',
    'timeframe': 'M5',
    'n_bars': 100000,
    'model_name': 'sl_tp_optimizer',
    'output_dir': str(default_model_dir()),
    'test_size': 0.2,
    'random_state': 42,
    'pip_value': 0.0001,
    'max_sl_pips': 50,
    'max_tp_pips': 100,
    'future_window': 48,
    'xgb_params': {
        'n_estimators': 400,
        'max_depth': 6,
        'learning_rate': 0.05,
        'subsample': 0.8,
        'colsample_bytree': 0.8,
        'reg_alpha': 0.1,
        'reg_lambda': 1.0,
    },
}


def generate_synthetic_data(n_bars: int = 100000) -> pd.DataFrame:
    """Generate synthetic OHLCV data when MT5 is unavailable."""
    np.random.seed(CONFIG['random_state'])
    returns = np.random.normal(0, 0.0005, n_bars)
    close = 1.1 + np.cumsum(returns)
    high = close + np.abs(np.random.normal(0, 0.0003, n_bars))
    low = close - np.abs(np.random.normal(0, 0.0003, n_bars))
    opn = close + np.random.normal(0, 0.0001, n_bars)
    vol = np.random.randint(100, 10000, n_bars).astype(float)
    return pd.DataFrame({
        'open': opn, 'high': high, 'low': low,
        'close': close, 'tick_volume': vol
    })


def create_features(df: pd.DataFrame) -> pd.DataFrame:
    """Create entry context features: volatility, trend, OB/FVG proxies."""
    feat = pd.DataFrame(index=df.index)

    # --- Volatility features ---
    tr = pd.concat([
        df['high'] - df['low'],
        (df['high'] - df['close'].shift(1)).abs(),
        (df['low'] - df['close'].shift(1)).abs()
    ], axis=1).max(axis=1)
    feat['atr_14'] = tr.rolling(14).mean() / CONFIG['pip_value']
    feat['atr_50'] = tr.rolling(50).mean() / CONFIG['pip_value']
    feat['atr_ratio'] = feat['atr_14'] / (feat['atr_50'] + 1e-10)
    feat['volatility_pct'] = df['close'].pct_change().rolling(20).std() * 100

    # --- Trend features ---
    feat['ema_9'] = df['close'].ewm(span=9).mean()
    feat['ema_21'] = df['close'].ewm(span=21).mean()
    feat['ema_50'] = df['close'].ewm(span=50).mean()
    feat['trend_strength'] = (feat['ema_9'] - feat['ema_50']) / (feat['atr_14'] * CONFIG['pip_value'] + 1e-10)
    feat['trend_direction'] = np.sign(feat['ema_9'] - feat['ema_21'])

    # --- Momentum ---
    delta = df['close'].diff()
    gain = delta.clip(lower=0).rolling(14).mean()
    loss = (-delta.clip(upper=0)).rolling(14).mean()
    feat['rsi'] = 100 - 100 / (1 + gain / (loss + 1e-10))
    feat['momentum_12'] = df['close'].pct_change(12)

    # --- Order Block proxy ---
    body = (df['close'] - df['open']).abs()
    feat['ob_size_pips'] = body / CONFIG['pip_value']
    feat['ob_strength'] = body / (tr.rolling(14).mean() + 1e-10)
    feat['ob_bullish'] = ((df['close'] > df['open']) & (feat['ob_strength'] > 1.5)).astype(float)
    feat['ob_bearish'] = ((df['close'] < df['open']) & (feat['ob_strength'] > 1.5)).astype(float)

    # --- FVG proxy ---
    feat['fvg_up_pips'] = (df['low'] - df['high'].shift(2)).clip(lower=0) / CONFIG['pip_value']
    feat['fvg_down_pips'] = (df['low'].shift(2) - df['high']).clip(lower=0) / CONFIG['pip_value']
    feat['fvg_size'] = feat['fvg_up_pips'] + feat['fvg_down_pips']

    # --- Volume context ---
    feat['volume_ratio'] = df['tick_volume'] / df['tick_volume'].rolling(20).mean()

    # Remove temporary EMA columns
    feat.drop(columns=['ema_9', 'ema_21', 'ema_50'], inplace=True)
    return feat


def create_labels(df: pd.DataFrame) -> pd.DataFrame:
    """
    Create optimal SL and TP labels from future price action.
    For each bar, look ahead and compute:
    - Optimal SL: max adverse excursion (MAE) in pips
    - Optimal TP: max favorable excursion (MFE) in pips
    Simulates both long and short entries, picks direction by trend.
    """
    window = CONFIG['future_window']
    pip = CONFIG['pip_value']
    sl_vals = np.full(len(df), np.nan)
    tp_vals = np.full(len(df), np.nan)

    close = df['close'].values
    high = df['high'].values
    low = df['low'].values
    ema_fast = pd.Series(close).ewm(span=9).mean().values
    ema_slow = pd.Series(close).ewm(span=21).mean().values

    for i in range(len(df) - window):
        entry = close[i]
        future_high = high[i + 1:i + 1 + window]
        future_low = low[i + 1:i + 1 + window]
        is_long = ema_fast[i] > ema_slow[i]

        if is_long:
            mae = (entry - future_low.min()) / pip
            mfe = (future_high.max() - entry) / pip
        else:
            mae = (future_high.max() - entry) / pip
            mfe = (entry - future_low.min()) / pip

        sl_vals[i] = np.clip(mae * 1.1, 5, CONFIG['max_sl_pips'])
        tp_vals[i] = np.clip(mfe * 0.8, 5, CONFIG['max_tp_pips'])

    return pd.DataFrame({'optimal_sl_pips': sl_vals, 'optimal_tp_pips': tp_vals},
                        index=df.index)


def main():
    """Main training pipeline for SL/TP optimizer."""
    print("=" * 70)
    print("12 - SL/TP Optimizer (XGBoost Multi-Output Regression)")
    print("=" * 70)

    # --- Data Loading ---
    print("\n[1/5] Loading data...")
    df = generate_synthetic_data(CONFIG['n_bars'])
    print(f"  Loaded {len(df)} bars")

    # --- Feature Engineering ---
    print("\n[2/5] Computing entry context features...")
    features = create_features(df)
    print(f"  Features: {features.shape}")

    # --- Label Creation ---
    print("\n[3/5] Computing optimal SL/TP from future price action...")
    labels = create_labels(df)
    print(f"  SL stats (pips): mean={labels['optimal_sl_pips'].mean():.1f}, "
          f"std={labels['optimal_sl_pips'].std():.1f}")
    print(f"  TP stats (pips): mean={labels['optimal_tp_pips'].mean():.1f}, "
          f"std={labels['optimal_tp_pips'].std():.1f}")

    # Merge and clean
    combined = pd.concat([features, labels], axis=1).dropna()
    feature_cols = list(features.columns)
    X = combined[feature_cols].values
    Y = combined[['optimal_sl_pips', 'optimal_tp_pips']].values
    print(f"  Clean samples: {len(combined)}")

    # --- Train/Test Split ---
    split_idx = int(len(X) * (1 - CONFIG['test_size']))
    X_train, X_test = X[:split_idx], X[split_idx:]
    Y_train, Y_test = Y[:split_idx], Y[split_idx:]
    print(f"  Train: {len(X_train)}, Test: {len(X_test)}")

    # --- Model Training ---
    print("\n[4/5] Training XGBoost with MultiOutputRegressor...")
    from xgboost import XGBRegressor
    from sklearn.multioutput import MultiOutputRegressor
    from sklearn.metrics import mean_squared_error, mean_absolute_error, r2_score

    base = XGBRegressor(**CONFIG['xgb_params'], random_state=CONFIG['random_state'])
    model = MultiOutputRegressor(base, n_jobs=-1)
    model.fit(X_train, Y_train)

    Y_pred = model.predict(X_test)
    target_names = ['SL (pips)', 'TP (pips)']
    print(f"\n  {'Target':<12} {'RMSE':>8} {'MAE':>8} {'R2':>8}")
    print(f"  {'-'*36}")
    for i, name in enumerate(target_names):
        rmse = np.sqrt(mean_squared_error(Y_test[:, i], Y_pred[:, i]))
        mae = mean_absolute_error(Y_test[:, i], Y_pred[:, i])
        r2 = r2_score(Y_test[:, i], Y_pred[:, i])
        print(f"  {name:<12} {rmse:>8.2f} {mae:>8.2f} {r2:>8.4f}")

    # --- Feature Importance ---
    print("\n  Feature Importance (SL model):")
    imp_sl = model.estimators_[0].feature_importances_
    top_idx = np.argsort(imp_sl)[-8:][::-1]
    for idx in top_idx:
        print(f"    {feature_cols[idx]}: {imp_sl[idx]:.4f}")

    # --- Export ---
    print("\n[5/5] Exporting model...")
    os.makedirs(CONFIG['output_dir'], exist_ok=True)
    model_path = os.path.join(CONFIG['output_dir'], CONFIG['model_name'])

    import joblib
    joblib.dump(model, f"{model_path}.pkl")
    print(f"  Saved: {model_path}.pkl")

    try:
        from skl2onnx import convert_sklearn
        from skl2onnx.common.data_types import FloatTensorType
        import onnx
        initial_type = [('input', FloatTensorType([None, X_train.shape[1]]))]
        onnx_model = convert_sklearn(model, initial_types=initial_type,
                                     target_opset=15)
        onnx.save_model(onnx_model, f"{model_path}.onnx")
        print(f"  ONNX exported: {model_path}.onnx")
    except Exception as e:
        print(f"  ONNX export skipped: {e}")

    print("\n" + "=" * 70)
    print("Training complete!")
    print("=" * 70)


if __name__ == '__main__':
    main()
