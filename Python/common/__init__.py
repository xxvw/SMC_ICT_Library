"""
SMC/ICT OSS Library - Common Python Modules
=============================================

Shared utilities for data loading, feature engineering, and model training
used across all ML-based strategies in the OSS Library.

Modules:
    data_loader   - MT5 / CSV data ingestion, splitting, and sequencing
    feature_base  - Technical and SMC/ICT feature engineering
    model_utils   - Model training, hyperparameter optimization, ONNX export
"""

from importlib import import_module

from common.paths import default_model_dir, resolve_output_dir

_EXPORT_MODULES = {
    "DataLoader": "common.data_loader",
    "FeatureEngineer": "common.feature_base",
    "ModelTrainer": "common.model_utils",
}


def __getattr__(name):
    """Load independent public helpers without requiring optional ML packages."""
    if name not in _EXPORT_MODULES:
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
    value = getattr(import_module(_EXPORT_MODULES[name]), name)
    globals()[name] = value
    return value


def __dir__():
    return sorted(set(globals()) | set(_EXPORT_MODULES))

__all__ = [
    "DataLoader",
    "FeatureEngineer",
    "ModelTrainer",
    "default_model_dir",
    "resolve_output_dir",
]
__version__ = "1.0.0"
