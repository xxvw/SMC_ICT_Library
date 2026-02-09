"""
Feature Engineering Module
==========================

Provides a comprehensive library of feature transformations tailored for
forex / gold price data and Smart-Money-Concept (SMC) / ICT strategies.

All methods accept and return ``pd.DataFrame`` so they can be chained:

>>> fe = FeatureEngineer()
>>> df = (
...     fe.add_returns(df)
...       .pipe(fe.add_volatility)
...       .pipe(fe.add_candlestick_features)
...       .pipe(fe.add_momentum)
...       .pipe(fe.add_time_features)
...       .pipe(fe.add_smc_features)
... )
"""

from __future__ import annotations

import logging
from typing import List, Optional

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

# Columns that are never considered features
_META_COLS = frozenset(
    ["datetime", "open", "high", "low", "close", "tick_volume",
     "spread", "real_volume", "volume", "target"]
)


class FeatureEngineer:
    """Stateless feature-engineering toolkit for OHLCV data.

    Every ``add_*`` method mutates the DataFrame **in-place** (for memory
    efficiency) and also returns it so calls can be chained.
    """

    # ------------------------------------------------------------------
    # Returns
    # ------------------------------------------------------------------
    @staticmethod
    def add_returns(
        df: pd.DataFrame,
        periods: Optional[List[int]] = None,
    ) -> pd.DataFrame:
        """Add log-return features for multiple look-back periods.

        Parameters
        ----------
        df : pd.DataFrame
            Must contain a ``close`` column.
        periods : list[int], optional
            Look-back windows.  Default ``[1, 3, 5, 10, 20]``.

        Returns
        -------
        pd.DataFrame
            Same DataFrame with new ``return_{p}`` columns.
        """
        if periods is None:
            periods = [1, 3, 5, 10, 20]

        close = df["close"]
        for p in periods:
            df[f"return_{p}"] = np.log(close / close.shift(p))

        logger.debug("Added return features for periods %s", periods)
        return df

    # ------------------------------------------------------------------
    # Volatility
    # ------------------------------------------------------------------
    @staticmethod
    def add_volatility(
        df: pd.DataFrame,
        periods: Optional[List[int]] = None,
    ) -> pd.DataFrame:
        """Add rolling volatility (std of log-returns) features.

        Parameters
        ----------
        df : pd.DataFrame
            Must contain a ``close`` column.
        periods : list[int], optional
            Rolling window sizes.  Default ``[5, 10, 20]``.

        Returns
        -------
        pd.DataFrame
        """
        if periods is None:
            periods = [5, 10, 20]

        # Ensure 1-bar returns exist
        if "return_1" not in df.columns:
            df["return_1"] = np.log(df["close"] / df["close"].shift(1))

        for p in periods:
            df[f"volatility_{p}"] = df["return_1"].rolling(p).std()

        logger.debug("Added volatility features for periods %s", periods)
        return df

    # ------------------------------------------------------------------
    # Candlestick geometry
    # ------------------------------------------------------------------
    @staticmethod
    def add_candlestick_features(df: pd.DataFrame) -> pd.DataFrame:
        """Add candle-shape features derived from OHLC values.

        Features created:
        - ``body_ratio``: absolute body / total range
        - ``upper_wick_ratio``: upper shadow / total range
        - ``lower_wick_ratio``: lower shadow / total range
        - ``candle_range``: high - low (absolute)
        - ``body_direction``: +1 bullish, -1 bearish, 0 doji

        Parameters
        ----------
        df : pd.DataFrame
            Must contain ``open, high, low, close``.

        Returns
        -------
        pd.DataFrame
        """
        o, h, l, c = df["open"], df["high"], df["low"], df["close"]
        total_range = h - l

        # Avoid division by zero for zero-range bars
        safe_range = total_range.replace(0, np.nan)

        body = (c - o).abs()
        upper_wick = h - pd.concat([o, c], axis=1).max(axis=1)
        lower_wick = pd.concat([o, c], axis=1).min(axis=1) - l

        df["body_ratio"] = (body / safe_range).fillna(0.0)
        df["upper_wick_ratio"] = (upper_wick / safe_range).fillna(0.0)
        df["lower_wick_ratio"] = (lower_wick / safe_range).fillna(0.0)
        df["candle_range"] = total_range
        df["body_direction"] = np.sign(c - o).astype(int)

        logger.debug("Added candlestick geometry features")
        return df

    # ------------------------------------------------------------------
    # Momentum
    # ------------------------------------------------------------------
    @staticmethod
    def add_momentum(
        df: pd.DataFrame,
        periods: Optional[List[int]] = None,
    ) -> pd.DataFrame:
        """Add RSI-like momentum features computed from returns.

        For each *period*, the momentum score is calculated as:

        .. math::

            \\text{momentum}_p = \\frac{\\text{avg\\_gain}_p}
                                      {\\text{avg\\_gain}_p + \\text{avg\\_loss}_p}

        The result is in [0, 1] and centred at 0.5 (similar to RSI / 100).

        Parameters
        ----------
        df : pd.DataFrame
            Must contain a ``close`` column.
        periods : list[int], optional
            Rolling windows.  Default ``[5, 10, 20]``.

        Returns
        -------
        pd.DataFrame
        """
        if periods is None:
            periods = [5, 10, 20]

        delta = df["close"].diff()
        gain = delta.clip(lower=0)
        loss = (-delta).clip(lower=0)

        for p in periods:
            avg_gain = gain.rolling(p, min_periods=1).mean()
            avg_loss = loss.rolling(p, min_periods=1).mean()
            total = avg_gain + avg_loss
            df[f"momentum_{p}"] = np.where(
                total > 0, avg_gain / total, 0.5
            )

        logger.debug("Added momentum features for periods %s", periods)
        return df

    # ------------------------------------------------------------------
    # Time / session features
    # ------------------------------------------------------------------
    @staticmethod
    def add_time_features(df: pd.DataFrame) -> pd.DataFrame:
        """Add cyclical time encodings and session dummy variables.

        Cyclical encodings use ``sin`` / ``cos`` so the model understands
        that hour 23 is close to hour 0.

        Session dummies (mutually exclusive):
        - ``session_asian``   : 00:00-08:00 UTC
        - ``session_london``  : 08:00-16:00 UTC
        - ``session_ny``      : 13:00-21:00 UTC  (overlaps London)

        Parameters
        ----------
        df : pd.DataFrame
            Must contain a ``datetime`` column (or a datetime index).

        Returns
        -------
        pd.DataFrame
        """
        dt = df["datetime"] if "datetime" in df.columns else df.index

        hour = dt.dt.hour + dt.dt.minute / 60.0
        day = dt.dt.dayofweek  # Monday=0

        df["hour_sin"] = np.sin(2 * np.pi * hour / 24)
        df["hour_cos"] = np.cos(2 * np.pi * hour / 24)
        df["day_sin"] = np.sin(2 * np.pi * day / 5)  # 5 trading days
        df["day_cos"] = np.cos(2 * np.pi * day / 5)

        # Session dummies
        raw_hour = dt.dt.hour
        df["session_asian"] = ((raw_hour >= 0) & (raw_hour < 8)).astype(int)
        df["session_london"] = ((raw_hour >= 8) & (raw_hour < 16)).astype(int)
        df["session_ny"] = ((raw_hour >= 13) & (raw_hour < 21)).astype(int)

        logger.debug("Added time / session features")
        return df

    # ------------------------------------------------------------------
    # SMC / ICT features
    # ------------------------------------------------------------------
    @staticmethod
    def add_smc_features(df: pd.DataFrame) -> pd.DataFrame:
        """Add Smart-Money-Concept (SMC) / ICT features.

        Features created:

        **Fair Value Gaps (FVG)**
        - ``fvg_bullish``: 1 when bar[i-1].low > bar[i+1].high (3-bar gap up)
        - ``fvg_bearish``: 1 when bar[i-1].high < bar[i+1].low (3-bar gap down)
        - ``fvg_size``: absolute size of the gap (0 when no FVG)

        **Swing Points**  (approximation using ±2 bar look-around)
        - ``swing_high``: 1 at a local high
        - ``swing_low``:  1 at a local low

        **Break of Structure (BOS) proxy**
        - ``bos_bull``: close exceeds the rolling 20-bar high
        - ``bos_bear``: close breaks below the rolling 20-bar low

        **Order Block proxy**
        - ``ob_bull``: last bearish candle before a BOS-bull event
        - ``ob_bear``: last bullish candle before a BOS-bear event

        Parameters
        ----------
        df : pd.DataFrame
            Must contain ``open, high, low, close``.

        Returns
        -------
        pd.DataFrame
        """
        h, l, c, o = df["high"], df["low"], df["close"], df["open"]

        # --- Fair Value Gaps (FVG) ---
        # Bullish FVG: bar[i-2].high < bar[i].low  (gap between candle i-2 top and candle i bottom)
        prev2_high = h.shift(2)
        curr_low = l
        fvg_bull = (curr_low > prev2_high).astype(int)

        # Bearish FVG: bar[i-2].low > bar[i].high
        prev2_low = l.shift(2)
        curr_high = h
        fvg_bear = (curr_high < prev2_low).astype(int)

        df["fvg_bullish"] = fvg_bull
        df["fvg_bearish"] = fvg_bear
        df["fvg_size"] = np.where(
            fvg_bull == 1,
            curr_low - prev2_high,
            np.where(fvg_bear == 1, prev2_low - curr_high, 0.0),
        )

        # --- Swing Points (±2 bar window) ---
        swing_window = 2
        df["swing_high"] = (
            (h == h.rolling(2 * swing_window + 1, center=True).max())
            & (h > h.shift(1))
            & (h > h.shift(-1))
        ).astype(int)

        df["swing_low"] = (
            (l == l.rolling(2 * swing_window + 1, center=True).min())
            & (l < l.shift(1))
            & (l < l.shift(-1))
        ).astype(int)

        # --- Break of Structure proxy ---
        rolling_high = h.rolling(20, min_periods=1).max().shift(1)
        rolling_low = l.rolling(20, min_periods=1).min().shift(1)

        df["bos_bull"] = (c > rolling_high).astype(int)
        df["bos_bear"] = (c < rolling_low).astype(int)

        # --- Order Block proxy ---
        # Bullish OB: the last bearish candle before a bullish BOS
        is_bearish = (c < o).astype(int)
        is_bullish_candle = (c > o).astype(int)

        df["ob_bull"] = (is_bearish.shift(1) * df["bos_bull"]).clip(0, 1)
        df["ob_bear"] = (is_bullish_candle.shift(1) * df["bos_bear"]).clip(0, 1)

        logger.debug("Added SMC / ICT features")
        return df

    # ------------------------------------------------------------------
    # Feature selection
    # ------------------------------------------------------------------
    @staticmethod
    def select_features(
        df: pd.DataFrame,
        target: str,
        method: str = "correlation",
        threshold: float = 0.95,
    ) -> pd.DataFrame:
        """Remove highly correlated or low-importance features.

        Parameters
        ----------
        df : pd.DataFrame
            Dataset including the ``target`` column.
        target : str
            Name of the target column.
        method : str
            ``"correlation"`` – drop features whose pairwise |correlation|
            exceeds ``threshold``.
        threshold : float
            Correlation cut-off (only used when ``method="correlation"``).

        Returns
        -------
        pd.DataFrame
            Reduced DataFrame (target column is preserved).
        """
        feature_cols = [
            c for c in df.columns
            if c not in _META_COLS and c != target
        ]

        if method == "correlation":
            corr_matrix = df[feature_cols].corr().abs()
            upper = corr_matrix.where(
                np.triu(np.ones(corr_matrix.shape, dtype=bool), k=1)
            )
            to_drop = [
                col for col in upper.columns
                if any(upper[col] > threshold)
            ]
            logger.info(
                "Dropping %d highly correlated features (threshold=%.2f): %s",
                len(to_drop),
                threshold,
                to_drop,
            )
            df = df.drop(columns=to_drop)
        else:
            raise ValueError(f"Unknown feature selection method: {method}")

        return df

    # ------------------------------------------------------------------
    # Utility
    # ------------------------------------------------------------------
    @staticmethod
    def get_feature_names(
        df: pd.DataFrame,
        exclude: Optional[List[str]] = None,
    ) -> List[str]:
        """Return the list of feature column names.

        Parameters
        ----------
        df : pd.DataFrame
        exclude : list[str], optional
            Columns to exclude.  Defaults to the standard meta columns
            (datetime, OHLCV, target).

        Returns
        -------
        list[str]
        """
        if exclude is None:
            exclude = list(_META_COLS)
        exclude_set = set(c.lower() for c in exclude)
        return [c for c in df.columns if c.lower() not in exclude_set]
