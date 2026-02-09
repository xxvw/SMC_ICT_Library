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

from common.data_loader import DataLoader
from common.feature_base import FeatureEngineer
from common.model_utils import ModelTrainer

__all__ = ["DataLoader", "FeatureEngineer", "ModelTrainer"]
__version__ = "1.0.0"
