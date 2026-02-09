# SMC/ICT Concepts Library for MQL5

**Smart Money Concepts (SMC) / Inner Circle Trader (ICT) の概念をMQL5で実装したオープンソースライブラリ**

An open-source MQL5 library implementing Smart Money Concepts (SMC) and Inner Circle Trader (ICT) methodologies, with integrated currency strength analysis, volatility (VIX) calculation, trading utilities, and 15 ONNX machine learning training scripts.

---

## Features / 機能一覧

### SMC/ICT Core Concepts

| Module | Description |
|--------|-------------|
| **SwingPoints** | スイングハイ/ロー検出 (両側確認方式) |
| **MarketStructure** | BOS (Break of Structure) / CHoCH (Change of Character) / トレンド・レンジ分析 |
| **OrderBlock** | オーダーブロック検出・状態管理 (FRESH/TESTED/MITIGATED/BROKEN) |
| **FairValueGap** | FVG (Fair Value Gap) / インバランス検出 (3本ローソク足パターン) |
| **Liquidity** | Equal Highs/Lows、流動性プール、流動性スイープ検出 |
| **PremiumDiscount** | Premium / Discount / Equilibrium ゾーン |
| **OptimalTradeEntry** | OTE (Fibonacci 0.618-0.786 ベースエントリーゾーン) |
| **KillZone** | ICT Kill Zones (Asian / London / New York / Overlap セッション) |
| **BreakerBlock** | Breaker Block / Mitigation Block |
| **ConfluenceDetector** | 複合コンフルエンス判定 (全要素のスコアリング) |

### Analysis Modules

| Module | Description |
|--------|-------------|
| **CurrencyStrength** | 8主要通貨 (USD, EUR, GBP, JPY, AUD, CAD, NZD, CHF) の相対強弱分析 |
| **VIXCalculator** | ヒストリカルボラティリティベースの VIX 相当値計算 |

### Utilities

| Module | Description |
|--------|-------------|
| **TradeUtils** | ロット計算、スプレッドフィルター、トレード可否チェック |
| **TimeUtils** | GMT変換、新バー検出、サマータイム判定 |
| **MathUtils** | 標準偏差、Zスコア、相関、線形回帰、パーセンタイル |
| **ArrayUtils** | 配列操作テンプレート関数 |
| **Logger** | レベル付きログ出力 (DEBUG/INFO/WARN/ERROR) |
| **DataExporter** | ML学習用CSVデータエクスポート |
| **OnnxWrapper** | 汎用ONNX推論ラッパー |

### Python ML Training Scripts (15 scripts)

| # | Script | Model | Purpose |
|---|--------|-------|---------|
| 01 | trend_classifier | LightGBM | トレンド方向分類 (Bullish/Bearish/Ranging) |
| 02 | fvg_fill_predictor | XGBoost | FVG充填確率予測 |
| 03 | ob_quality_scorer | LightGBM | オーダーブロック品質スコアリング |
| 04 | bos_choch_detector | LSTM | BOS/CHoCH事前検出 |
| 05 | liquidity_sweep_predictor | XGBoost | 流動性スイープ予測 |
| 06 | entry_timing_optimizer | LightGBM | エントリータイミング最適化 |
| 07 | volatility_regime | RandomForest | ボラティリティレジーム分類 |
| 08 | session_pattern | LightGBM | セッション別パターン認識 |
| 09 | mtf_confluence_scorer | XGBoost | マルチTFコンフルエンススコアリング |
| 10 | price_action_classifier | LSTM | プライスアクションパターン分類 |
| 11 | currency_strength_predictor | LightGBM | 通貨強弱変化予測 |
| 12 | sl_tp_optimizer | XGBoost | SL/TP最適配置 |
| 13 | market_regime_detector | RandomForest | マーケットレジーム検出 |
| 14 | swing_reversal_predictor | LSTM | スイング反転予測 |
| 15 | smc_ensemble | Stacking | 全モデル統合アンサンブル |

---

