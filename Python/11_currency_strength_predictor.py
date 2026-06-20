"""
11 - 通貨強弱予測器 / Currency Strength Predictor
===================================================
LightGBMマルチ出力回帰: 28通貨ペアの価格変動を特徴量として、
N本先の8通貨の強弱値を予測する。MultiOutputRegressorラッパーを使用。

LightGBM multi-output regression: Uses 28 pair price changes as features
to predict 8 currency strength values N bars ahead.
Uses sklearn MultiOutputRegressor wrapper.
"""
import sys
import os
import warnings
import numpy as np
import pandas as pd
from itertools import combinations

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
    'model_name': 'currency_strength_predictor',
    'output_dir': str(default_model_dir()),
    'test_size': 0.2,
    'random_state': 42,
    'prediction_horizon': 12,
    'lookback_periods': [1, 3, 6, 12, 24],
    'lgbm_params': {
        'n_estimators': 300,
        'max_depth': 5,
        'learning_rate': 0.05,
        'num_leaves': 31,
        'subsample': 0.8,
        'colsample_bytree': 0.8,
        'reg_alpha': 0.1,
        'reg_lambda': 1.0,
        'verbose': -1,
    },
}

CURRENCIES = ['EUR', 'USD', 'GBP', 'JPY', 'AUD', 'NZD', 'CAD', 'CHF']

PAIRS_28 = [
    'EURUSD', 'EURJPY', 'EURGBP', 'EURAUD', 'EURNZD', 'EURCAD', 'EURCHF',
    'GBPUSD', 'GBPJPY', 'GBPAUD', 'GBPNZD', 'GBPCAD', 'GBPCHF',
    'AUDUSD', 'AUDJPY', 'AUDNZD', 'AUDCAD', 'AUDCHF',
    'NZDUSD', 'NZDJPY', 'NZDCAD', 'NZDCHF',
    'USDCAD', 'USDCHF', 'USDJPY',
    'CADJPY', 'CADCHF',
    'CHFJPY',
]


def generate_synthetic_pair_data(n_bars: int) -> pd.DataFrame:
    """Generate synthetic price data for all 28 pairs."""
    np.random.seed(CONFIG['random_state'])
    data = {}
    base_prices = {p: 1.0 + np.random.uniform(-0.5, 0.5) for p in PAIRS_28}
    # JPY pairs have higher prices
    for p in PAIRS_28:
        if 'JPY' in p:
            base_prices[p] = 100.0 + np.random.uniform(-20, 20)

    for pair in PAIRS_28:
        returns = np.random.normal(0, 0.0003, n_bars)
        prices = base_prices[pair] + np.cumsum(returns)
        data[pair] = prices
    return pd.DataFrame(data)


def create_features(df: pd.DataFrame) -> pd.DataFrame:
    """Create multi-period return features for all 28 pairs."""
    feat = pd.DataFrame(index=df.index)
    for pair in PAIRS_28:
        for period in CONFIG['lookback_periods']:
            # Price change (return)
            feat[f'{pair}_ret_{period}'] = df[pair].pct_change(period)
            # Volatility (rolling std of returns)
            feat[f'{pair}_vol_{period}'] = df[pair].pct_change().rolling(period).std()
        # Cross-pair momentum
        feat[f'{pair}_mom'] = df[pair].pct_change(12) - df[pair].pct_change(24)
    return feat


