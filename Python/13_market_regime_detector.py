"""
13 - マーケットレジーム検出器 / Market Regime Detector
=======================================================
RandomForest 5クラス分類: ボラティリティ・トレンド・モメンタムの複合特徴量から、
マーケットレジーム(trending_bull, trending_bear, ranging, volatile, breakout)を分類。

RandomForest 5-class classifier: Uses composite volatility, trend, and
momentum features to classify market regime (trending_bull, trending_bear,
ranging, volatile, breakout).
"""
import sys
import os
import warnings
import numpy as np
import pandas as pd

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
    'timeframe': 'M5',
    'n_bars': 100000,
    'model_name': 'market_regime_detector',
    'output_dir': '../Files/models/',
    'test_size': 0.2,
    'random_state': 42,
    'regime_window': 50,
    'rf_params': {
        'n_estimators': 500,
        'max_depth': 10,
        'min_samples_split': 20,
        'min_samples_leaf': 10,
        'max_features': 'sqrt',
        'class_weight': 'balanced',
    },
}

REGIME_CLASSES = ['trending_bull', 'trending_bear', 'ranging', 'volatile', 'breakout']
NUM_CLASSES = len(REGIME_CLASSES)


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
    """Create composite volatility, trend, and momentum features."""
    feat = pd.DataFrame(index=df.index)
    close = df['close']

    # === Volatility Composite ===
    tr = pd.concat([
        df['high'] - df['low'],
        (df['high'] - close.shift(1)).abs(),
        (df['low'] - close.shift(1)).abs()
    ], axis=1).max(axis=1)
    feat['atr_14'] = tr.rolling(14).mean()
    feat['atr_50'] = tr.rolling(50).mean()
    feat['atr_ratio'] = feat['atr_14'] / (feat['atr_50'] + 1e-10)
    feat['volatility_20'] = close.pct_change().rolling(20).std()
    feat['volatility_50'] = close.pct_change().rolling(50).std()
    feat['vol_expansion'] = feat['volatility_20'] / (feat['volatility_50'] + 1e-10)
    feat['range_pct'] = (df['high'].rolling(20).max() - df['low'].rolling(20).min()) / close
    feat['bollinger_width'] = (close.rolling(20).std() * 4) / close

    # === Trend Composite ===
    for span in [9, 21, 50, 100]:
        feat[f'ema_{span}'] = close.ewm(span=span).mean()
    feat['trend_9_21'] = (feat['ema_9'] - feat['ema_21']) / close
    feat['trend_21_50'] = (feat['ema_21'] - feat['ema_50']) / close
    feat['trend_50_100'] = (feat['ema_50'] - feat['ema_100']) / close
    # ADX proxy: directional movement strength
    up_move = df['high'].diff()
    down_move = -df['low'].diff()
    plus_dm = np.where((up_move > down_move) & (up_move > 0), up_move, 0)
    minus_dm = np.where((down_move > up_move) & (down_move > 0), down_move, 0)
    plus_di = pd.Series(plus_dm, index=df.index).rolling(14).mean() / (feat['atr_14'] + 1e-10)
    minus_di = pd.Series(minus_dm, index=df.index).rolling(14).mean() / (feat['atr_14'] + 1e-10)
    feat['adx_proxy'] = ((plus_di - minus_di).abs() / (plus_di + minus_di + 1e-10)).rolling(14).mean()
    feat['ema_alignment'] = (
        np.sign(feat['trend_9_21']) + np.sign(feat['trend_21_50']) +
        np.sign(feat['trend_50_100'])
    ) / 3.0

    # === Momentum Composite ===
    delta = close.diff()
    gain = delta.clip(lower=0).rolling(14).mean()
    loss = (-delta.clip(upper=0)).rolling(14).mean()
    feat['rsi'] = 100 - 100 / (1 + gain / (loss + 1e-10))
    feat['momentum_6'] = close.pct_change(6)
    feat['momentum_12'] = close.pct_change(12)
    feat['momentum_24'] = close.pct_change(24)
    feat['roc_diff'] = feat['momentum_6'] - feat['momentum_12']

    # === Volume ===
    feat['volume_ratio'] = df['tick_volume'] / df['tick_volume'].rolling(20).mean()
    feat['volume_trend'] = df['tick_volume'].rolling(5).mean() / (df['tick_volume'].rolling(20).mean() + 1)

    # Cleanup temp columns
    for span in [9, 21, 50, 100]:
        feat.drop(columns=[f'ema_{span}'], inplace=True)
    return feat


