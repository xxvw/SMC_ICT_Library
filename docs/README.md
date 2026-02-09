# SMC/ICT Library for MQL5 - 完全ドキュメント

**Smart Money Concepts (SMC) / Inner Circle Trader (ICT) のMQL5実装ライブラリ**

> このドキュメントを読めば、ライブラリの全機能を理解し、即座に使い始めることができます。

---

## ドキュメント一覧

| ドキュメント | 内容 | 対象読者 |
|---|---|---|
| **[GETTING_STARTED.md](GETTING_STARTED.md)** | インストール・環境構築・クイックスタート | 初めて使う方 |
| **[SMC_CONCEPTS.md](SMC_CONCEPTS.md)** | SMC/ICT各コンセプトの解説と本ライブラリでの実装方法 | SMC/ICTを学びたい方 |
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | アーキテクチャ・設計思想・モジュール依存関係 | 開発者・コントリビューター |
| **[API_REFERENCE.md](API_REFERENCE.md)** | 全クラス・全メソッドの完全APIリファレンス | 実装時の参照用 |
| **[EXAMPLES.md](EXAMPLES.md)** | 実践的なコード例集（単体使用・統合使用・EA・インジケーター） | 実装したい方 |
| **[PYTHON_ML.md](PYTHON_ML.md)** | Python機械学習パイプラインの使い方・15スクリプト解説 | ML連携したい方 |
| **[FAQ.md](FAQ.md)** | よくある質問・トラブルシューティング・Tips | 困った時に |

---

## プロジェクト概要

### ライブラリ構成

```
SMC_ICT_Library/
├── Include/SMC/                  # MQL5 Include ライブラリ
│   ├── Core/                     #   基盤クラス
│   │   ├── SmcTypes.mqh          #     列挙型・構造体定義
│   │   ├── SmcBase.mqh           #     基底クラス（全モジュール共通）
│   │   └── SmcDrawing.mqh        #     チャート描画ユーティリティ
│   ├── SwingPoints.mqh           #   スイングポイント検出
│   ├── MarketStructure.mqh       #   BOS / CHoCH / トレンド・レンジ分析
│   ├── OrderBlock.mqh            #   オーダーブロック検出・管理
│   ├── FairValueGap.mqh          #   FVG（インバランス）検出
│   ├── Liquidity.mqh             #   流動性分析（EQH/EQL・プール・スイープ）
│   ├── PremiumDiscount.mqh       #   Premium / Discount ゾーン
│   ├── OptimalTradeEntry.mqh     #   OTE（フィボナッチ 0.618-0.786）
│   ├── KillZone.mqh              #   ICT Kill Zones（セッション時間フィルター）
│   ├── BreakerBlock.mqh          #   Breaker Block / Mitigation Block
│   ├── ConfluenceDetector.mqh    #   コンフルエンス判定
│   ├── SmcManager.mqh            #   全モジュール統合マネージャー
│   ├── Analysis/                 #   分析モジュール
│   │   ├── CurrencyStrength.mqh  #     8通貨相対強弱分析
│   │   └── VIXCalculator.mqh     #     ボラティリティ指数計算
│   └── Utils/                    #   ユーティリティ
│       ├── TradeUtils.mqh        #     ロット計算・スプレッド判定
│       ├── TimeUtils.mqh         #     GMT変換・新バー検出
│       ├── MathUtils.mqh         #     統計関数（StdDev, Zスコア等）
│       ├── ArrayUtils.mqh        #     配列操作テンプレート関数
│       ├── Logger.mqh            #     レベル付きロギング
│       ├── DataExporter.mqh      #     ML用CSVエクスポート
│       └── OnnxWrapper.mqh       #     ONNX推論ラッパー
├── Indicators/
│   └── SMC_Visualizer.mq5        # 全SMCコンセプト可視化インジケーター
├── Experts/
│   └── SMC_Sample_EA.mq5         # サンプルEA（コンフルエンス売買）
├── Scripts/
│   └── SMC_DataExport.mq5        # ML学習用データエクスポートスクリプト
├── Python/                       # Python ML学習パイプライン
│   ├── common/                   #   共通モジュール
│   │   ├── data_loader.py        #     データ取得・分割
│   │   ├── feature_base.py       #     特徴量エンジニアリング
│   │   └── model_utils.py        #     モデル学習・ONNX変換
│   ├── 01〜15_*.py               #   15種類の学習スクリプト
│   └── requirements.txt          #   Python依存関係
├── docs/                         # ドキュメント（このフォルダ）
├── LICENSE                       # MITライセンス
├── .gitignore
└── README.md                     # プロジェクトトップREADME
```

### 対応銘柄・タイムフレーム

- **銘柄**: FX全通貨ペア、ゴールド（XAUUSD）、株式指数、暗号通貨等
- **タイムフレーム**: M1〜MN1（全タイムフレーム対応）
- **Pip自動検出**: 3桁/5桁ブローカー対応

### 主な特徴

1. **モジュラー設計** - 各コンセプトを単独でも統合でも使用可能
2. **統一API** - 全モジュールが `Init()` / `Update()` / `Clean()` 共通インターフェース
3. **描画ON/OFF** - `enableDraw` フラグで可視化を切り替え
4. **リソース共有** - SmcManager は SwingPoints を全モジュールで共有し効率化
5. **ML連携** - CSVエクスポート → Python学習 → ONNXモデル推論のフルパイプライン

---

## クイックリンク

| やりたいこと | 参照先 |
|---|---|
| とにかくすぐ使いたい | [GETTING_STARTED.md](GETTING_STARTED.md) |
| FVGだけ使いたい | [EXAMPLES.md#単体モジュール使用](EXAMPLES.md#単体モジュール使用) |
| 全機能統合して使いたい | [EXAMPLES.md#SmcManager統合使用](EXAMPLES.md#smcmanager統合使用) |
| EAを作りたい | [EXAMPLES.md#EA開発パターン](EXAMPLES.md#ea開発パターン) |
| 機械学習モデルを作りたい | [PYTHON_ML.md](PYTHON_ML.md) |
| 全メソッドを知りたい | [API_REFERENCE.md](API_REFERENCE.md) |
| SMC/ICTの概念自体を理解したい | [SMC_CONCEPTS.md](SMC_CONCEPTS.md) |
| コンパイルエラーが出た | [FAQ.md#トラブルシューティング](FAQ.md#トラブルシューティング) |

---

## ライセンス

MIT License - 商用利用可、改変自由、著作権表記のみ必要

## 免責事項

このライブラリは教育・研究目的で提供されています。実際のトレードでの使用は自己責任で行ってください。過去のパフォーマンスは将来の結果を保証するものではありません。
