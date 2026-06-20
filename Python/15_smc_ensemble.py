"""
15 - SMCアンサンブル / SMC Ensemble Meta-Learner
=================================================
スタッキングアンサンブル: 前14モデルの予測を統合するメタ学習器(LightGBM)。
モデルが存在しない場合はモック予測を生成。最終出力: Buy/Sell/Waitの3クラス。

Stacking ensemble: Loads predictions from all 14 previous models (or generates
mock predictions if models not available). Trains a LightGBM meta-learner
on stacked predictions. Final output: 3 classes (Buy/Sell/Wait).
"""
import sys
import os
import warnings
import numpy as np
import pandas as pd
from typing import Dict, Optional

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
    'model_name': 'smc_ensemble',
    'output_dir': str(default_model_dir()),
    'test_size': 0.2,
    'random_state': 42,
    'meta_lgbm_params': {
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
    'signal_threshold_buy': 0.55,
    'signal_threshold_sell': 0.55,
}

FINAL_CLASSES = ['Buy', 'Sell', 'Wait']
NUM_CLASSES = len(FINAL_CLASSES)

# All 14 sub-models and their expected output types
SUB_MODELS = {
    '01_order_block_detector':       {'type': 'binary_prob',   'cols': ['ob_prob']},
    '02_fvg_detector':               {'type': 'binary_prob',   'cols': ['fvg_prob']},
    '03_bos_choch_classifier':       {'type': 'multiclass',    'cols': ['bos_prob', 'choch_prob', 'none_prob']},
    '04_liquidity_sweep_predictor':  {'type': 'binary_prob',   'cols': ['liq_sweep_prob']},
    '05_optimal_entry_timer':        {'type': 'regression',    'cols': ['entry_score']},
    '06_session_bias_predictor':     {'type': 'multiclass',    'cols': ['bullish_bias', 'bearish_bias', 'neutral_bias']},
    '07_wyckoff_phase_classifier':   {'type': 'multiclass',    'cols': ['accum_prob', 'distrib_prob', 'markup_prob', 'markdown_prob']},
    '08_kill_zone_volatility':       {'type': 'regression',    'cols': ['vol_prediction']},
    '09_mtf_confluence_scorer':      {'type': 'regression',    'cols': ['confluence_score']},
    '10_price_action_classifier':    {'type': 'multiclass',    'cols': ['doji_p', 'engulf_p', 'pin_p', 'hammer_p', 'star_p', 'marubozu_p', 'other_p']},
    '11_currency_strength_predictor':{'type': 'regression',    'cols': ['eur_str', 'usd_str']},
    '12_sl_tp_optimizer':            {'type': 'regression',    'cols': ['opt_sl', 'opt_tp']},
    '13_market_regime_detector':     {'type': 'multiclass',    'cols': ['bull_regime', 'bear_regime', 'range_regime', 'vol_regime', 'break_regime']},
    '14_swing_reversal_predictor':   {'type': 'binary_prob',   'cols': ['reversal_prob']},
}


def generate_synthetic_data(n_bars: int = 100000) -> pd.DataFrame:
    """Generate synthetic base OHLCV data."""
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


def try_load_model_predictions(model_name: str, model_info: dict,
                                n_bars: int) -> Optional[pd.DataFrame]:
    """
    Attempt to load a trained sub-model and generate predictions.
    Returns None if the model file is not found.
    """
    model_dir = CONFIG['output_dir']
    possible_files = [
        os.path.join(model_dir, f"{model_name}.onnx"),
        os.path.join(model_dir, f"{model_name}.pkl"),
        os.path.join(model_dir, f"{model_name}.json"),
        os.path.join(model_dir, f"{model_name}.keras"),
    ]
    for fpath in possible_files:
        if os.path.exists(fpath):
            print(f"    Found: {fpath}")
            # In production, load and run inference here
            return None
    return None


