"""
09 - マルチタイムフレーム合流スコアラー / Multi-Timeframe Confluence Scorer
=============================================================================
XGBoost回帰モデル: 複数タイムフレーム(M5, M15, H1, H4)のSMC特徴量を統合し、
トレード収益性スコア(0-1)を予測する。

XGBoost regression model: Collects SMC features from multiple timeframes
(M5, M15, H1, H4) and merges them to predict a trade profitability score (0-1).
"""
import sys
import os
import warnings
import numpy as np
import pandas as pd
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    from common.data_loader import DataLoader
    from common.feature_base import FeatureEngineer
    from common.model_utils import ModelTrainer
except ImportError:
    DataLoader = FeatureEngineer = ModelTrainer = None

warnings.filterwarnings("ignore")

CONFIG = {
    'symbol': 'EURUSD',
    'timeframes': ['M5', 'M15', 'H1', 'H4'],
    'base_timeframe': 'M5',
    'n_bars': 100000,
    'model_name': 'mtf_confluence_scorer',
    'output_dir': '../Files/models/',
    'test_size': 0.2,
    'random_state': 42,
    'xgb_params': {
        'n_estimators': 500,
        'max_depth': 6,
        'learning_rate': 0.05,
        'subsample': 0.8,
        'colsample_bytree': 0.8,
        'reg_alpha': 0.1,
        'reg_lambda': 1.0,
        'objective': 'reg:squarederror',
    },
}


def generate_synthetic_data(n_bars: int = 100000) -> dict:
    """Generate synthetic OHLCV data for each timeframe when MT5 unavailable."""
    np.random.seed(CONFIG['random_state'])
    tf_ratios = {'M5': 1, 'M15': 3, 'H1': 12, 'H4': 48}
    datasets = {}
    base_price = 1.1000
    for tf in CONFIG['timeframes']:
        n = n_bars // tf_ratios[tf]
        returns = np.random.normal(0, 0.0005, n)
        close = base_price + np.cumsum(returns)
        high = close + np.abs(np.random.normal(0, 0.0003, n))
        low = close - np.abs(np.random.normal(0, 0.0003, n))
        opn = close + np.random.normal(0, 0.0001, n)
        volume = np.random.randint(100, 10000, n).astype(float)
        dates = pd.date_range('2020-01-01', periods=n, freq='5min' if tf == 'M5'
                              else '15min' if tf == 'M15'
                              else '1h' if tf == 'H1' else '4h')
        datasets[tf] = pd.DataFrame({
            'time': dates, 'open': opn, 'high': high, 'low': low,
            'close': close, 'tick_volume': volume
        })
    return datasets


def compute_smc_features(df: pd.DataFrame, prefix: str) -> pd.DataFrame:
    """Compute SMC/ICT features for a single timeframe."""
    feat = pd.DataFrame(index=df.index)
    # Trend: EMA crossovers
    feat[f'{prefix}_ema_fast'] = df['close'].ewm(span=9).mean()
    feat[f'{prefix}_ema_slow'] = df['close'].ewm(span=21).mean()
    feat[f'{prefix}_trend'] = (feat[f'{prefix}_ema_fast'] - feat[f'{prefix}_ema_slow']) / df['close']
    # Volatility: ATR proxy
    tr = pd.concat([
        df['high'] - df['low'],
        (df['high'] - df['close'].shift(1)).abs(),
        (df['low'] - df['close'].shift(1)).abs()
    ], axis=1).max(axis=1)
    feat[f'{prefix}_atr'] = tr.rolling(14).mean() / df['close']
    # Order Block proxy: large candle body relative to ATR
    body = (df['close'] - df['open']).abs()
    feat[f'{prefix}_ob_strength'] = body / (tr.rolling(14).mean() + 1e-10)
    # FVG proxy: gap between current low and previous high (bearish) or vice versa
    feat[f'{prefix}_fvg_up'] = (df['low'] - df['high'].shift(2)).clip(lower=0) / df['close']
    feat[f'{prefix}_fvg_down'] = (df['low'].shift(2) - df['high']).clip(lower=0) / df['close']
    # Momentum: RSI-like
    delta = df['close'].diff()
    gain = delta.clip(lower=0).rolling(14).mean()
    loss = (-delta.clip(upper=0)).rolling(14).mean()
    feat[f'{prefix}_rsi'] = 100 - 100 / (1 + gain / (loss + 1e-10))
    # Volume profile
    feat[f'{prefix}_vol_ratio'] = df['tick_volume'] / df['tick_volume'].rolling(20).mean()
    return feat


