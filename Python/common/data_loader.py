"""
Data Loader Module
==================

Handles data ingestion from MetaTrader 5 and CSV files, time-series aware
splitting, and sequence creation for LSTM / transformer models.

Gracefully falls back to CSV loading when the MetaTrader5 package is not
installed or the terminal is not running.
"""

from __future__ import annotations

import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Union

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# MetaTrader5 import with graceful fallback
# ---------------------------------------------------------------------------
try:
    import MetaTrader5 as mt5

    _MT5_AVAILABLE = True
except ImportError:
    _MT5_AVAILABLE = False
    logger.warning(
        "MetaTrader5 package not installed. "
        "Only CSV-based loading will be available."
    )

# ---------------------------------------------------------------------------
# Timeframe mapping  (MQL5 enum value -> MT5 constant)
# ---------------------------------------------------------------------------
TIMEFRAME_MAP: Dict[str, int] = {
    "M1": 1,
    "M2": 2,
    "M3": 3,
    "M4": 4,
    "M5": 5,
    "M6": 6,
    "M10": 10,
    "M12": 12,
    "M15": 15,
    "M20": 20,
    "M30": 30,
    "H1": 16385,
    "H2": 16386,
    "H3": 16387,
    "H4": 16388,
    "H6": 16390,
    "H8": 16392,
    "H12": 16396,
    "D1": 16408,
    "W1": 32769,
    "MN1": 49153,
}

# Reverse lookup for display purposes
TIMEFRAME_NAME: Dict[int, str] = {v: k for k, v in TIMEFRAME_MAP.items()}


def _resolve_mt5_timeframe(timeframe: Union[str, int]) -> int:
    """Convert a string timeframe label to its MT5 integer constant.

    Parameters
    ----------
    timeframe : str | int
        Either a string like ``"M5"`` or the raw MT5 integer constant.

    Returns
    -------
    int
        The MT5 timeframe constant.

    Raises
    ------
    ValueError
        If the string is not recognised.
    """
    if isinstance(timeframe, int):
        return timeframe
    tf_upper = timeframe.upper()
    if tf_upper not in TIMEFRAME_MAP:
        raise ValueError(
            f"Unknown timeframe '{timeframe}'. "
            f"Valid options: {list(TIMEFRAME_MAP.keys())}"
        )
    return TIMEFRAME_MAP[tf_upper]


