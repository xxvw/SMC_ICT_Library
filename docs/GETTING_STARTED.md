# Getting Started / はじめに

## 目次

1. [動作要件](#動作要件)
2. [MQL5ライブラリのインストール](#mql5ライブラリのインストール)
3. [Python環境のセットアップ](#python環境のセットアップ)
4. [最初の一歩：FVGを検出する](#最初の一歩fvgを検出する)
5. [全機能を統合して使う](#全機能を統合して使う)
6. [インジケーターで可視化する](#インジケーターで可視化する)
7. [サンプルEAを動かす](#サンプルeaを動かす)
8. [次のステップ](#次のステップ)

---

## 動作要件

### MQL5

| 項目 | 要件 |
|---|---|
| MetaTrader 5 | Build 3000以上推奨 |
| MQL5 | 標準ライブラリ（デフォルトで含まれる） |
| ONNX機能 | MT5 Build 3600以上（ONNXWrapper使用時のみ） |

### Python（ML学習スクリプト使用時のみ）

| 項目 | 要件 |
|---|---|
| Python | 3.9 以上 |
| MetaTrader5 | Python パッケージ（データ取得用） |

---

## MQL5ライブラリのインストール

### 方法1: フォルダコピー（推奨）

1. MetaTrader 5の **データフォルダ** を開く
   - MetaTrader 5 → `ファイル` → `データフォルダを開く`

2. 以下のようにファイルをコピー

```
あなたのMT5データフォルダ/
└── MQL5/
    ├── Include/
    │   └── SMC/              ← Include/SMC/ フォルダ全体をここにコピー
    ├── Indicators/
    │   └── SMC_Visualizer.mq5  ← Indicators/ からコピー
    ├── Experts/
    │   └── SMC_Sample_EA.mq5   ← Experts/ からコピー
    └── Scripts/
        └── SMC_DataExport.mq5  ← Scripts/ からコピー
```

3. MetaEditorを開き、`コンパイル` を実行して確認

### 方法2: GitHubからクローン

```bash
cd "あなたのMT5データフォルダ/MQL5"
git clone https://github.com/your-repo/SMC_ICT_Library.git
```

> **注意**: `Include/SMC/` フォルダは `MQL5/Include/SMC/` に配置する必要があります。クローンした場合は、Include内のSMCフォルダを `MQL5/Include/` 直下にコピーまたはシンボリックリンクを作成してください。

### 動作確認

MetaEditorで新規ファイルを作成し、以下を入力してコンパイルが通ることを確認：

```cpp
#include <SMC/SmcManager.mqh>

void OnStart()
{
   Print("SMC Library version: ", SMC_LIB_VERSION);
}
```

---

## Python環境のセットアップ

ML学習スクリプトを使用する場合のみ必要です。

```bash
# 1. Python/ フォルダに移動
cd Python/

# 2. 仮想環境作成（推奨）
python -m venv venv
source venv/bin/activate      # Linux/Mac
# venv\Scripts\activate       # Windows

# 3. 依存関係インストール
pip install -r requirements.txt
```

軽量な構文チェック・lint・単体テストだけを確認する場合は、リポジトリルートで以下を実行します。

```bash
pip install numpy pandas scikit-learn ruff
python tools/check_python.py
python tools/check_mql5_static.py
```

### 主な依存パッケージ

| パッケージ | 用途 |
|---|---|
| MetaTrader5 | MT5からのデータ取得 |
| pandas, numpy | データ処理 |
| scikit-learn | 前処理・評価 |
| lightgbm, xgboost | 勾配ブースティングモデル |
| tensorflow | LSTMモデル |
| optuna | ハイパーパラメータ最適化 |
| onnx, onnxruntime | ONNX変換・推論 |
| skl2onnx, tf2onnx, onnxmltools | モデル→ONNX変換 |

---

## 最初の一歩：FVGを検出する

最もシンプルな使い方として、単体モジュールでFVG（Fair Value Gap）を検出する例です。

```cpp
//+------------------------------------------------------------------+
//| FVG検出の最小例                                                    |
//+------------------------------------------------------------------+
#include <SMC/FairValueGap.mqh>

CSmcFairValueGap fvg;

int OnInit()
{
   // 初期化（シンボル, タイムフレーム, 描画有効）
   if(!fvg.Init(_Symbol, _Period, true))
      return INIT_FAILED;

   return INIT_SUCCEEDED;
}

void OnTick()
{
   // 毎ティック更新
   fvg.Update();

   // 現在価格に最も近い Bullish FVG を取得
   SmcZone zone;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(fvg.GetNearestBullishFVG(bid, zone))
   {
      if(zone.IsFresh())
         Print("Fresh Bullish FVG: ",
               zone.bottomPrice, " - ", zone.topPrice);
   }

   // FVGの統計情報
   Print("Bullish FVGs: ", fvg.GetBullishCount(),
         " (Fresh: ", fvg.GetFreshBullishCount(), ")");
   Print("Bearish FVGs: ", fvg.GetBearishCount(),
         " (Fresh: ", fvg.GetFreshBearishCount(), ")");
}

void OnDeinit(const int reason)
{
   fvg.Clean();
}
```

**ポイント:**
- `Init()` の第3引数 `true` でチャートにFVGゾーンが描画される
- `false` にすればバックテスト等で描画なしの高速動作が可能
- `SmcZone` 構造体でゾーン情報（上端/下端/状態/スコア等）にアクセス

---

## 全機能を統合して使う

`CSmcManager` を使えば、全10モジュール + 分析2モジュールを一括管理できます。

```cpp
#include <SMC/SmcManager.mqh>

CSmcManager *smc;

int OnInit()
{
   smc = new CSmcManager();

   // Init(シンボル, タイムフレーム, 描画, 通貨強弱, VIX)
   if(!smc.Init(_Symbol, _Period, true, true, true))
   {
      delete smc;
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

void OnTick()
{
   smc.Update();  // 全モジュールを依存関係順に一括更新

   // --- トレンド確認
   if(smc.IsBullish())
      Print("Bullish Trend");
   else if(smc.IsBearish())
      Print("Bearish Trend");

   // --- BOS/CHoCH確認
   if(smc.Structure()->HasRecentBOS(10))
      Print("Recent BOS detected!");
   if(smc.Structure()->HasRecentCHoCH(10))
      Print("Recent CHoCH detected!");

   // --- コンフルエンスシグナル
   ENUM_ENTRY_SIGNAL signal = smc.GetSignal();
   if(signal == SIGNAL_BUY)
      Print("BUY signal with confluence!");

   // --- VIX確認
   if(smc.VIX() != NULL)
      Print("VIX: ", smc.VIX().GetVIX(),
            " (", smc.VIX().GetVIXLevelName(), ")");

   // --- 通貨強弱
   if(smc.CurrStr() != NULL)
   {
      Print("USD: ", smc.CurrStr().GetStrength("USD"));
      Print("Strongest: ", smc.CurrStr().GetStrongest());
      Print("Weakest: ", smc.CurrStr().GetWeakest());
   }
}

void OnDeinit(const int reason)
{
   if(smc != NULL)
   {
      smc.Clean();
      delete smc;
   }
}
```

**ポイント:**
- `Update()` は内部で正しい依存関係順（SwingPoints → Structure → OB → ...）に更新
- 各モジュールへは `smc.Swing()`, `smc.OB()`, `smc.FVG()` 等のアクセサでアクセス
- 通貨強弱・VIXは `Init()` の第4・第5引数で有効/無効を制御

---

## インジケーターで可視化する

`SMC_Visualizer.mq5` をMT5のナビゲーターからチャートにドラッグ＆ドロップすると、全SMCコンセプトがチャート上に可視化されます。

### 設定パラメータ

| パラメータ | デフォルト | 説明 |
|---|---|---|
| ShowSwingPoints | true | スイングH/L表示 |
| ShowMarketStructure | true | BOS/CHoCH表示 |
| ShowOrderBlocks | true | OBゾーン表示 |
| ShowFVG | true | FVGゾーン表示 |
| ShowLiquidity | true | EQH/EQL/Pool/Sweep表示 |
| ShowPremiumDiscount | true | Premium/Discountゾーン表示 |
| ShowOTE | true | OTEフィボナッチゾーン表示 |
| ShowKillZones | true | セッション時間帯表示 |
| ShowBreakerBlocks | true | Breaker/Mitigation Block表示 |
| SwingPeriod | 5 | スイング検出の左右確認バー数 |

---

## サンプルEAを動かす

`SMC_Sample_EA.mq5` はコンフルエンスベースのシグナルで自動売買するサンプルです。

### ストラテジーテスターでの実行

1. MetaTrader 5 → `表示` → `ストラテジーテスター`
2. EA: `SMC_Sample_EA` を選択
3. シンボル・期間を設定
4. `開始` をクリック

### 主要パラメータ

| パラメータ | デフォルト | 説明 |
|---|---|---|
| InpRiskPercent | 1.0 | 口座残高に対するリスク率 (%) |
| InpMaxSpreadPips | 3.0 | スプレッドフィルター上限 (pips) |
| InpMinConfluence | 3 | 最小コンフルエンス要因数 |
| InpMinScore | 0.5 | 最小コンフルエンススコア (0.0-1.0) |
| InpEnableKillZoneFilter | true | キルゾーン外でのエントリーを禁止 |
| InpEnableVIXFilter | true | VIX Extremeでのエントリーを禁止 |
| InpEnableDashboard | true | チャート上にダッシュボードを表示 |

### EAの動作フロー

```
OnTick()
  ├── 新バーチェック
  ├── g_smc.Update()              ← 全SMCモジュール更新
  ├── CheckFilters()              ← スプレッド / VIX / KZ / 通貨強弱
  ├── g_smc.GetSignal()           ← コンフルエンスシグナル取得
  ├── PositionSelect()            ← 既存ポジション確認
  └── OpenBuyTrade / SellTrade    ← エントリー実行
       ├── OB検索 → SL設定
       ├── ロット計算（リスク%ベース）
       └── TP = RR 1:2
```

---

## 次のステップ

| やりたいこと | 参照先 |
|---|---|
| 各モジュールの全メソッドを知りたい | [API_REFERENCE.md](API_REFERENCE.md) |
| SMC/ICTの概念そのものを理解したい | [SMC_CONCEPTS.md](SMC_CONCEPTS.md) |
| もっと実践的なコード例が欲しい | [EXAMPLES.md](EXAMPLES.md) |
| 機械学習モデルを学習したい | [PYTHON_ML.md](PYTHON_ML.md) |
| アーキテクチャの詳細を知りたい | [ARCHITECTURE.md](ARCHITECTURE.md) |
