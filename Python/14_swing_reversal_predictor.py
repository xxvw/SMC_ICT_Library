"""
14 - スイング反転予測器 / Swing Reversal Predictor
=====================================================
LSTMバイナリ分類: スイングポイント系列(価格・強度・ブレイクフラグ)から、
スイングでの価格反転か継続かを予測する。

LSTM binary classifier: Uses swing point sequences (price, strength,
broken flag) to predict whether price reverses at a swing point or
continues in the same direction.
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
    'model_name': 'swing_reversal_predictor',
    'output_dir': str(default_model_dir()),
    'test_size': 0.2,
    'random_state': 42,
    'swing_lookback': 5,
    'sequence_length': 15,
    'future_window': 20,
    'reversal_threshold': 0.0010,
    'epochs': 50,
    'batch_size': 256,
    'lstm_units': 48,
    'dropout': 0.3,
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


def detect_swing_points(df: pd.DataFrame, lookback: int = 5) -> pd.DataFrame:
    """
    Detect swing highs and swing lows using a rolling window approach.
    Returns a DataFrame of swing points with their properties.
    """
    high = df['high'].values
    low = df['low'].values
    close = df['close'].values
    n = len(df)

    swings = []
    for i in range(lookback, n - lookback):
        # Swing High: highest high in the window
        if high[i] == max(high[i - lookback:i + lookback + 1]):
            # Strength: how far above neighbors
            strength = (high[i] - np.mean(high[i - lookback:i + lookback + 1])) / high[i]
            swings.append({
                'bar_index': i,
                'price': high[i],
                'type': 1,  # 1 = swing high
                'strength': strength,
                'close': close[i],
            })
        # Swing Low: lowest low in the window
        if low[i] == min(low[i - lookback:i + lookback + 1]):
            strength = (np.mean(low[i - lookback:i + lookback + 1]) - low[i]) / low[i]
            swings.append({
                'bar_index': i,
                'price': low[i],
                'type': -1,  # -1 = swing low
                'strength': strength,
                'close': close[i],
            })

    swing_df = pd.DataFrame(swings)
    if len(swing_df) == 0:
        return swing_df
    swing_df.sort_values('bar_index', inplace=True)
    swing_df.reset_index(drop=True, inplace=True)
    return swing_df


def add_broken_flags(swing_df: pd.DataFrame) -> pd.DataFrame:
    """
    Add 'broken' flag: whether a swing high/low was subsequently broken
    by a later swing in the same direction.
    """
    swing_df['broken'] = 0.0
    for i in range(1, len(swing_df)):
        for j in range(i - 1, max(i - 10, -1), -1):
            if swing_df.iloc[j]['type'] == swing_df.iloc[i]['type']:
                if swing_df.iloc[i]['type'] == 1:  # swing high
                    if swing_df.iloc[i]['price'] > swing_df.iloc[j]['price']:
                        swing_df.iloc[j, swing_df.columns.get_loc('broken')] = 1.0
                else:  # swing low
                    if swing_df.iloc[i]['price'] < swing_df.iloc[j]['price']:
                        swing_df.iloc[j, swing_df.columns.get_loc('broken')] = 1.0
                break
    return swing_df


def create_labels(swing_df: pd.DataFrame, close_prices: np.ndarray) -> np.ndarray:
    """
    Label each swing point: 1 = reversal, 0 = continuation.
    A reversal occurs when price moves against the swing direction
    by more than the threshold within the future window.
    """
    labels = np.zeros(len(swing_df))
    window = CONFIG['future_window']
    threshold = CONFIG['reversal_threshold']
    n_prices = len(close_prices)

    for i, row in swing_df.iterrows():
        bar_idx = int(row['bar_index'])
        if bar_idx + window >= n_prices:
            labels[i] = -1  # mark as invalid
            continue
        entry_price = close_prices[bar_idx]
        future_prices = close_prices[bar_idx + 1:bar_idx + 1 + window]

        if row['type'] == 1:  # swing high -> reversal means price drops
            max_drop = (entry_price - future_prices.min()) / entry_price
            labels[i] = 1 if max_drop > threshold else 0
        else:  # swing low -> reversal means price rises
            max_rise = (future_prices.max() - entry_price) / entry_price
            labels[i] = 1 if max_rise > threshold else 0

    return labels


def create_sequences(swing_df: pd.DataFrame, labels: np.ndarray,
                     seq_len: int) -> tuple:
    """Create sequences of swing point features for LSTM input."""
    # Features per swing: normalized_price, type, strength, broken
    valid_mask = labels >= 0
    swing_df = swing_df[valid_mask].reset_index(drop=True)
    labels = labels[valid_mask]

    prices = swing_df['price'].values
    types = swing_df['type'].values.astype(float)
    strengths = swing_df['strength'].values
    broken = swing_df['broken'].values

    X_list, y_list = [], []
    for i in range(seq_len, len(swing_df)):
        window = slice(i - seq_len, i)
        # Normalize prices in the window to [0, 1]
        p_window = prices[window]
        p_min, p_max = p_window.min(), p_window.max()
        p_range = p_max - p_min if (p_max - p_min) > 1e-10 else 1e-10
        norm_prices = (p_window - p_min) / p_range

        seq = np.column_stack([
            norm_prices,
            types[window],
            strengths[window],
            broken[window],
        ])
        X_list.append(seq)
        y_list.append(labels[i])

    return np.array(X_list), np.array(y_list)


def build_lstm_model(input_shape: tuple):
    """Build Keras LSTM model for binary swing reversal prediction."""
    from tensorflow.keras.models import Sequential
    from tensorflow.keras.layers import LSTM, Dense, Dropout, BatchNormalization

    model = Sequential([
        LSTM(CONFIG['lstm_units'], return_sequences=True, input_shape=input_shape),
        Dropout(CONFIG['dropout']),
        LSTM(CONFIG['lstm_units'] // 2, return_sequences=False),
        Dropout(CONFIG['dropout']),
        BatchNormalization(),
        Dense(32, activation='relu'),
        Dropout(CONFIG['dropout']),
        Dense(1, activation='sigmoid'),
    ])
    model.compile(
        optimizer='adam',
        loss='binary_crossentropy',
        metrics=['accuracy']
    )
    return model


def main():
    """Main training pipeline for swing reversal predictor."""
    print("=" * 70)
    print("14 - Swing Reversal Predictor (LSTM Binary)")
    print("=" * 70)

    # --- Data Loading ---
    print("\n[1/6] Loading data...")
    df = generate_synthetic_data(CONFIG['n_bars'])
    print(f"  Loaded {len(df)} bars")

    # --- Swing Detection ---
    print("\n[2/6] Detecting swing points...")
    swing_df = detect_swing_points(df, CONFIG['swing_lookback'])
    swing_df = add_broken_flags(swing_df)
    n_highs = (swing_df['type'] == 1).sum()
    n_lows = (swing_df['type'] == -1).sum()
    n_broken = (swing_df['broken'] == 1).sum()
    print(f"  Swing points: {len(swing_df)} (highs={n_highs}, lows={n_lows})")
    print(f"  Broken swings: {n_broken}")

    # --- Label Creation ---
    print("\n[3/6] Labeling reversals vs continuations...")
    labels = create_labels(swing_df, df['close'].values)
    valid = labels >= 0
    n_rev = (labels[valid] == 1).sum()
    n_con = (labels[valid] == 0).sum()
    print(f"  Reversals: {n_rev}, Continuations: {n_con}")
    print(f"  Reversal rate: {100 * n_rev / (n_rev + n_con):.1f}%")

    # --- Sequence Creation ---
    print("\n[4/6] Creating swing sequences...")
    X, y = create_sequences(swing_df, labels, CONFIG['sequence_length'])
    print(f"  Sequences: {X.shape} (samples, timesteps, features)")

    # --- Train/Test Split ---
    split_idx = int(len(X) * (1 - CONFIG['test_size']))
    X_train, X_test = X[:split_idx], X[split_idx:]
    y_train, y_test = y[:split_idx], y[split_idx:]
    print(f"  Train: {len(X_train)}, Test: {len(X_test)}")

    # --- Model Training ---
    print("\n[5/6] Training LSTM model...")
    from tensorflow.keras.callbacks import EarlyStopping, ReduceLROnPlateau

    model = build_lstm_model(input_shape=(CONFIG['sequence_length'], 4))
    model.summary()

    callbacks = [
        EarlyStopping(patience=7, restore_best_weights=True, monitor='val_loss'),
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
    from sklearn.metrics import classification_report, roc_auc_score
    y_prob = model.predict(X_test).flatten()
    y_pred = (y_prob > 0.5).astype(int)
    print("\nClassification Report:")
    print(classification_report(y_test.astype(int), y_pred,
                                target_names=['continuation', 'reversal'],
                                zero_division=0))
    try:
        auc = roc_auc_score(y_test, y_prob)
        print(f"  AUC-ROC: {auc:.4f}")
    except ValueError:
        print("  AUC-ROC: N/A (single class in test)")

    # --- Export ---
    print("\n[6/6] Exporting model...")
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