def merge_timeframes(datasets: dict) -> pd.DataFrame:
    """Merge multi-timeframe features onto the base M5 timeframe using asof join."""
    base_tf = CONFIG['base_timeframe']
    base_df = datasets[base_tf].copy()
    base_df['time'] = pd.to_datetime(base_df['time'])
    base_features = compute_smc_features(base_df, 'M5')
    merged = pd.concat([base_df[['time', 'close']], base_features], axis=1)
    for tf in CONFIG['timeframes']:
        if tf == base_tf:
            continue
        htf_df = datasets[tf].copy()
        htf_df['time'] = pd.to_datetime(htf_df['time'])
        htf_features = compute_smc_features(htf_df, tf)
        htf_merged = pd.concat([htf_df[['time']], htf_features], axis=1)
        htf_merged = htf_merged.sort_values('time')
        merged = merged.sort_values('time')
        merged = pd.merge_asof(merged, htf_merged, on='time', direction='backward')
    return merged


def create_labels(df: pd.DataFrame, horizon: int = 12) -> pd.Series:
    """Create profitability score (0-1) based on future price movement."""
    future_ret = (df['close'].shift(-horizon) - df['close']) / df['close']
    # Normalize to 0-1 using sigmoid-like mapping
    score = 1 / (1 + np.exp(-future_ret * 10000))
    return score


def main():
    """Main training pipeline for multi-timeframe confluence scorer."""
    print("=" * 70)
    print("09 - Multi-Timeframe Confluence Scorer (XGBoost Regression)")
    print("=" * 70)

    # --- Data Loading ---
    print("\n[1/5] Loading data...")
    datasets = generate_synthetic_data(CONFIG['n_bars'])
    for tf, df in datasets.items():
        print(f"  {tf}: {len(df)} bars")

    # --- Feature Engineering ---
    print("\n[2/5] Computing multi-timeframe SMC features...")
    merged = merge_timeframes(datasets)
    print(f"  Merged dataset: {merged.shape}")

    # --- Label Creation ---
    print("\n[3/5] Creating profitability labels...")
    merged['label'] = create_labels(merged)
    merged.dropna(inplace=True)
    print(f"  Clean samples: {len(merged)}")
    print(f"  Label stats: mean={merged['label'].mean():.4f}, "
          f"std={merged['label'].std():.4f}")

    # --- Train/Test Split ---
    feature_cols = [c for c in merged.columns if c not in ['time', 'close', 'label']]
    X = merged[feature_cols].values
    y = merged['label'].values
    split_idx = int(len(X) * (1 - CONFIG['test_size']))
    X_train, X_test = X[:split_idx], X[split_idx:]
    y_train, y_test = y[:split_idx], y[split_idx:]
    print(f"  Train: {len(X_train)}, Test: {len(X_test)}")

    # --- Model Training ---
    print("\n[4/5] Training XGBoost regressor...")
    from xgboost import XGBRegressor
    from sklearn.metrics import mean_squared_error, r2_score, mean_absolute_error

    model = XGBRegressor(**CONFIG['xgb_params'], random_state=CONFIG['random_state'])
    model.fit(
        X_train, y_train,
        eval_set=[(X_test, y_test)],
        verbose=50,
    )
    y_pred = model.predict(X_test)
    rmse = np.sqrt(mean_squared_error(y_test, y_pred))
    mae = mean_absolute_error(y_test, y_pred)
    r2 = r2_score(y_test, y_pred)
    print(f"\n  Results: RMSE={rmse:.6f}, MAE={mae:.6f}, R2={r2:.4f}")

    # --- Feature Importance ---
    importance = dict(zip(feature_cols, model.feature_importances_))
    top_features = sorted(importance.items(), key=lambda x: x[1], reverse=True)[:10]
    print("\n  Top 10 Features:")
    for fname, fval in top_features:
        print(f"    {fname}: {fval:.4f}")

    # --- Export ---
    print("\n[5/5] Exporting model...")
    os.makedirs(CONFIG['output_dir'], exist_ok=True)
    model_path = os.path.join(CONFIG['output_dir'], CONFIG['model_name'])
    model.save_model(f"{model_path}.json")
    print(f"  Saved: {model_path}.json")

    try:
        from skl2onnx import convert_sklearn
        from skl2onnx.common.data_types import FloatTensorType
        import onnx
        initial_type = [('input', FloatTensorType([None, len(feature_cols)]))]
        onnx_model = convert_sklearn(model, initial_types=initial_type)
        onnx.save_model(onnx_model, f"{model_path}.onnx")
        print(f"  ONNX exported: {model_path}.onnx")
    except Exception as e:
        print(f"  ONNX export skipped: {e}")

    print("\n" + "=" * 70)
    print("Training complete!")
    print("=" * 70)


if __name__ == '__main__':
    main()