def compute_currency_strength(df: pd.DataFrame, shift: int = 0) -> pd.DataFrame:
    """
    Compute individual currency strength from pair returns.
    Each currency's strength = average return of pairs where it is the base
    minus average return of pairs where it is the quote.
    """
    horizon = CONFIG['prediction_horizon']
    pair_returns = pd.DataFrame(index=df.index)
    for pair in PAIRS_28:
        if shift > 0:
            pair_returns[pair] = df[pair].pct_change(horizon).shift(-shift)
        else:
            pair_returns[pair] = df[pair].pct_change(horizon)

    strength = pd.DataFrame(index=df.index)
    for ccy in CURRENCIES:
        base_pairs = [p for p in PAIRS_28 if p[:3] == ccy]
        quote_pairs = [p for p in PAIRS_28 if p[3:] == ccy]
        base_avg = pair_returns[base_pairs].mean(axis=1) if base_pairs else 0
        quote_avg = pair_returns[quote_pairs].mean(axis=1) if quote_pairs else 0
        strength[f'{ccy}_strength'] = base_avg - quote_avg
    return strength


def create_labels(df: pd.DataFrame) -> pd.DataFrame:
    """Create future currency strength labels."""
    return compute_currency_strength(df, shift=CONFIG['prediction_horizon'])


def main():
    """Main training pipeline for currency strength predictor."""
    print("=" * 70)
    print("11 - Currency Strength Predictor (LightGBM Multi-Output)")
    print("=" * 70)

    # --- Data Loading ---
    print("\n[1/5] Loading data for 28 currency pairs...")
    df = generate_synthetic_pair_data(CONFIG['n_bars'])
    print(f"  Loaded {len(df)} bars for {len(PAIRS_28)} pairs")

    # --- Feature Engineering ---
    print("\n[2/5] Computing pair return features...")
    features = create_features(df)
    print(f"  Feature matrix: {features.shape}")

    # --- Label Creation ---
    print("\n[3/5] Computing future currency strength labels...")
    labels = create_labels(df)
    label_cols = labels.columns.tolist()
    print(f"  Targets: {label_cols}")

    # Merge and clean
    combined = pd.concat([features, labels], axis=1).dropna()
    X = combined[features.columns].values
    Y = combined[label_cols].values
    print(f"  Clean samples: {len(combined)}")

    # --- Train/Test Split ---
    split_idx = int(len(X) * (1 - CONFIG['test_size']))
    X_train, X_test = X[:split_idx], X[split_idx:]
    Y_train, Y_test = Y[:split_idx], Y[split_idx:]
    print(f"  Train: {len(X_train)}, Test: {len(X_test)}")

    # --- Model Training ---
    print("\n[4/5] Training LightGBM with MultiOutputRegressor...")
    from lightgbm import LGBMRegressor
    from sklearn.multioutput import MultiOutputRegressor
    from sklearn.metrics import mean_squared_error, r2_score

    base_model = LGBMRegressor(**CONFIG['lgbm_params'],
                                random_state=CONFIG['random_state'])
    model = MultiOutputRegressor(base_model, n_jobs=-1)
    model.fit(X_train, Y_train)

    Y_pred = model.predict(X_test)
    print("\n  Per-Currency Results:")
    print(f"  {'Currency':<12} {'RMSE':>10} {'R2':>10}")
    print(f"  {'-'*32}")
    for i, ccy in enumerate(CURRENCIES):
        rmse = np.sqrt(mean_squared_error(Y_test[:, i], Y_pred[:, i]))
        r2 = r2_score(Y_test[:, i], Y_pred[:, i])
        print(f"  {ccy:<12} {rmse:>10.6f} {r2:>10.4f}")

    overall_rmse = np.sqrt(mean_squared_error(Y_test, Y_pred))
    overall_r2 = r2_score(Y_test.flatten(), Y_pred.flatten())
    print(f"\n  Overall: RMSE={overall_rmse:.6f}, R2={overall_r2:.4f}")

    # --- Feature Importance (averaged across outputs) ---
    feat_names = list(features.columns)
    avg_importance = np.mean(
        [est.feature_importances_ for est in model.estimators_], axis=0
    )
    top_idx = np.argsort(avg_importance)[-10:][::-1]
    print("\n  Top 10 Features (averaged):")
    for idx in top_idx:
        print(f"    {feat_names[idx]}: {avg_importance[idx]:.1f}")

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
