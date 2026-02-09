# FAQ / よくある質問・トラブルシューティング

## 目次

1. [インストール・セットアップ](#インストールセットアップ)
2. [コンパイルエラー](#コンパイルエラー)
3. [実行時の問題](#実行時の問題)
4. [パフォーマンス](#パフォーマンス)
5. [SMCモジュール関連](#smcモジュール関連)
6. [通貨強弱・VIX関連](#通貨強弱vix関連)
7. [ONNX・機械学習関連](#onnx機械学習関連)
8. [Python ML関連](#python-ml関連)
9. [Tips・ベストプラクティス](#tipsベストプラクティス)

---

## インストール・セットアップ

### Q: どのフォルダにファイルを置けばいい？

**A**: MetaTrader 5のデータフォルダの中です。

```
MT5データフォルダ/MQL5/
├── Include/SMC/        ← Include/SMC/ フォルダ全体をここに
├── Indicators/         ← SMC_Visualizer.mq5 をここに
├── Experts/            ← SMC_Sample_EA.mq5 をここに
└── Scripts/            ← SMC_DataExport.mq5 をここに
```

データフォルダは MetaTrader 5 → `ファイル` → `データフォルダを開く` で確認できます。

### Q: MetaTrader 5のデータフォルダはどこ？

**A**: OSとインストール方法により異なります：

- **Windows**: `C:\Users\<ユーザー名>\AppData\Roaming\MetaQuotes\Terminal\<ハッシュ>\MQL5\`
- **ポータブル版**: MT5インストールフォルダ内の `MQL5\`

### Q: Python環境は必須？

**A**: いいえ。MQL5ライブラリ単体で使用する場合はPythonは不要です。Python環境が必要になるのは、ML学習スクリプトを使ってONNXモデルを作成する場合のみです。

---

## コンパイルエラー

### Q: `'SmcTypes.mqh' - cannot open include file` と出る

**A**: `Include/SMC/` フォルダが正しい場所にありません。

**確認項目:**
1. `MQL5/Include/SMC/Core/SmcTypes.mqh` が存在するか
2. `#include <SMC/SmcManager.mqh>` のように `<>` でインクルードしているか（`""` ではなく）
3. MetaEditorの `ツール` → `オプション` でインクルードパスを確認

### Q: `'CTrade' - identifier not found` と出る

**A**: `<Trade/Trade.mqh>` のインクルードが不足しています。サンプルEAでは MQL5標準ライブラリの `CTrade` クラスを使用しています。

```cpp
#include <Trade/Trade.mqh>     // ← これを追加
#include <SMC/SmcManager.mqh>
```

### Q: `'OnnxCreate' - function not defined` と出る

**A**: MT5のビルドバージョンが古い可能性があります。ONNX機能は **Build 3600以上** が必要です。MetaTrader 5を最新バージョンに更新してください。

### Q: テンプレート関数のエラーが出る

**A**: MQL5のテンプレートにはいくつかの制限があります。`ArrayUtils.mqh` のテンプレート関数は基本型（int, double, string等）と本ライブラリの構造体で動作確認済みです。カスタム型で使う場合は、型に適したオーバーロードが必要になる場合があります。

---

## 実行時の問題

### Q: `[SMC] Error: Invalid symbol` と表示される

**A**: 初期化時にシンボル情報が取得できていません。以下を確認：

1. シンボル名のスペルが正しいか
2. そのシンボルがブローカーで利用可能か
3. マーケットウォッチに追加されているか

```cpp
// 正しい例
smc.Init(_Symbol, _Period, true);         // 現在のチャートシンボル
smc.Init("EURUSD", PERIOD_H1, true);     // 明示指定

// "" や "0" は自動的に _Symbol に置換される
smc.Init("", PERIOD_CURRENT, true);
```

### Q: `Failed to create ATR indicator` と警告が出る

**A**: ATRインジケーターの作成に失敗しています。通常は一時的な問題です。ATR取得失敗時は自動的に手動計算（`GetAverageRange()`）にフォールバックするため、動作には影響しません。

### Q: チャートに何も描画されない

**A**: 以下を確認：

1. `Init()` の `enableDraw` パラメータが `true` になっているか
2. `Update()` が呼ばれているか
3. チャートプロパティで「チャートの前面にオブジェクトを表示」が有効か
4. 十分なバー数が存在するか（少なくとも `swingPeriod * 2` + α）

### Q: スイングポイントが少ない/多い

**A**: `swingPeriod` パラメータを調整してください。

| swingPeriod | 結果 |
|---|---|
| 小さい（2-3） | 多くのスイング検出、ノイズも多い |
| 標準（5） | バランスの良い検出 |
| 大きい（10-20） | 少数の重要なスイングのみ |

```cpp
smc.Swing()->SetSwingPeriod(3);   // 敏感に
smc.Swing()->SetSwingPeriod(10);  // 鈍感に
```

---

## パフォーマンス

### Q: OnTick()で毎ティック更新するのは重くない？

**A**: 基本的には**新バー時のみ更新**することを推奨します。

```cpp
void OnTick()
{
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, _Period, 0);
   if(currentBar == lastBar) return;  // 新バーでなければスキップ
   lastBar = currentBar;

   smc.Update();  // 新バー時のみ更新
}
```

### Q: バックテストが遅い

**A**: パフォーマンスを改善する方法：

1. **描画を無効化**: `Init(..., false)` で描画OFF
2. **不要なモジュールを無効化**: 通貨強弱・VIXが不要なら `Init(..., false, false, false)`
3. **新バー時のみ更新**: 上記のコード参照
4. **ルックバック範囲を縮小**: `swingPeriod` や `lookbackBars` を小さくする

### Q: メモリ使用量が多い

**A**: 各モジュールの最大保持数を調整してください。

```cpp
// SwingPointsの最大保持数を減らす
smc.Swing()->Init(_Symbol, _Period, false, 5, 20, 200);
//                                          ^   ^    ^
//                                     period maxPts lookback
```

---

## SMCモジュール関連

### Q: OBが検出されない

**A**: インパルスムーブの閾値が厳しすぎる可能性があります。

```cpp
ob.SetMinStrength(1.2);  // デフォルト1.5より緩和
```

また、ルックバック範囲内に条件を満たすパターンがない場合もあります。タイムフレームを変更して試してください。

### Q: FVGが多すぎる

**A**: 最小サイズフィルターを大きくしてください。

```cpp
fvg.SetMinSizePips(5.0);  // デフォルト2.0から拡大
fvg.SetMaxAge(100);        // 古いFVGを早く消す
```

### Q: コンフルエンスシグナルが出ない

**A**: 条件が厳しすぎる可能性があります。

```cpp
smc.Confluence()->SetMinConfluence(2);  // 3→2に緩和
smc.Confluence()->SetMinScore(0.3);     // 0.5→0.3に緩和
```

### Q: 単体モジュールとSmcManagerの違いは？

**A**: 
- **単体モジュール**: 必要な機能だけ使いたい場合。軽量。
- **SmcManager**: 全機能統合。SwingPointsを共有し効率的。コンフルエンス判定が可能。

単体でもSwingPointsの共有は手動で可能：

```cpp
CSmcSwingPoints *swing = new CSmcSwingPoints();
swing.Init(_Symbol, _Period, false);

CSmcMarketStructure ms;
ms.Init(_Symbol, _Period, false, swing);  // 共有

CSmcLiquidity liq;
liq.Init(_Symbol, _Period, false, swing);  // 同じswingを共有
```

---

## 通貨強弱・VIX関連

### Q: 通貨強弱で一部のペアが `N/A`

**A**: ブローカーでそのペアが利用できないか、シンボル名が異なる可能性があります。`FindBrokerSymbol()` は一般的なサフィックス（`.ecn`, `.pro` 等）を自動試行しますが、特殊な命名規則のブローカーでは取得できない場合があります。

### Q: VIX値が異常に高い/低い

**A**: 計算タイムフレームと期間を確認してください。

```cpp
// デフォルト: D1の20バーで計算
vix.Init(_Symbol, _Period, false, 20, PERIOD_D1);

// 閾値を銘柄に合わせて調整
vix.SetThresholds(10.0, 20.0, 30.0);  // ゴールド等のボラタイル銘柄向け
```

---

## ONNX・機械学習関連

### Q: ONNXモデルの読み込みに失敗する

**A**: 確認事項：

1. モデルファイルが `MQL5/Files/` ディレクトリ内にあるか
2. MT5のBuildが3600以上か
3. モデルのONNX opset versionが対応範囲内か
4. `SetInputShape()` / `SetOutputShape()` が正しいか

### Q: 推論結果がおかしい

**A**: 最も多い原因は**スケーリングの不一致**です。

1. 学習時と同じスケーラー（mean/scale）を使っているか
2. 特徴量の順番が学習時と同じか
3. 特徴量にNaN/Infが含まれていないか

```cpp
// 推論前にバリデーション
float features[];
// ... features を設定 ...
if(!onnx.ApplyScaler(features))
   Print("Scaler application failed!");
```

---

## Python ML関連

### Q: MetaTrader5パッケージがインストールできない

**A**: MetaTrader5 Pythonパッケージは **Windows のみ** 対応です。Mac/Linux では CSV経由でデータを準備してください。

```bash
# Windows
pip install MetaTrader5

# Mac/Linux → MQL5でCSVエクスポート後、CSVからロード
loader.load_from_csv("path/to/exported_data.csv")
```

### Q: Optuna最適化が遅い

**A**: 試行回数を減らすか、タイムアウトを設定してください。

```python
CONFIG = {
    'optimize': True,
    'n_trials': 30,    # 100→30に削減
}
```

### Q: TensorFlow/LSTMモデルのONNXエクスポートに失敗する

**A**: `tf2onnx` のバージョンを確認してください。TensorFlowのバージョンとの互換性が重要です。

```bash
pip install --upgrade tf2onnx tensorflow
```

---

## Tips・ベストプラクティス

### 1. 新バー時のみ更新する

毎ティック更新は不要です。SMCコンセプトはバーベースです。

### 2. 描画はデバッグ時のみ有効にする

バックテストや本番では `enableDraw = false` でパフォーマンスを向上。

### 3. フィルターを段階的に適用する

計算コストの低いフィルターから順に適用：

```
1. IsNewBar()        ← ほぼゼロコスト
2. IsSpreadOK()      ← 低コスト
3. IsInKillZone()    ← 低コスト
4. smc.Update()      ← メインの計算
5. GetSignal()       ← コンフルエンス判定
```

### 4. SwingPeriodは銘柄・TFに合わせて調整

- 短期TF（M1-M15）: swingPeriod = 3-5
- 中期TF（M30-H4）: swingPeriod = 5-10
- 長期TF（D1-W1）: swingPeriod = 5-20

### 5. ログはデバッグ時のみ詳細に

本番では `LOG_WARN` 以上に設定してログ出力を抑制。

```cpp
#ifdef _DEBUG
   CSmcLogger::SetLevel(LOG_DEBUG);
#else
   CSmcLogger::SetLevel(LOG_WARN);
#endif
```

### 6. ML予測とSMCシグナルの併用

ML予測だけでなく、SMCシグナルと一致する場合のみエントリーすることで、シグナルの信頼性が向上します。

### 7. メモリリークに注意

`new` で作成したオブジェクトは必ず `delete` で解放。`OnDeinit()` での解放を忘れずに。

```cpp
void OnDeinit(const int reason)
{
   if(smc != NULL)
   {
      smc.Clean();   // チャートオブジェクト削除
      delete smc;    // メモリ解放
      smc = NULL;
   }
}
```

### 8. 複数タイムフレームの活用

上位TFでトレンド確認、下位TFでエントリーの「マルチTF分析」が有効です。

```cpp
CSmcManager *smcH4, *smcM15;

// H4でトレンド確認
smcH4 = new CSmcManager();
smcH4.Init(_Symbol, PERIOD_H4, false, false, false);

// M15でエントリー
smcM15 = new CSmcManager();
smcM15.Init(_Symbol, PERIOD_M15, true, false, false);

void OnTick()
{
   smcH4.Update();
   smcM15.Update();

   // H4がBullish && M15がBuyシグナル → 強い買いシグナル
   if(smcH4.IsBullish() && smcM15.GetSignal() == SIGNAL_BUY)
      Print("Multi-TF Confluence BUY!");
}
```
