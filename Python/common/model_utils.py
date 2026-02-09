"""
Model Utilities Module
======================

Provides a unified interface for training, evaluating, hyper-parameter tuning,
and ONNX-exporting machine learning models used across the OSS Library.

Supported model families:
    - LightGBM  (gradient boosted trees)
    - XGBoost   (gradient boosted trees)
    - Random Forest (scikit-learn)
    - LSTM      (TensorFlow / Keras)

All ``train_*`` methods return ``(model, metrics_dict)`` so the caller
always has immediate feedback on validation performance.
"""

from __future__ import annotations

import logging
import warnings
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Union

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    f1_score,
    mean_absolute_error,
    mean_squared_error,
    precision_score,
    r2_score,
    recall_score,
    roc_auc_score,
)

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Optional heavy imports (fail gracefully)
# ---------------------------------------------------------------------------
try:
    import lightgbm as lgb

    _LGB_AVAILABLE = True
except ImportError:
    _LGB_AVAILABLE = False

try:
    import xgboost as xgb

    _XGB_AVAILABLE = True
except ImportError:
    _XGB_AVAILABLE = False

try:
    import optuna

    _OPTUNA_AVAILABLE = True
except ImportError:
    _OPTUNA_AVAILABLE = False

try:
    import tensorflow as tf

    _TF_AVAILABLE = True
except ImportError:
    _TF_AVAILABLE = False

try:
    import onnx  # noqa: F401
    import onnxmltools  # noqa: F401
    from skl2onnx import convert_sklearn
    from skl2onnx.common.data_types import FloatTensorType

    _ONNX_AVAILABLE = True
except ImportError:
    _ONNX_AVAILABLE = False

try:
    import tf2onnx  # noqa: F401

    _TF2ONNX_AVAILABLE = True
except ImportError:
    _TF2ONNX_AVAILABLE = False


# ===================================================================
# Default hyper-parameters
# ===================================================================
_DEFAULT_LGB_CLS: Dict[str, Any] = {
    "objective": "binary",
    "metric": "binary_logloss",
    "boosting_type": "gbdt",
    "num_leaves": 63,
    "learning_rate": 0.05,
    "feature_fraction": 0.8,
    "bagging_fraction": 0.8,
    "bagging_freq": 5,
    "verbose": -1,
    "n_estimators": 500,
    "early_stopping_rounds": 30,
}

_DEFAULT_LGB_REG: Dict[str, Any] = {
    **_DEFAULT_LGB_CLS,
    "objective": "regression",
    "metric": "rmse",
}

_DEFAULT_XGB_CLS: Dict[str, Any] = {
    "objective": "binary:logistic",
    "eval_metric": "logloss",
    "max_depth": 6,
    "learning_rate": 0.05,
    "n_estimators": 500,
    "subsample": 0.8,
    "colsample_bytree": 0.8,
    "early_stopping_rounds": 30,
    "verbosity": 0,
}

_DEFAULT_XGB_REG: Dict[str, Any] = {
    **_DEFAULT_XGB_CLS,
    "objective": "reg:squarederror",
    "eval_metric": "rmse",
}

_DEFAULT_RF_CLS: Dict[str, Any] = {
    "n_estimators": 300,
    "max_depth": 12,
    "min_samples_leaf": 5,
    "max_features": "sqrt",
    "n_jobs": -1,
    "random_state": 42,
}

_DEFAULT_RF_REG: Dict[str, Any] = {
    **_DEFAULT_RF_CLS,
    "max_features": 1.0,
}


