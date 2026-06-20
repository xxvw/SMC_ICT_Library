"""
10 - プライスアクション分類器 / Price Action Classifier
========================================================
LSTM多クラス分類: OHLC系列をレンジ正規化し、ローソク足パターン
(doji, engulfing, pin_bar, hammer, shooting_star, marubozu, other)を分類する。

LSTM multi-class classifier: Normalizes OHLC sequences to range and
classifies candlestick pattern type (doji, engulfing, pin_bar, hammer,
shooting_star, marubozu, other).
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
    'model_name': 'price_action_classifier',
    'output_dir': str(default_model_dir()),
    'sequence_length': 20,
    'test_size': 0.2,
    'random_state': 42,
    'epochs': 50,
    'batch_size': 256,
    'lstm_units': 64,
    'dropout': 0.3,
}

PATTERN_CLASSES = ['doji', 'engulfing', 'pin_bar', 'hammer',
                   'shooting_star', 'marubozu', 'other']
NUM_CLASSES = len(PATTERN_CLASSES)


def generate_synthetic_data(n_bars: int = 100000) -> pd.DataFrame:
    """Generate synthetic OHLCV data when MT5 is unavailable."""
    np.random.seed(CONFIG['random_state'])
    returns = np.random.normal(0, 0.0005, n_bars)
    close = 1.1 + np.cumsum(returns)
    high = close + np.abs(np.random.normal(0, 0.0003, n_bars))
    low = close - np.abs(np.random.normal(0, 0.0003, n_bars))
    opn = close + np.random.normal(0, 0.0001, n_bars)
    return pd.DataFrame({
        'open': opn, 'high': high, 'low': low, 'close': close,
        'tick_volume': np.random.randint(100, 10000, n_bars).astype(float)
    })


def classify_candle(row) -> int:
    """Classify a single candlestick into pattern classes."""
    o, h, l, c = row['open'], row['high'], row['low'], row['close']
    body = abs(c - o)
    full_range = h - l
    if full_range < 1e-10:
        return PATTERN_CLASSES.index('doji')
    body_ratio = body / full_range
    upper_wick = h - max(o, c)
    lower_wick = min(o, c) - l
    # Doji: very small body
    if body_ratio < 0.1:
        return PATTERN_CLASSES.index('doji')
    # Marubozu: body > 90% of range
    if body_ratio > 0.9:
        return PATTERN_CLASSES.index('marubozu')
    # Pin bar: one wick > 2/3 of range, body < 1/3
    if body_ratio < 0.33:
        if upper_wick > 0.66 * full_range or lower_wick > 0.66 * full_range:
            return PATTERN_CLASSES.index('pin_bar')
    # Hammer: small body at top, long lower wick
    if lower_wick > 2 * body and upper_wick < body:
        return PATTERN_CLASSES.index('hammer')
    # Shooting star: small body at bottom, long upper wick
    if upper_wick > 2 * body and lower_wick < body:
        return PATTERN_CLASSES.index('shooting_star')
    return PATTERN_CLASSES.index('other')


def detect_engulfing(df: pd.DataFrame, labels: np.ndarray) -> np.ndarray:
    """Override label to engulfing where previous candle is engulfed."""
    for i in range(1, len(df)):
        prev_o, prev_c = df.iloc[i - 1]['open'], df.iloc[i - 1]['close']
        curr_o, curr_c = df.iloc[i]['open'], df.iloc[i]['close']
        prev_body_hi, prev_body_lo = max(prev_o, prev_c), min(prev_o, prev_c)
        curr_body_hi, curr_body_lo = max(curr_o, curr_c), min(curr_o, curr_c)
        if curr_body_hi > prev_body_hi and curr_body_lo < prev_body_lo:
            labels[i] = PATTERN_CLASSES.index('engulfing')
    return labels


def create_labels(df: pd.DataFrame) -> np.ndarray:
    """Create candlestick pattern labels for each bar."""
    labels = df.apply(classify_candle, axis=1).values
    labels = detect_engulfing(df, labels)
    return labels


def normalize_ohlc_sequence(df: pd.DataFrame, seq_len: int) -> np.ndarray:
    """Normalize OHLC sequences: scale each window to [0, 1] range."""
    ohlc = df[['open', 'high', 'low', 'close']].values
    sequences = []
    for i in range(seq_len, len(ohlc)):
        window = ohlc[i - seq_len:i]
        w_min = window.min()
        w_max = window.max()
        rng = w_max - w_min
        if rng < 1e-10:
            rng = 1e-10
        normalized = (window - w_min) / rng
        sequences.append(normalized)
    return np.array(sequences)


def create_features(df: pd.DataFrame) -> np.ndarray:
    """Create normalized OHLC sequence features for LSTM input."""
    return normalize_ohlc_sequence(df, CONFIG['sequence_length'])


def build_lstm_model(input_shape: tuple, num_classes: int):
    """Build Keras LSTM model for candlestick pattern classification."""
    from tensorflow.keras.models import Sequential
    from tensorflow.keras.layers import LSTM, Dense, Dropout, BatchNormalization

    model = Sequential([
        LSTM(CONFIG['lstm_units'], return_sequences=True, input_shape=input_shape),
        Dropout(CONFIG['dropout']),
        LSTM(CONFIG['lstm_units'] // 2, return_sequences=False),
        Dropout(CONFIG['dropout']),
        BatchNormalization(),
        Dense(64, activation='relu'),
        Dropout(CONFIG['dropout']),
        Dense(num_classes, activation='softmax'),
    ])
    model.compile(
        optimizer='adam',
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )
    return model


def main():
    """Main training pipeline for price action classifier."""
    print("=" * 70)
    print("10 - Price Action Classifier (LSTM Multi-Class)")
    print("=" * 70)

    # --- Data Loading ---
    print("\n[1/5] Loading data...")
    df = generate_synthetic_data(CONFIG['n_bars'])
    print(f"  Loaded {len(df)} bars")

    # --- Label Creation ---
    print("\n[2/5] Classifying candlestick patterns...")
    labels = create_labels(df)
    print("  Class distribution:")
    for i, name in enumerate(PATTERN_CLASSES):
        count = (labels == i).sum()
        print(f"    {name}: {count} ({100 * count / len(labels):.1f}%)")

    # --- Feature Engineering ---
    print("\n[3/5] Creating normalized OHLC sequences...")
    X = create_features(df)
    y = labels[CONFIG['sequence_length']:]
    assert len(X) == len(y), f"Shape mismatch: X={len(X)}, y={len(y)}"
    print(f"  Sequences: {X.shape} (samples, timesteps, features)")

    # --- Train/Test Split (temporal) ---
    split_idx = int(len(X) * (1 - CONFIG['test_size']))
    X_train, X_test = X[:split_idx], X[split_idx:]
    y_train, y_test = y[:split_idx], y[split_idx:]
    print(f"  Train: {len(X_train)}, Test: {len(X_test)}")

    # --- Model Training ---
    print("\n[4/5] Training LSTM model...")
    from tensorflow.keras.callbacks import EarlyStopping, ReduceLROnPlateau

    model = build_lstm_model(
        input_shape=(CONFIG['sequence_length'], 4),
        num_classes=NUM_CLASSES,
    )
    model.summary()

    callbacks = [
        EarlyStopping(patience=7, restore_best_weights=True, monitor='val_accuracy'),
        ReduceLROnPlateau(factor=0.5, patience=3, monitor='val_loss'),
    ]
    history = model.fit(
        X_train, y_train,
        validation_data=(X_test, y_test),
        epochs=CONFIG['epochs'],
        batch_size=CONFIG['batch_size'],
        callbacks=callbacks,
        verbose=1,
    )

    # --- Evaluation ---
    from sklearn.metrics import classification_report
    y_pred = model.predict(X_test).argmax(axis=1)
    print("\nClassification Report:")
    print(classification_report(y_test, y_pred, target_names=PATTERN_CLASSES,
                                zero_division=0))

    # --- Export ---
    print("\n[5/5] Exporting model...")
    os.makedirs(CONFIG['output_dir'], exist_ok=True)
    model_path = os.path.join(CONFIG['output_dir'], CONFIG['model_name'])
    model.save(f"{model_path}.keras")
    print(f"  Saved Keras: {model_path}.keras")

    try:
        import tf2onnx
        import tensorflow as tf
        spec = (tf.TensorSpec((None, CONFIG['sequence_length'], 4),
                              tf.float32, name="input"),)
        onnx_model, _ = tf2onnx.convert.from_keras(model, input_signature=spec)
        import onnx
        onnx.save_model(onnx_model, f"{model_path}.onnx")
        print(f"  ONNX exported: {model_path}.onnx")
    except Exception as e:
        print(f"  ONNX export skipped: {e}")

    print("\n" + "=" * 70)
    print("Training complete!")
    print("=" * 70)


if __name__ == '__main__':
    main()