## Installation / インストール

### MQL5 Library

1. `Include/SMC/` フォルダをMetaTrader 5の `MQL5/Include/` にコピー
2. 必要に応じて `Indicators/` と `Experts/` もコピー

```
MetaTrader 5/
└── MQL5/
    ├── Include/
    │   └── SMC/           ← ここにコピー
    ├── Indicators/
    │   └── SMC_Visualizer.mq5
    └── Experts/
        └── SMC_Sample_EA.mq5
```

### Python Environment

```bash
cd Python/
pip install -r requirements.txt
```

---

## Quick Start / クイックスタート

### Basic Usage (単体モジュール)

```cpp
#include <SMC/FairValueGap.mqh>

CSmcFairValueGap fvg;

int OnInit()
{
    fvg.Init(_Symbol, _Period, true);  // 描画有効
    return INIT_SUCCEEDED;
}

void OnTick()
{
    fvg.Update();

    SmcZone zone;
    if(fvg.GetNearestBullishFVG(SymbolInfoDouble(_Symbol, SYMBOL_BID), zone))
    {
        Print("Nearest Bullish FVG: ", zone.bottomPrice, " - ", zone.topPrice);
    }
}
```

### Full Manager (全モジュール統合)

```cpp
#include <SMC/SmcManager.mqh>

CSmcManager *smc;

int OnInit()
{
    smc = new CSmcManager();
    smc.Init(_Symbol, _Period, true, true, true);
    return INIT_SUCCEEDED;
}

void OnTick()
{
    smc.Update();

    // トレンド確認
    if(smc.IsBullish())
        Print("Bullish Trend");

    // コンフルエンスシグナル
    ENUM_ENTRY_SIGNAL signal = smc.GetSignal();
    if(signal == SIGNAL_BUY)
        Print("BUY Signal with confluence!");

    // 通貨強弱
    if(smc.CurrStr() != NULL)
        Print("USD Strength: ", smc.CurrStr().GetStrength("USD"));

    // VIX
    if(smc.VIX() != NULL)
        Print("VIX: ", smc.VIX().GetVIX(), " (", smc.VIX().GetVIXLevelName(), ")");
}

void OnDeinit(const int reason)
{
    if(smc != NULL) { smc.Clean(); delete smc; }
}
```

### ML Model Training

```bash
cd Python/

# 1. トレンド分類モデルの学習
python 01_trend_classifier.py

# 2. アンサンブルモデルの学習 (全モデルの統合)
python 15_smc_ensemble.py
```

---

## Architecture / アーキテクチャ

```
SmcTypes (enums/structs)
  └── SmcBase (base class)
        └── SmcDrawing (chart objects)
              ├── SwingPoints (foundation)
              │     ├── MarketStructure → OrderBlock → BreakerBlock
              │     ├── Liquidity
              │     ├── PremiumDiscount
              │     └── OptimalTradeEntry
              ├── FairValueGap (independent)
              └── KillZone (independent)

ConfluenceDetector ← references all modules above
SmcManager ← owns and orchestrates all modules
```

### Design Principles / 設計方針

- **Symbol-agnostic**: FX、ゴールド、株式指数など全銘柄対応
- **Timeframe-agnostic**: 全タイムフレーム対応
- **Modular**: 各コンセプトは単独使用可能
- **Unified API**: `Init()` / `Update()` / `Clean()` 共通インターフェース
- **Optional Drawing**: `enableDraw` フラグで描画ON/OFF
- **Resource Sharing**: SmcManager は SwingPoints インスタンスを全モジュールで共有

---

## Contributing / 貢献

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License / ライセンス

MIT License - See [LICENSE](LICENSE) for details.

---

## Disclaimer / 免責事項

このライブラリは教育・研究目的で提供されています。実際のトレードでの使用は自己責任で行ってください。過去のパフォーマンスは将来の結果を保証するものではありません。

This library is provided for educational and research purposes. Use in live trading is at your own risk. Past performance does not guarantee future results.