class DataLoader:
    """Unified data loading interface for the OSS Library.

    Supports MetaTrader 5 terminal (live / historical) and CSV files
    exported by the MQL5 ``DataExporter`` include.

    Examples
    --------
    >>> loader = DataLoader()
    >>> df = loader.load_from_mt5("XAUUSD", "M1", 50000)
    >>> train, val, test = loader.train_val_test_split(df)
    """

    # ------------------------------------------------------------------
    # MT5 loading
    # ------------------------------------------------------------------
    @staticmethod
    def load_from_mt5(
        symbol: str,
        timeframe: Union[str, int],
        n_bars: int,
        start_date: Optional[datetime] = None,
    ) -> pd.DataFrame:
        """Load OHLCV data directly from a running MetaTrader 5 terminal.

        Parameters
        ----------
        symbol : str
            Instrument symbol, e.g. ``"XAUUSD"``.
        timeframe : str | int
            Timeframe label (``"M1"``, ``"H1"``, ...) or MT5 integer.
        n_bars : int
            Number of bars to request.
        start_date : datetime, optional
            If provided, data is fetched starting from this date forward
            (up to ``n_bars``).  Otherwise the most recent ``n_bars`` are
            returned.

        Returns
        -------
        pd.DataFrame
            Columns: ``datetime, open, high, low, close, tick_volume,
            spread, real_volume``.

        Raises
        ------
        RuntimeError
            If the MT5 package is missing or the terminal cannot be reached.
        """
        if not _MT5_AVAILABLE:
            raise RuntimeError(
                "MetaTrader5 package is not installed. "
                "Install it with: pip install MetaTrader5"
            )

        if not mt5.initialize():
            raise RuntimeError(
                f"MT5 initialize() failed – error {mt5.last_error()}"
            )

        try:
            tf = _resolve_mt5_timeframe(timeframe)

            if start_date is not None:
                rates = mt5.copy_rates_from(symbol, tf, start_date, n_bars)
            else:
                rates = mt5.copy_rates_from_pos(symbol, tf, 0, n_bars)

            if rates is None or len(rates) == 0:
                raise RuntimeError(
                    f"No data returned for {symbol} {timeframe}. "
                    f"MT5 error: {mt5.last_error()}"
                )

            df = pd.DataFrame(rates)
            df["datetime"] = pd.to_datetime(df["time"], unit="s")
            df.drop(columns=["time"], inplace=True)

            # Normalise column names to lowercase
            df.columns = [c.lower() for c in df.columns]

            logger.info(
                "Loaded %d bars for %s %s from MT5",
                len(df),
                symbol,
                TIMEFRAME_NAME.get(tf, str(tf)),
            )
            return df

        finally:
            mt5.shutdown()

    # ------------------------------------------------------------------
    # CSV loading
    # ------------------------------------------------------------------
    @staticmethod
    def load_from_csv(filepath: Union[str, Path]) -> pd.DataFrame:
        """Load OHLCV data from a CSV file (MQL5 DataExporter format).

        The CSV is expected to have a header row with at least:
        ``datetime, open, high, low, close``.  Additional columns such as
        ``tick_volume``, ``spread``, ``real_volume`` are preserved if present.

        Parameters
        ----------
        filepath : str | Path
            Path to the CSV file.

        Returns
        -------
        pd.DataFrame
            Parsed data with ``datetime`` as a proper datetime column.
        """
        filepath = Path(filepath)
        if not filepath.exists():
            raise FileNotFoundError(f"CSV file not found: {filepath}")

        df = pd.read_csv(filepath)

        # Normalise column names
        df.columns = [c.strip().lower() for c in df.columns]

        # Parse datetime
        if "datetime" in df.columns:
            df["datetime"] = pd.to_datetime(df["datetime"])
        elif "date" in df.columns and "time" in df.columns:
            df["datetime"] = pd.to_datetime(
                df["date"].astype(str) + " " + df["time"].astype(str)
            )
            df.drop(columns=["date", "time"], inplace=True)
        elif "time" in df.columns:
            df["datetime"] = pd.to_datetime(df["time"])
            df.drop(columns=["time"], inplace=True)
        else:
            logger.warning(
                "No recognised datetime column found – data will lack "
                "timestamps."
            )

        logger.info("Loaded %d rows from %s", len(df), filepath.name)
        return df

    # ------------------------------------------------------------------
    # Multi-symbol loading
    # ------------------------------------------------------------------
    @staticmethod
    def load_multi_symbol(
        symbols: List[str],
        timeframe: Union[str, int],
        n_bars: int,
    ) -> Dict[str, pd.DataFrame]:
        """Load data for multiple symbols from MetaTrader 5.

        Parameters
        ----------
        symbols : list[str]
            List of instrument symbols.
        timeframe : str | int
            Common timeframe for all symbols.
        n_bars : int
            Number of bars per symbol.

        Returns
        -------
        dict[str, pd.DataFrame]
            Mapping ``symbol -> DataFrame``.
        """
        result: Dict[str, pd.DataFrame] = {}
        for sym in symbols:
            try:
                result[sym] = DataLoader.load_from_mt5(sym, timeframe, n_bars)
            except RuntimeError as exc:
                logger.error("Failed to load %s: %s", sym, exc)
        return result

    # ------------------------------------------------------------------
    # Time-series splitting
    # ------------------------------------------------------------------
    @staticmethod
    def train_val_test_split(
        df: pd.DataFrame,
        train_ratio: float = 0.70,
        val_ratio: float = 0.15,
    ) -> Tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
        """Split a DataFrame chronologically into train / val / test.

        Unlike ``sklearn.train_test_split``, this preserves temporal order
        which is critical for time-series data to prevent look-ahead bias.

        Parameters
        ----------
        df : pd.DataFrame
            Full dataset (must already be sorted by time).
        train_ratio : float
            Fraction of rows for training.  Default ``0.70``.
        val_ratio : float
            Fraction of rows for validation.  Default ``0.15``.
            The remainder goes to the test set.

        Returns
        -------
        tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]
            ``(train, val, test)`` DataFrames with reset indices.
        """
        n = len(df)
        train_end = int(n * train_ratio)
        val_end = int(n * (train_ratio + val_ratio))

        train = df.iloc[:train_end].reset_index(drop=True)
        val = df.iloc[train_end:val_end].reset_index(drop=True)
        test = df.iloc[val_end:].reset_index(drop=True)

        logger.info(
            "Split %d rows -> train=%d, val=%d, test=%d",
            n,
            len(train),
            len(val),
            len(test),
        )
        return train, val, test

    # ------------------------------------------------------------------
    # Sequence creation (LSTM / Transformer)
    # ------------------------------------------------------------------
    @staticmethod
    def create_sequences(
        data: np.ndarray,
        seq_length: int,
        target_col: int,
    ) -> Tuple[np.ndarray, np.ndarray]:
        """Create sliding-window sequences for recurrent models.

        Parameters
        ----------
        data : np.ndarray
            2-D array of shape ``(n_samples, n_features)``.
        seq_length : int
            Number of past time steps per input sample.
        target_col : int
            Column index used as the prediction target.

        Returns
        -------
        tuple[np.ndarray, np.ndarray]
            ``X`` with shape ``(n_sequences, seq_length, n_features)`` and
            ``y`` with shape ``(n_sequences,)``.
        """
        if data.ndim != 2:
            raise ValueError(
                f"Expected 2-D array, got shape {data.shape}"
            )
        if seq_length >= len(data):
            raise ValueError(
                f"seq_length ({seq_length}) must be less than "
                f"data length ({len(data)})"
            )

        xs: List[np.ndarray] = []
        ys: List[float] = []

        for i in range(seq_length, len(data)):
            xs.append(data[i - seq_length : i])
            ys.append(data[i, target_col])

        X = np.array(xs, dtype=np.float32)
        y = np.array(ys, dtype=np.float32)

        logger.info(
            "Created %d sequences of length %d with %d features",
            X.shape[0],
            seq_length,
            X.shape[2],
        )
        return X, y