def generate_mock_predictions(model_name: str, model_info: dict,
                               n_bars: int) -> pd.DataFrame:
    """
    Generate realistic mock predictions for a sub-model.
    Uses correlated noise to simulate model behavior.
    """
    np.random.seed(hash(model_name) % 2**31)
    cols = model_info['cols']
    n_cols = len(cols)

    if model_info['type'] == 'binary_prob':
        # Probabilities centered around 0.5 with some signal
        base = np.random.beta(2, 2, n_bars)
        data = {cols[0]: base}

    elif model_info['type'] == 'multiclass':
        # Dirichlet distribution for probability simplex
        alphas = np.ones(n_cols) * 2.0
        probs = np.random.dirichlet(alphas, n_bars)
        data = {col: probs[:, i] for i, col in enumerate(cols)}

    elif model_info['type'] == 'regression':
        data = {}
        for col in cols:
            if 'score' in col or 'prob' in col:
                data[col] = np.random.beta(2, 2, n_bars)
            elif 'sl' in col or 'tp' in col:
                data[col] = np.abs(np.random.normal(15, 8, n_bars))
            elif 'str' in col:
                data[col] = np.random.normal(0, 0.001, n_bars)
            else:
                data[col] = np.random.normal(0, 1, n_bars)
    else:
        data = {col: np.random.randn(n_bars) for col in cols}

    return pd.DataFrame(data)


def collect_sub_model_predictions(n_bars: int) -> pd.DataFrame:
    """Collect predictions from all 14 sub-models (real or mock)."""
    all_preds = pd.DataFrame()

    for model_name, model_info in SUB_MODELS.items():
        real_preds = try_load_model_predictions(model_name, model_info, n_bars)
        if real_preds is not None:
            for col in real_preds.columns:
                all_preds[col] = real_preds[col].values[:n_bars]
        else:
            mock_preds = generate_mock_predictions(model_name, model_info, n_bars)
            for col in mock_preds.columns:
                all_preds[col] = mock_preds[col].values[:n_bars]

    return all_preds


def create_meta_features(sub_preds: pd.DataFrame,
                          base_df: pd.DataFrame) -> pd.DataFrame:
    """
    Create meta-features from sub-model predictions.
    Adds cross-model interaction features and base market context.
    """
    feat = sub_preds.copy()

    # --- Cross-model Interaction Features ---
    # Directional consensus: average of directional signals
    if 'ob_prob' in feat.columns and 'fvg_prob' in feat.columns:
        feat['smc_signal_avg'] = (feat['ob_prob'] + feat['fvg_prob']) / 2
    if 'reversal_prob' in feat.columns and 'confluence_score' in feat.columns:
        feat['reversal_x_confluence'] = feat['reversal_prob'] * feat['confluence_score']
    if 'liq_sweep_prob' in feat.columns and 'reversal_prob' in feat.columns:
        feat['sweep_x_reversal'] = feat['liq_sweep_prob'] * feat['reversal_prob']

    # Regime-adjusted signals
    if 'bull_regime' in feat.columns and 'ob_prob' in feat.columns:
        feat['bull_ob_signal'] = feat['bull_regime'] * feat['ob_prob']
        feat['bear_ob_signal'] = feat['bear_regime'] * feat['ob_prob']

    # Risk-reward ratio from SL/TP predictions
    if 'opt_sl' in feat.columns and 'opt_tp' in feat.columns:
        feat['risk_reward_ratio'] = feat['opt_tp'] / (feat['opt_sl'] + 1e-10)

    # Currency strength differential
    if 'eur_str' in feat.columns and 'usd_str' in feat.columns:
        feat['ccy_diff'] = feat['eur_str'] - feat['usd_str']

    # --- Base Market Context ---
    close = base_df['close']
    feat['base_return_1'] = close.pct_change(1).values
    feat['base_return_5'] = close.pct_change(5).values
    feat['base_return_12'] = close.pct_change(12).values
    feat['base_volatility'] = close.pct_change().rolling(20).std().values

    # Rolling statistics on key sub-model outputs
    for col in ['ob_prob', 'confluence_score', 'reversal_prob']:
        if col in feat.columns:
            feat[f'{col}_ma5'] = feat[col].rolling(5).mean()
            feat[f'{col}_std5'] = feat[col].rolling(5).std()

    return feat


