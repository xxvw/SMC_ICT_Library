# Python ML パイプラインガイド

## 目次

1. [概要](#概要)
2. [環境セットアップ](#環境セットアップ)
3. [共通モジュール](#共通モジュール)
4. [15学習スクリプト一覧](#15学習スクリプト一覧)
5. [学習の実行方法](#学習の実行方法)
6. [ONNXモデルのMQL5での使用](#onnxモデルのmql5での使用)
7. [カスタムモデルの作成](#カスタムモデルの作成)

---

## 概要

本ライブラリは、MQL5からエクスポートしたデータ（またはMetaTrader5 Python APIで取得したデータ）を使って機械学習モデルを学習し、ONNX形式でMQL5に組み込むフルパイプラインを提供します。

### パイプライン全体フロー

```
[MQL5] DataExporter.mqh  ──CSV──→  [Python] data_loader.py
                                          ↓
                                    feature_base.py (特徴量生成)
                                          ↓
                                    model_utils.py (学習・最適化)
                                          ↓
                                    .onnx モデル + .npy スケーラー
                                          ↓
[MQL5] OnnxWrapper.mqh  ←──────  推論 (リアルタイム)
```

---

## 環境セットアップ

```bash
cd Python/
python -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### requirements.txt 内容

```
MetaTrader5>=5.0.45
pandas>=2.0.0
numpy>=1.24.0
scikit-learn>=1.3.0
lightgbm>=4.0.0
xgboost>=2.0.0
optuna>=3.3.0
onnx>=1.14.0
onnxruntime>=1.15.0
onnxmltools>=1.11.0
skl2onnx>=1.15.0
tensorflow>=2.13.0
tf2onnx>=1.15.0
matplotlib>=3.7.0
seaborn>=0.12.0
```

---

## 共通モジュール

### `common/data_loader.py` - DataLoader

データの取得と分割を担当。

**主な機能:**

| メソッド | 説明 |
|---|---|
| `load_from_mt5(symbol, timeframe, bars)` | MT5 Python APIからデータ取得 |
| `load_from_csv(filepath)` | CSVファイルからデータ読み込み |
| `DataLoader(symbol, timeframe).load(bars)` | 学習スクリプト互換のインスタンスロード |
| `load_multi_symbol(symbols, timeframe, bars)` | 複数シンボル一括取得 |
| `train_val_test_split(df, train_ratio, val_ratio)` | 時系列を考慮したデータ分割（look-ahead bias防止） |
| `create_sequences(data, seq_length, target_col)` | LSTM用のシーケンスデータ作成 |

**使用例:**

```python
from common import DataLoader

loader = DataLoader("EURUSD", "H1")
df = loader.load(50000)
train, val, test = loader.train_val_test_split(df, 0.7, 0.15)
```

### `common/feature_base.py` - FeatureEngineer

特徴量エンジニアリングを担当。

**主な特徴量カテゴリ:**

| カテゴリ | 特徴量例 |
|---|---|
| **リターン系** | 1/5/10/20期間のリターン、ログリターン |
| **ボラティリティ系** | ATR、標準偏差、ボリンジャーバンド幅 |
| **ローソク足系** | 実体比率、上下ヒゲ比率、陽陰パターン |
| **モメンタム系** | RSI、MACD、ストキャスティクス |
| **時間系** | 曜日（sin/cos）、時間（sin/cos）、セッションダミー |
| **SMC系** | FVG近接度、OB近接度、スイング距離、BOS/CHoCH近似 |
| **流動性系** | Equal H/L近接度、Volume変化率 |

**使用例:**

```python
from common import FeatureEngineer

fe = FeatureEngineer()
df = fe.add_returns(df)
df = fe.add_volatility(df)
df = fe.add_candlestick_features(df)
df = fe.add_momentum(df)
df = fe.add_time_features(df)
df = fe.add_smc_features(df)
df = fe.select_features(df, target='label')
```

### `common/model_utils.py` - ModelTrainer

モデル学習・最適化・ONNX変換を担当。

**対応モデル:**

| モデル | ライブラリ | 用途 |
|---|---|---|
| LightGBM | lightgbm | 汎用分類・回帰（高速） |
| XGBoost | xgboost | 汎用分類・回帰（堅牢） |
| RandomForest | scikit-learn | ベースライン・アンサンブル部品 |
| LSTM | tensorflow | 時系列パターン認識 |
| Stacking | scikit-learn | 複数モデルのアンサンブル |

**主な機能:**

| メソッド | 説明 |
|---|---|
| `train_lightgbm/train_xgboost/train_random_forest(...)` | 検証データ付きモデル学習 |
| `train_lgbm/train_xgb/train_rf(...)` | 学習スクリプト互換のモデル学習 |
| `optimize_hyperparams(...)` | Optunaによるハイパーパラメータ最適化 |
| `evaluate(model, X, y)` | 評価（Accuracy, F1, Precision, Recall, ROC-AUC） |
| `export_to_onnx(...)` / `export_onnx(...)` | ONNX形式でエクスポート |
| `save_scaler(scaler, output_dir, model_name)` | スケーラーパラメータ保存 |
| `load_scaler(output_dir, model_name)` | スケーラーパラメータ読み込み |

---

## 15学習スクリプト一覧

### SMCコア系

| # | ファイル | モデル | 目的 | 入力 | 出力 |
|---|---|---|---|---|---|
| 01 | `01_trend_classifier.py` | LightGBM | トレンド方向分類 | 価格+指標 | 3クラス (Bull/Bear/Range) |
| 02 | `02_fvg_fill_predictor.py` | XGBoost | FVG充填確率予測 | FVG特徴量 | 充填確率 (0-1) |
| 03 | `03_ob_quality_scorer.py` | LightGBM | OB品質スコア | OB特徴量 | スコア (0-1) |
| 04 | `04_bos_choch_detector.py` | LSTM | BOS/CHoCH事前検出 | 価格シーケンス | 4クラス (None/BOS+/BOS-/CHoCH) |
| 05 | `05_liquidity_sweep_predictor.py` | XGBoost | 流動性スイープ予測 | 流動性特徴量 | スイープ確率 |

### トレーディング最適化系

| # | ファイル | モデル | 目的 | 入力 | 出力 |
|---|---|---|---|---|---|
| 06 | `06_entry_timing_optimizer.py` | LightGBM | エントリータイミング最適化 | SMC+時間特徴量 | 最適タイミングスコア |
| 07 | `07_volatility_regime.py` | RandomForest | ボラティリティレジーム | ボラ指標 | 4レジーム分類 |
| 08 | `08_session_pattern.py` | LightGBM | セッション別パターン | 時間+価格 | セッション行動分類 |
| 12 | `12_sl_tp_optimizer.py` | XGBoost | SL/TP最適配置 | エントリー条件 | SL/TPレベル |

### マルチTF・分析系

| # | ファイル | モデル | 目的 | 入力 | 出力 |
|---|---|---|---|---|---|
| 09 | `09_mtf_confluence_scorer.py` | XGBoost | マルチTFコンフルエンス | 複数TFの特徴量 | コンフルエンススコア |
| 10 | `10_price_action_classifier.py` | LSTM | プライスアクション分類 | 価格シーケンス | パターンクラス |
| 11 | `11_currency_strength_predictor.py` | LightGBM | 通貨強弱変化予測 | 28ペアの特徴量 | 8通貨の強弱変化 |
| 13 | `13_market_regime_detector.py` | RandomForest | マーケットレジーム検出 | 複合指標 | 4レジーム (Trend/Range/Vol/Break) |
| 14 | `14_swing_reversal_predictor.py` | LSTM | スイング反転予測 | 価格シーケンス | 反転確率 |

### アンサンブル

| # | ファイル | モデル | 目的 | 入力 | 出力 |
|---|---|---|---|---|---|
| 15 | `15_smc_ensemble.py` | Stacking | 全モデル統合 | 他モデル出力 | 最終シグナル (Buy/Sell/Hold) |

---

## 学習の実行方法

### 基本的な実行

```bash
cd Python/

# 単体スクリプト実行
python 01_trend_classifier.py

# 出力される生成物:
#   ../Files/models/...       ← ONNXモデル / スケーラー / 補助ファイル
```

出力先は `common.paths.default_model_dir()` で解決されるため、スクリプトをどのディレクトリから実行してもリポジトリ配下の `Files/models/` に保存されます。

### 軽量検証

学習処理やMT5接続を行わず、共通モジュールの構文・lint・単体テストだけを確認できます。

```bash
cd ..
pip install numpy pandas scikit-learn ruff
python tools/check_python.py
python tools/check_mql5_static.py
```

### 全モデルの一括学習

```bash
# 01〜14を順番に実行
for i in $(seq -f "%02g" 1 14); do
    python ${i}_*.py
done

# 最後にアンサンブル（他モデルの出力を入力にする）
python 15_smc_ensemble.py
```

### データソースの切り替え

各スクリプト内で設定可能：

```python
CONFIG = {
    'symbol': 'EURUSD',
    'timeframe': 'H1',
    'bars': 50000,
    'data_source': 'mt5',     # 'mt5' or 'csv'
    'csv_path': 'data/EURUSD_H1.csv',  # CSV使用時
}
```

### Optuna最適化の使用

```python
CONFIG = {
    'optimize': True,           # Optuna最適化を有効化
    'n_trials': 100,            # 試行回数
}
```

---

## ONNXモデルのMQL5での使用

### 1. モデルファイルの配置

```
MQL5/
├── Files/
│   └── models/
│       ├── trend_classifier.onnx
│       ├── trend_classifier_mean.npy
│       └── trend_classifier_scale.npy
```

### 2. MQL5でのモデル読み込みと推論

```cpp
#include <SMC/Utils/OnnxWrapper.mqh>

CSmcOnnxWrapper onnx;

int OnInit()
{
   // モデル読み込み
   if(!onnx.LoadFromFile("models\\trend_classifier.onnx"))
      return INIT_FAILED;

   // 入出力形状設定
   onnx.SetInputShape(30);     // 特徴量数
   onnx.SetOutputShape(3);     // 出力クラス数

   // スケーラー読み込み
   onnx.LoadScaler("models\\trend_classifier_mean.npy",
                    "models\\trend_classifier_scale.npy");

   return INIT_SUCCEEDED;
}

void OnTick()
{
   // 特徴量を準備
   float features[];
   ArrayResize(features, 30);
   // ... features[] に値を設定 ...

   // スケーラー適用
   onnx.ApplyScaler(features);

   // 予測
   int classIdx = onnx.PredictClass(features);
   // classIdx: 0=Bearish, 1=Ranging, 2=Bullish

   // 信頼度付き予測
   float output[];
   ArrayResize(output, 3);
   if(onnx.Predict(features, output))
   {
      double confidence = onnx.GetConfidence(output);
      Print("Prediction: ", classIdx, " Confidence: ", confidence);
   }
}

void OnDeinit(const int reason)
{
   onnx.Release();
}
```

### 3. DataExporterとの連携

MQL5側でCSVデータをエクスポートし、Pythonで学習：

```cpp
// MQL5: Scripts/SMC_DataExport.mq5
#include <SMC/Utils/DataExporter.mqh>
#include <SMC/SmcManager.mqh>

CSmcManager *smc;

void OnStart()
{
   smc = new CSmcManager();
   smc.Init(_Symbol, _Period, false, false, false);

   // SMC特徴量付きデータをエクスポート
   CSmcDataExporter::ExportSmcFeatures(
      _Symbol, _Period, 50000,
      _Symbol + "_features.csv", smc);

   smc.Clean();
   delete smc;
}
```

---

## カスタムモデルの作成

### テンプレート

```python
"""
カスタムモデルテンプレート
"""
import sys
sys.path.append('.')
from common import DataLoader, FeatureEngineer, ModelTrainer, default_model_dir

# 設定
CONFIG = {
    'name': 'my_custom_model',
    'symbol': 'EURUSD',
    'timeframe': 'H1',
    'bars': 50000,
    'model_type': 'lightgbm',   # lightgbm, xgboost, random_forest, lstm
    'optimize': True,
    'n_trials': 50,
}

def create_features(df):
    """カスタム特徴量を作成"""
    fe = FeatureEngineer()
    df = fe.add_returns(df)
    df = fe.add_volatility(df)
    # ... 必要な特徴量を追加 ...
    return df

def create_labels(df):
    """カスタムラベルを作成"""
    # 例: 10バー後のリターンで3クラス分類
    df['future_return'] = df['close'].shift(-10) / df['close'] - 1
    df['label'] = 1  # Ranging
    df.loc[df['future_return'] > 0.001, 'label'] = 2  # Bullish
    df.loc[df['future_return'] < -0.001, 'label'] = 0  # Bearish
    return df

def main():
    # データ取得
    loader = DataLoader(CONFIG['symbol'], CONFIG['timeframe'])
    df = loader.load(CONFIG['bars'])

    # 特徴量・ラベル作成
    df = create_features(df)
    df = create_labels(df)
    df = df.dropna()

    # 分割
    train, val, test = loader.train_val_test_split(df, 0.7, 0.15)

    # 学習
    trainer = ModelTrainer(task='multiclass', num_class=3)
    feature_cols = [c for c in df.columns if c not in ['label', 'future_return', 'time']]

    if CONFIG['optimize']:
        best_params = trainer.optimize_lgbm(
            train[feature_cols], train['label'], CONFIG['n_trials'])
        model = trainer.train_lgbm(
            train[feature_cols], train['label'], best_params)
    else:
        model = trainer.train_lgbm(train[feature_cols], train['label'])

    # 評価
    metrics = trainer.evaluate(model, test[feature_cols], test['label'])
    print(f"Test Metrics: {metrics}")

    # ONNXエクスポート
    output_path = default_model_dir() / CONFIG['name']
    trainer.export_onnx(model, feature_cols, output_path)

if __name__ == '__main__':
    main()
```

### モデル選択ガイド

| ユースケース | 推奨モデル | 理由 |
|---|---|---|
| テーブルデータ分類 | LightGBM | 高速・高精度、欠損値耐性 |
| 非線形回帰 | XGBoost | 堅牢、過学習制御が容易 |
| 時系列パターン | LSTM | 時間依存性を捉える |
| ベースライン・比較用 | RandomForest | シンプル・解釈しやすい |
| 最終アンサンブル | Stacking | 複数モデルの長所を統合 |