class ModelTrainer:
    """Unified training / evaluation / export interface."""

    # ================================================================
    # LightGBM
    # ================================================================
    @staticmethod
    def train_lightgbm(
        X_train: np.ndarray,
        y_train: np.ndarray,
        X_val: np.ndarray,
        y_val: np.ndarray,
        task: str = "classification",
        params: Optional[Dict[str, Any]] = None,
    ) -> Tuple[Any, Dict[str, float]]:
        """Train a LightGBM model.

        Parameters
        ----------
        X_train, y_train : array-like
            Training features and labels.
        X_val, y_val : array-like
            Validation features and labels.
        task : str
            ``"classification"`` or ``"regression"``.
        params : dict, optional
            Override default LightGBM parameters.

        Returns
        -------
        tuple[lgb.Booster | lgb.LGBMClassifier, dict]
            Trained model and validation metrics.
        """
        if not _LGB_AVAILABLE:
            raise ImportError("lightgbm is not installed.")

        defaults = (
            _DEFAULT_LGB_CLS.copy()
            if task == "classification"
            else _DEFAULT_LGB_REG.copy()
        )
        if params:
            defaults.update(params)

        early_stopping = defaults.pop("early_stopping_rounds", 30)
        n_estimators = defaults.pop("n_estimators", 500)

        if task == "classification":
            model = lgb.LGBMClassifier(
                n_estimators=n_estimators, **defaults
            )
            model.fit(
                X_train,
                y_train,
                eval_set=[(X_val, y_val)],
                callbacks=[
                    lgb.early_stopping(early_stopping),
                    lgb.log_evaluation(50),
                ],
            )
            y_pred = model.predict(X_val)
            y_prob = model.predict_proba(X_val)[:, 1]
            metrics = ModelTrainer.evaluate(
                y_val, y_pred, y_prob, task="classification"
            )
        else:
            model = lgb.LGBMRegressor(
                n_estimators=n_estimators, **defaults
            )
            model.fit(
                X_train,
                y_train,
                eval_set=[(X_val, y_val)],
                callbacks=[
                    lgb.early_stopping(early_stopping),
                    lgb.log_evaluation(50),
                ],
            )
            y_pred = model.predict(X_val)
            metrics = ModelTrainer.evaluate(
                y_val, y_pred, task="regression"
            )

        logger.info("LightGBM %s metrics: %s", task, metrics)
        return model, metrics

    # ================================================================
    # XGBoost
    # ================================================================
    @staticmethod
    def train_xgboost(
        X_train: np.ndarray,
        y_train: np.ndarray,
        X_val: np.ndarray,
        y_val: np.ndarray,
        task: str = "classification",
        params: Optional[Dict[str, Any]] = None,
    ) -> Tuple[Any, Dict[str, float]]:
        """Train an XGBoost model.

        Parameters
        ----------
        X_train, y_train, X_val, y_val : array-like
            Training and validation data.
        task : str
            ``"classification"`` or ``"regression"``.
        params : dict, optional
            Override default XGBoost parameters.

        Returns
        -------
        tuple[xgb.XGBClassifier | xgb.XGBRegressor, dict]
        """
        if not _XGB_AVAILABLE:
            raise ImportError("xgboost is not installed.")

        defaults = (
            _DEFAULT_XGB_CLS.copy()
            if task == "classification"
            else _DEFAULT_XGB_REG.copy()
        )
        if params:
            defaults.update(params)

        if task == "classification":
            model = xgb.XGBClassifier(**defaults)
            model.fit(
                X_train,
                y_train,
                eval_set=[(X_val, y_val)],
                verbose=False,
            )
            y_pred = model.predict(X_val)
            y_prob = model.predict_proba(X_val)[:, 1]
            metrics = ModelTrainer.evaluate(
                y_val, y_pred, y_prob, task="classification"
            )
        else:
            model = xgb.XGBRegressor(**defaults)
            model.fit(
                X_train,
                y_train,
                eval_set=[(X_val, y_val)],
                verbose=False,
            )
            y_pred = model.predict(X_val)
            metrics = ModelTrainer.evaluate(
                y_val, y_pred, task="regression"
            )

        logger.info("XGBoost %s metrics: %s", task, metrics)
        return model, metrics

    # ================================================================
    # Random Forest
    # ================================================================
    @staticmethod
    def train_random_forest(
        X_train: np.ndarray,
        y_train: np.ndarray,
        X_val: np.ndarray,
        y_val: np.ndarray,
        task: str = "classification",
        params: Optional[Dict[str, Any]] = None,
    ) -> Tuple[Any, Dict[str, float]]:
        """Train a scikit-learn Random Forest.

        Parameters
        ----------
        X_train, y_train, X_val, y_val : array-like
            Training and validation data.
        task : str
            ``"classification"`` or ``"regression"``.
        params : dict, optional
            Override defaults.

        Returns
        -------
        tuple[RandomForestClassifier | RandomForestRegressor, dict]
        """
        defaults = (
            _DEFAULT_RF_CLS.copy()
            if task == "classification"
            else _DEFAULT_RF_REG.copy()
        )
        if params:
            defaults.update(params)

        if task == "classification":
            model = RandomForestClassifier(**defaults)
            model.fit(X_train, y_train)
            y_pred = model.predict(X_val)
            y_prob = model.predict_proba(X_val)[:, 1]
            metrics = ModelTrainer.evaluate(
                y_val, y_pred, y_prob, task="classification"
            )
        else:
            model = RandomForestRegressor(**defaults)
            model.fit(X_train, y_train)
            y_pred = model.predict(X_val)
            metrics = ModelTrainer.evaluate(
                y_val, y_pred, task="regression"
            )

        logger.info("RandomForest %s metrics: %s", task, metrics)
        return model, metrics

    # ================================================================
    # LSTM (TensorFlow / Keras)
    # ================================================================
    @staticmethod
    def train_lstm(
        X_train: np.ndarray,
        y_train: np.ndarray,
        X_val: np.ndarray,
        y_val: np.ndarray,
        seq_length: int,
        n_features: int,
        n_classes: int = 2,
        epochs: int = 50,
        batch_size: int = 64,
        learning_rate: float = 1e-3,
    ) -> Tuple[Any, Dict[str, float]]:
        """Train a Keras LSTM classifier.

        The architecture:
            LSTM(64) -> Dropout(0.3) -> LSTM(32) -> Dropout(0.3) ->
            Dense(16, relu) -> Dense(n_classes, softmax)

        Parameters
        ----------
        X_train : np.ndarray
            Shape ``(n_samples, seq_length, n_features)``.
        y_train : np.ndarray
            Integer class labels.
        X_val, y_val : np.ndarray
            Validation data.
        seq_length : int
            Time-step dimension (for reference / logging only; inferred
            from ``X_train.shape[1]``).
        n_features : int
            Feature dimension (for reference / logging only).
        n_classes : int
            Number of output classes.  Default ``2`` (binary).
        epochs : int
            Maximum training epochs (early stopping may cut short).
        batch_size : int
            Mini-batch size.
        learning_rate : float
            Adam optimiser learning rate.

        Returns
        -------
        tuple[tf.keras.Model, dict]
        """
        if not _TF_AVAILABLE:
            raise ImportError("tensorflow is not installed.")

        from tensorflow.keras.callbacks import EarlyStopping, ReduceLROnPlateau
        from tensorflow.keras.layers import LSTM, Dense, Dropout, Input
        from tensorflow.keras.models import Sequential
        from tensorflow.keras.utils import to_categorical

        # Encode labels
        y_train_cat = to_categorical(y_train, num_classes=n_classes)
        y_val_cat = to_categorical(y_val, num_classes=n_classes)

        # Build model
        model = Sequential(
            [
                Input(shape=(X_train.shape[1], X_train.shape[2])),
                LSTM(64, return_sequences=True),
                Dropout(0.3),
                LSTM(32, return_sequences=False),
                Dropout(0.3),
                Dense(16, activation="relu"),
                Dense(n_classes, activation="softmax"),
            ]
        )
        model.compile(
            optimizer=tf.keras.optimizers.Adam(learning_rate=learning_rate),
            loss="categorical_crossentropy",
            metrics=["accuracy"],
        )

        callbacks = [
            EarlyStopping(
                monitor="val_loss", patience=10, restore_best_weights=True
            ),
            ReduceLROnPlateau(
                monitor="val_loss", factor=0.5, patience=5, min_lr=1e-6
            ),
        ]

        model.fit(
            X_train,
            y_train_cat,
            validation_data=(X_val, y_val_cat),
            epochs=epochs,
            batch_size=batch_size,
            callbacks=callbacks,
            verbose=1,
        )

        # Evaluate
        y_prob = model.predict(X_val, verbose=0)
        y_pred = np.argmax(y_prob, axis=1)

        if n_classes == 2:
            metrics = ModelTrainer.evaluate(
                y_val, y_pred, y_prob[:, 1], task="classification"
            )
        else:
            metrics = ModelTrainer.evaluate(
                y_val, y_pred, task="classification"
            )

        logger.info("LSTM metrics: %s", metrics)
        return model, metrics

    # ================================================================
    # Optuna hyper-parameter optimisation
    # ================================================================
    @staticmethod
    def optimize_hyperparams(
        X_train: np.ndarray,
        y_train: np.ndarray,
        X_val: np.ndarray,
        y_val: np.ndarray,
        model_type: str = "lightgbm",
        n_trials: int = 50,
        task: str = "classification",
    ) -> Tuple[Dict[str, Any], float]:
        """Run Optuna hyper-parameter search.

        Parameters
        ----------
        X_train, y_train, X_val, y_val : array-like
            Training and validation data.
        model_type : str
            ``"lightgbm"``, ``"xgboost"``, or ``"random_forest"``.
        n_trials : int
            Number of Optuna trials.
        task : str
            ``"classification"`` or ``"regression"``.

        Returns
        -------
        tuple[dict, float]
            Best parameters and best validation score (accuracy or RMSE).
        """
        if not _OPTUNA_AVAILABLE:
            raise ImportError("optuna is not installed.")

        optuna.logging.set_verbosity(optuna.logging.WARNING)

        def _objective(trial: optuna.Trial) -> float:
            if model_type == "lightgbm":
                params = {
                    "num_leaves": trial.suggest_int("num_leaves", 16, 128),
                    "learning_rate": trial.suggest_float(
                        "learning_rate", 0.01, 0.3, log=True
                    ),
                    "feature_fraction": trial.suggest_float(
                        "feature_fraction", 0.5, 1.0
                    ),
                    "bagging_fraction": trial.suggest_float(
                        "bagging_fraction", 0.5, 1.0
                    ),
                    "bagging_freq": trial.suggest_int("bagging_freq", 1, 10),
                    "min_child_samples": trial.suggest_int(
                        "min_child_samples", 5, 100
                    ),
                    "n_estimators": trial.suggest_int(
                        "n_estimators", 100, 1000
                    ),
                    "early_stopping_rounds": 20,
                }
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore")
                    model, metrics = ModelTrainer.train_lightgbm(
                        X_train, y_train, X_val, y_val, task=task, params=params
                    )

            elif model_type == "xgboost":
                params = {
                    "max_depth": trial.suggest_int("max_depth", 3, 10),
                    "learning_rate": trial.suggest_float(
                        "learning_rate", 0.01, 0.3, log=True
                    ),
                    "subsample": trial.suggest_float("subsample", 0.5, 1.0),
                    "colsample_bytree": trial.suggest_float(
                        "colsample_bytree", 0.5, 1.0
                    ),
                    "n_estimators": trial.suggest_int(
                        "n_estimators", 100, 1000
                    ),
                    "early_stopping_rounds": 20,
                }
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore")
                    model, metrics = ModelTrainer.train_xgboost(
                        X_train, y_train, X_val, y_val, task=task, params=params
                    )

            elif model_type == "random_forest":
                params = {
                    "n_estimators": trial.suggest_int(
                        "n_estimators", 50, 500
                    ),
                    "max_depth": trial.suggest_int("max_depth", 4, 20),
                    "min_samples_leaf": trial.suggest_int(
                        "min_samples_leaf", 2, 50
                    ),
                    "max_features": trial.suggest_categorical(
                        "max_features", ["sqrt", "log2", None]
                    ),
                }
                model, metrics = ModelTrainer.train_random_forest(
                    X_train, y_train, X_val, y_val, task=task, params=params
                )
            else:
                raise ValueError(f"Unsupported model_type: {model_type}")

            if task == "classification":
                return metrics.get("f1", 0.0)
            else:
                return -metrics.get("rmse", float("inf"))  # minimise

        study = optuna.create_study(
            direction="maximize",
            study_name=f"{model_type}_{task}_optimisation",
        )
        study.optimize(_objective, n_trials=n_trials, show_progress_bar=True)

        logger.info(
            "Best %s params (score=%.4f): %s",
            model_type,
            study.best_value,
            study.best_params,
        )
        return study.best_params, study.best_value

    # ================================================================
    # Evaluation
    # ================================================================
    @staticmethod
    def evaluate(
        y_true: np.ndarray,
        y_pred: np.ndarray,
        y_prob: Optional[np.ndarray] = None,
        task: str = "classification",
    ) -> Dict[str, float]:
        """Compute a standard set of evaluation metrics.

        Parameters
        ----------
        y_true : array-like
            Ground truth labels / values.
        y_pred : array-like
            Model predictions.
        y_prob : array-like, optional
            Predicted probabilities for the positive class (binary only).
        task : str
            ``"classification"`` or ``"regression"``.

        Returns
        -------
        dict[str, float]
            Metric name -> value.
        """
        y_true = np.asarray(y_true)
        y_pred = np.asarray(y_pred)

        if task == "classification":
            metrics: Dict[str, float] = {
                "accuracy": float(accuracy_score(y_true, y_pred)),
                "precision": float(
                    precision_score(y_true, y_pred, zero_division=0)
                ),
                "recall": float(
                    recall_score(y_true, y_pred, zero_division=0)
                ),
                "f1": float(f1_score(y_true, y_pred, zero_division=0)),
            }
            if y_prob is not None:
                try:
                    metrics["auc_roc"] = float(roc_auc_score(y_true, y_prob))
                except ValueError:
                    metrics["auc_roc"] = 0.0
            return metrics

        # Regression
        return {
            "rmse": float(np.sqrt(mean_squared_error(y_true, y_pred))),
            "mae": float(mean_absolute_error(y_true, y_pred)),
            "r2": float(r2_score(y_true, y_pred)),
        }

    # ================================================================
    # ONNX Export
    # ================================================================
    @staticmethod
    def export_to_onnx(
        model: Any,
        model_type: str,
        n_features: int,
        output_path: Union[str, Path],
        seq_length: Optional[int] = None,
    ) -> Path:
        """Export a trained model to ONNX format for MQL5 inference.

        Parameters
        ----------
        model : object
            Trained model (LightGBM, XGBoost, RandomForest, or Keras).
        model_type : str
            ``"lightgbm"``, ``"xgboost"``, ``"random_forest"``, or ``"lstm"``.
        n_features : int
            Number of input features.
        output_path : str | Path
            Destination ``.onnx`` file path.
        seq_length : int, optional
            Required when ``model_type="lstm"`` – the time-step dimension.

        Returns
        -------
        Path
            The path the ONNX file was written to.
        """
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        if model_type in ("lightgbm", "xgboost"):
            if not _ONNX_AVAILABLE:
                raise ImportError(
                    "onnxmltools / skl2onnx is not installed."
                )

            if model_type == "lightgbm":
                from onnxmltools.convert import convert_lightgbm
                from onnxmltools.convert.common.data_types import (
                    FloatTensorType as OnnxFloatTensor,
                )

                initial_type = [
                    ("input", OnnxFloatTensor([None, n_features]))
                ]
                onnx_model = convert_lightgbm(
                    model, initial_types=initial_type
                )
            else:  # xgboost
                from onnxmltools.convert import convert_xgboost
                from onnxmltools.convert.common.data_types import (
                    FloatTensorType as OnnxFloatTensor,
                )

                initial_type = [
                    ("input", OnnxFloatTensor([None, n_features]))
                ]
                onnx_model = convert_xgboost(
                    model, initial_types=initial_type
                )

            import onnx as onnx_lib

            onnx_lib.save_model(onnx_model, str(output_path))

        elif model_type == "random_forest":
            if not _ONNX_AVAILABLE:
                raise ImportError("skl2onnx is not installed.")

            initial_type = [
                ("input", FloatTensorType([None, n_features]))
            ]
            onnx_model = convert_sklearn(
                model, initial_types=initial_type
            )
            import onnx as onnx_lib

            onnx_lib.save_model(onnx_model, str(output_path))

        elif model_type == "lstm":
            if not _TF_AVAILABLE or not _TF2ONNX_AVAILABLE:
                raise ImportError(
                    "tensorflow and/or tf2onnx are not installed."
                )
            if seq_length is None:
                raise ValueError(
                    "seq_length is required for LSTM ONNX export."
                )

            import tf2onnx

            spec = (
                tf.TensorSpec(
                    (None, seq_length, n_features),
                    tf.float32,
                    name="input",
                ),
            )
            onnx_model, _ = tf2onnx.convert.from_keras(
                model, input_signature=spec, opset=13
            )
            import onnx as onnx_lib

            onnx_lib.save_model(onnx_model, str(output_path))

        else:
            raise ValueError(f"Unsupported model_type for ONNX: {model_type}")

        logger.info("Exported %s model to %s", model_type, output_path)
        return output_path

    # ================================================================
    # Scaler persistence  (mean / scale / feature names)
    # ================================================================
    @staticmethod
    def save_scaler(
        scaler: Any,
        output_dir: Union[str, Path],
        model_name: str,
    ) -> None:
        """Save a StandardScaler's parameters to disk for MQL5 inference.

        Creates three files:
            - ``{model_name}_mean.npy``  – per-feature means
            - ``{model_name}_scale.npy`` – per-feature standard deviations
            - ``{model_name}_feature_names.txt`` – one feature name per line

        Parameters
        ----------
        scaler : sklearn.preprocessing.StandardScaler
            Fitted scaler.
        output_dir : str | Path
            Directory to write files into.
        model_name : str
            Prefix for filenames.
        """
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        np.save(
            output_dir / f"{model_name}_mean.npy",
            scaler.mean_.astype(np.float32),
        )
        np.save(
            output_dir / f"{model_name}_scale.npy",
            scaler.scale_.astype(np.float32),
        )

        if hasattr(scaler, "feature_names_in_"):
            names_path = output_dir / f"{model_name}_feature_names.txt"
            names_path.write_text(
                "\n".join(scaler.feature_names_in_), encoding="utf-8"
            )

        logger.info("Saved scaler params to %s", output_dir)

    @staticmethod
    def load_scaler(
        output_dir: Union[str, Path],
        model_name: str,
    ) -> Dict[str, Any]:
        """Load previously saved scaler parameters.

        Parameters
        ----------
        output_dir : str | Path
            Directory containing the scaler files.
        model_name : str
            Prefix used when saving.

        Returns
        -------
        dict
            ``{"mean": np.ndarray, "scale": np.ndarray,
              "feature_names": list[str] | None}``
        """
        output_dir = Path(output_dir)

        mean = np.load(output_dir / f"{model_name}_mean.npy")
        scale = np.load(output_dir / f"{model_name}_scale.npy")

        names_path = output_dir / f"{model_name}_feature_names.txt"
        feature_names: Optional[List[str]] = None
        if names_path.exists():
            feature_names = names_path.read_text(encoding="utf-8").strip().split("\n")

        logger.info(
            "Loaded scaler: %d features from %s", len(mean), output_dir
        )
        return {
            "mean": mean,
            "scale": scale,
            "feature_names": feature_names,
        }