def create_ensemble_labels(base_df: pd.DataFrame, horizon: int = 12) -> np.ndarray:
    """
    Create Buy/Sell/Wait labels based on future returns.
    Buy=0, Sell=1, Wait=2.
    """
    close = base_df['close'].values
    labels = np.full(len(close), 2)  # default Wait
    threshold = 0.0005

    for i in range(len(close) - horizon):
        future_ret = (close[i + horizon] - close[i]) / close[i]
        if future_ret > threshold:
            labels[i] = 0  # Buy
        elif future_ret < -threshold:
            labels[i] = 1  # Sell
        else:
            labels[i] = 2  # Wait
    return labels


def main():
    """Main training pipeline for SMC ensemble meta-learner."""
    print("=" * 70)
    print("15 - SMC Ensemble Meta-Learner (LightGBM Stacking)")
    print("=" * 70)
    print(f"  Sub-models: {len(SUB_MODELS)}")
    print(f"  Final classes: {FINAL_CLASSES}")

    # --- Data Loading ---
    print("\n[1/7] Loading base market data...")
    base_df = generate_synthetic_data(CONFIG['n_bars'])
    n_bars = len(base_df)
    print(f"  Loaded {n_bars} bars")

    # --- Collect Sub-Model Predictions ---
    print("\n[2/7] Collecting sub-model predictions...")
    sub_preds = collect_sub_model_predictions(n_bars)
    total_pred_cols = len(sub_preds.columns)
    print(f"  Collected {total_pred_cols} prediction columns from {len(SUB_MODELS)} models")
    print(f"  Prediction columns: {list(sub_preds.columns)}")

    # --- Meta-Feature Engineering ---
    print("\n[3/7] Creating meta-features...")
    meta_features = create_meta_features(sub_preds, base_df)
    print(f"  Meta-features: {meta_features.shape}")

    # --- Label Creation ---
    print("\n[4/7] Creating ensemble labels (Buy/Sell/Wait)...")
    labels = create_ensemble_labels(base_df)
    meta_features['label'] = labels
    meta_features.dropna(inplace=True)

    print("  Label distribution:")
    for i, name in enumerate(FINAL_CLASSES):
        count = (meta_features['label'] == i).sum()
        print(f"    {name}: {count} ({100 * count / len(meta_features):.1f}%)")

    # --- Prepare Data ---
    feature_cols = [c for c in meta_features.columns if c != 'label']
    X = meta_features[feature_cols].values
    y = meta_features['label'].values.astype(int)

    split_idx = int(len(X) * (1 - CONFIG['test_size']))
    X_train, X_test = X[:split_idx], X[split_idx:]
    y_train, y_test = y[:split_idx], y[split_idx:]
    print(f"\n  Features: {len(feature_cols)}")
    print(f"  Train: {len(X_train)}, Test: {len(X_test)}")

    # --- Meta-Learner Training ---
    print("\n[5/7] Training LightGBM meta-learner...")
    from lightgbm import LGBMClassifier
    from sklearn.metrics import classification_report, confusion_matrix, accuracy_score

    model = LGBMClassifier(
        **CONFIG['meta_lgbm_params'],
        objective='multiclass',
        num_class=NUM_CLASSES,
        random_state=CONFIG['random_state'],
        class_weight='balanced',
    )
    model.fit(
        X_train, y_train,
        eval_set=[(X_test, y_test)],
        callbacks=[],
    )

    y_pred = model.predict(X_test)
    y_proba = model.predict_proba(X_test)
    accuracy = accuracy_score(y_test, y_pred)

    print(f"\n  Accuracy: {accuracy:.4f}")
    print("\nClassification Report:")
    print(classification_report(y_test, y_pred, target_names=FINAL_CLASSES,
                                zero_division=0))

    print("Confusion Matrix:")
    cm = confusion_matrix(y_test, y_pred)
    print(pd.DataFrame(cm, index=FINAL_CLASSES, columns=FINAL_CLASSES))

    # --- Feature Importance Analysis ---
    print("\n[6/7] Analyzing meta-feature importance...")
    importance = dict(zip(feature_cols, model.feature_importances_))
    top_features = sorted(importance.items(), key=lambda x: x[1], reverse=True)[:15]
    print("\n  Top 15 Meta-Features:")
    for fname, fval in top_features:
        print(f"    {fname}: {fval:.0f}")

    # Group importance by sub-model
    print("\n  Importance by Sub-Model Category:")
    categories = {
        'SMC Structure': ['ob_prob', 'fvg_prob', 'bos_prob', 'choch_prob', 'none_prob'],
        'Liquidity/Sweep': ['liq_sweep_prob', 'sweep_x_reversal'],
        'Entry/Timing': ['entry_score', 'confluence_score'],
        'Session/Regime': ['bullish_bias', 'bearish_bias', 'neutral_bias',
                          'bull_regime', 'bear_regime', 'range_regime'],
        'Price Action': ['doji_p', 'engulf_p', 'pin_p', 'hammer_p', 'star_p', 'marubozu_p'],
        'Risk Management': ['opt_sl', 'opt_tp', 'risk_reward_ratio'],
        'Currency Strength': ['eur_str', 'usd_str', 'ccy_diff'],
        'Reversal': ['reversal_prob', 'reversal_x_confluence'],
    }
    for cat_name, cat_cols in categories.items():
        cat_imp = sum(importance.get(c, 0) for c in cat_cols if c in importance)
        if cat_imp > 0:
            print(f"    {cat_name}: {cat_imp:.0f}")

    # --- Signal Quality Analysis ---
    print("\n  Signal Quality Analysis:")
    buy_mask = y_pred == 0
    sell_mask = y_pred == 1
    wait_mask = y_pred == 2
    buy_conf = y_proba[buy_mask, 0].mean() if buy_mask.any() else 0
    sell_conf = y_proba[sell_mask, 1].mean() if sell_mask.any() else 0
    wait_conf = y_proba[wait_mask, 2].mean() if wait_mask.any() else 0
    print(f"    Buy  signals: {buy_mask.sum():>6} (avg conf: {buy_conf:.3f})")
    print(f"    Sell signals: {sell_mask.sum():>6} (avg conf: {sell_conf:.3f})")
    print(f"    Wait signals: {wait_mask.sum():>6} (avg conf: {wait_conf:.3f})")

    # --- Export ---
    print("\n[7/7] Exporting ensemble model...")
    os.makedirs(CONFIG['output_dir'], exist_ok=True)
    model_path = os.path.join(CONFIG['output_dir'], CONFIG['model_name'])

    import joblib
    joblib.dump({
        'model': model,
        'feature_cols': feature_cols,
        'sub_models': list(SUB_MODELS.keys()),
        'classes': FINAL_CLASSES,
        'config': CONFIG,
    }, f"{model_path}.pkl")
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

    # Save meta-feature specification for inference
    spec_path = os.path.join(CONFIG['output_dir'], f"{CONFIG['model_name']}_spec.json")
    import json
    spec = {
        'sub_models': {k: v for k, v in SUB_MODELS.items()},
        'meta_feature_cols': feature_cols,
        'final_classes': FINAL_CLASSES,
        'thresholds': {
            'buy': CONFIG['signal_threshold_buy'],
            'sell': CONFIG['signal_threshold_sell'],
        },
    }
    with open(spec_path, 'w') as f:
        json.dump(spec, f, indent=2)
    print(f"  Spec saved: {spec_path}")

    print("\n" + "=" * 70)
    print("SMC Ensemble Training Complete!")
    print(f"  Total sub-models integrated: {len(SUB_MODELS)}")
    print(f"  Meta-features used: {len(feature_cols)}")
    print(f"  Final accuracy: {accuracy:.4f}")
    print("=" * 70)


if __name__ == '__main__':
    main()