def create_labels(df: pd.DataFrame) -> np.ndarray:
    """
    Classify market regime using rule-based heuristics on rolling windows.
    These labels serve as training targets for the ML model.
    """
    w = CONFIG['regime_window']
    close = df['close'].values
    high = df['high'].values
    low = df['low'].values
    labels = np.full(len(df), REGIME_CLASSES.index('ranging'))

    for i in range(w, len(df)):
        window_close = close[i - w:i]
        window_high = high[i - w:i]
        window_low = low[i - w:i]

        ret = (window_close[-1] - window_close[0]) / window_close[0]
        vol = np.std(np.diff(window_close) / window_close[:-1])
        price_range = (window_high.max() - window_low.min()) / window_close.mean()

        # Breakout: sudden range expansion + high volatility
        recent_vol = np.std(np.diff(close[max(0, i-10):i]) /
                           (close[max(0, i-10):i-1] + 1e-10)) if i > 10 else vol
        if recent_vol > 2.0 * vol and price_range > 0.01:
            labels[i] = REGIME_CLASSES.index('breakout')
        # Trending bull
        elif ret > 0.003 and vol < 0.002:
            labels[i] = REGIME_CLASSES.index('trending_bull')
        # Trending bear
        elif ret < -0.003 and vol < 0.002:
            labels[i] = REGIME_CLASSES.index('trending_bear')
        # Volatile
        elif vol > 0.0015:
            labels[i] = REGIME_CLASSES.index('volatile')
        # Ranging (default)
        else:
            labels[i] = REGIME_CLASSES.index('ranging')
    return labels


def main():
    """Main training pipeline for market regime detector."""
    print("=" * 70)
    print("13 - Market Regime Detector (RandomForest 5-Class)")
    print("=" * 70)

    # --- Data Loading ---
    print("\n[1/5] Loading data...")
    df = generate_synthetic_data(CONFIG['n_bars'])
    print(f"  Loaded {len(df)} bars")

    # --- Feature Engineering ---
    print("\n[2/5] Computing composite features...")
    features = create_features(df)
    print(f"  Features: {features.shape}")

    # --- Label Creation ---
    print("\n[3/5] Classifying market regimes...")
    labels = create_labels(df)
    print("  Regime distribution:")
    for i, name in enumerate(REGIME_CLASSES):
        count = (labels == i).sum()
        print(f"    {name}: {count} ({100 * count / len(labels):.1f}%)")

    # --- Clean and split ---
    features['label'] = labels
    features.dropna(inplace=True)
    feature_cols = [c for c in features.columns if c != 'label']
    X = features[feature_cols].values
    y = features['label'].values.astype(int)
    split_idx = int(len(X) * (1 - CONFIG['test_size']))
    X_train, X_test = X[:split_idx], X[split_idx:]
    y_train, y_test = y[:split_idx], y[split_idx:]
    print(f"  Train: {len(X_train)}, Test: {len(X_test)}")

    # --- Model Training ---
    print("\n[4/5] Training RandomForest classifier...")
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import classification_report, confusion_matrix

    model = RandomForestClassifier(**CONFIG['rf_params'],
                                    random_state=CONFIG['random_state'],
                                    n_jobs=-1)
    model.fit(X_train, y_train)

    y_pred = model.predict(X_test)
    print("\nClassification Report:")
    print(classification_report(y_test, y_pred, target_names=REGIME_CLASSES,
                                zero_division=0))

    print("Confusion Matrix:")
    cm = confusion_matrix(y_test, y_pred)
    print(pd.DataFrame(cm, index=REGIME_CLASSES, columns=REGIME_CLASSES))

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

    import joblib
    joblib.dump(model, f"{model_path}.pkl")
    print(f"  Saved: {model_path}.pkl")

    try:
        from skl2onnx import convert_sklearn
        from skl2onnx.common.data_types import FloatTensorType
        import onnx
        initial_type = [('input', FloatTensorType([None, len(feature_cols)]))]
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
