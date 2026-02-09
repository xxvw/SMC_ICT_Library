# アーキテクチャ・設計思想

## 目次

1. [設計原則](#設計原則)
2. [モジュール依存関係図](#モジュール依存関係図)
3. [クラス階層](#クラス階層)
4. [データフロー](#データフロー)
5. [型定義システム（SmcTypes）](#型定義システムsmctypes)
6. [基底クラス（CSmcBase）](#基底クラスcsmcbase)
7. [描画システム（CSmcDrawing）](#描画システムcsmcdrawing)
8. [マネージャーパターン（CSmcManager）](#マネージャーパターンcsmcmanager)
9. [リソース共有戦略](#リソース共有戦略)
10. [ユーティリティ設計](#ユーティリティ設計)
11. [MQL5コーディング規約](#mql5コーディング規約)

---

## 設計原則

### 1. Symbol-agnostic（銘柄非依存）

全モジュールは `Init()` でシンボルを受け取り、`iHigh()`, `iLow()` 等の汎用関数でデータにアクセスします。FX、ゴールド、指数等の銘柄タイプに依存しません。Pipサイズは `DetectPipSize()` で自動検出されます。

### 2. Timeframe-agnostic（タイムフレーム非依存）

M1〜MN1のいずれでも動作します。タイムフレーム依存のパラメータ（ルックバック期間等）はコンストラクタのデフォルト値として設定可能です。

### 3. Modular（モジュラー）

各SMCコンセプトは独立したクラスとして実装。単体使用も統合使用も可能です。

```
単体使用:    CSmcFairValueGap fvg;  fvg.Init(...);  fvg.Update();
統合使用:    CSmcManager mgr;       mgr.Init(...);  mgr.Update();
```

### 4. Unified API（統一API）

全モジュールが以下の3メソッドを共通インターフェースとして提供：

| メソッド | 役割 |
|---|---|
| `Init(symbol, timeframe, enableDraw, ...)` | 初期化。シンボル情報取得、ATR作成、描画設定 |
| `Update()` | 毎ティック/バーの更新処理 |
| `Clean()` | チャートオブジェクト削除、リソース解放 |

### 5. Optional Drawing（描画オプショナル）

`enableDraw` パラメータにより、チャートへの描画ON/OFFを制御。バックテスト時やバックグラウンド計算時は `false` で高速動作。

### 6. Resource Sharing（リソース共有）

`CSmcManager` は `CSmcSwingPoints` のインスタンスを1つ作成し、全依存モジュール（MarketStructure, Liquidity, PremiumDiscount, OTE）で共有。不必要な重複計算を排除。

---

## モジュール依存関係図

```
                    SmcTypes (列挙型・構造体)
                         │
                    SmcBase (基底クラス)
                         │
                    SmcDrawing (描画ユーティリティ)
                         │
              ┌──────────┼──────────┐
              │          │          │
         SwingPoints   FairValueGap  KillZone
         (基盤)       (独立)        (独立)
              │
    ┌─────────┼─────────────────┐
    │         │                 │
MarketStructure  Liquidity  PremiumDiscount  OptimalTradeEntry
    │
OrderBlock
    │
BreakerBlock
    │
    └──────────────── ConfluenceDetector ←── 全モジュール参照
                              │
                        SmcManager ←── 全モジュール統括

[独立ユーティリティ]
TradeUtils | TimeUtils | MathUtils | ArrayUtils | Logger | DataExporter | OnnxWrapper

[分析モジュール]
CurrencyStrength | VIXCalculator
```

### 依存関係の方向

| モジュール | 依存先 |
|---|---|
| SwingPoints | なし（基底のみ） |
| MarketStructure | SwingPoints |
| OrderBlock | MarketStructure (→ SwingPoints) |
| FairValueGap | なし（独立） |
| Liquidity | SwingPoints |
| PremiumDiscount | SwingPoints |
| OptimalTradeEntry | SwingPoints |
| KillZone | なし（独立） |
| BreakerBlock | OrderBlock + MarketStructure |
| ConfluenceDetector | 全SMCモジュール参照（Set〇〇で注入） |
| CurrencyStrength | なし（独立） |
| VIXCalculator | なし（独立） |

---

## クラス階層

```
CSmcBase (基底クラス)
├── CSmcSwingPoints
├── CSmcMarketStructure
├── CSmcOrderBlock
├── CSmcFairValueGap
├── CSmcLiquidity
├── CSmcPremiumDiscount
├── CSmcOptimalTradeEntry
├── CSmcKillZone
├── CSmcBreakerBlock
├── CSmcConfluence
├── CSmcCurrencyStrength
└── CSmcVIXCalculator

CSmcDrawing          ← static ユーティリティクラス（継承なし）
CSmcTradeUtils       ← static ユーティリティクラス
CSmcTimeUtils        ← static ユーティリティクラス
CSmcMathUtils        ← static ユーティリティクラス
CSmcLogger           ← static シングルトン型クラス
CSmcDataExporter     ← static ユーティリティクラス
CSmcOnnxWrapper      ← インスタンスクラス（ONNX推論用）
CSmcManager          ← オーケストレーションクラス

// テンプレート関数（クラス外）
SmcArrayPush<T>(), SmcArrayPop<T>(), SmcArrayRemoveAt<T>(), ...
```

---

## データフロー

### 毎バー更新フロー（CSmcManager::Update()）

```
1. SwingPoints.Update()
   └── DetectSwingPoints()      ← 500バーのスイングH/L検出
   └── UpdateBreakStatus()      ← 現在価格によるブレイク判定

2. MarketStructure.Update()
   └── DetectTrend()            ← HH/HL, LH/LL パターン判定
   └── DetectStructureBreaks()  ← BOS/CHoCH 検出
   └── DetectRange()            ← レンジ判定

3. OrderBlock.Update()
   └── DetectOrderBlocks()      ← 逆方向キャンドル + インパルスムーブ
   └── UpdateStates()           ← FRESH → TESTED → BROKEN

4. FairValueGap.Update()
   └── DetectFVGs()             ← 3本ローソク足パターン
   └── UpdateStates()           ← 価格接触による状態遷移

5. Liquidity.Update()
   └── DetectEqualHighsLows()   ← 許容範囲内の同値H/L
   └── DetectLiquidityPools()   ← 3回以上タッチ
   └── DetectSweeps()           ← レベル超え→反転パターン

6. PremiumDiscount.Update()
   └── Calculate()              ← スイングH/Lの50%基準

7. OptimalTradeEntry.Update()
   └── Calculate()              ← フィボナッチ 0.618-0.786

8. KillZone.Update()
   └── UpdateCurrentSession()   ← GMT時刻→セッション判定
   └── UpdateSessionHL()        ← セッション中の高安値追跡

9. BreakerBlock.Update()
   └── DetectBreakerBlocks()    ← 失敗したOBを検出
   └── DetectMitigationBlocks() ← 部分消費されたOBを検出

10. Confluence.Update()
    └── DetectBuyZone()         ← 全要素をスコアリング
    └── DetectSellZone()        ← 全要素をスコアリング

11. CurrencyStrength.Update()   ← 28ペアの相対強弱計算

12. VIXCalculator.Update()      ← ヒストリカルボラティリティ計算
```

---

## 型定義システム（SmcTypes）

### 列挙型

| 列挙型 | 用途 | 値 |
|---|---|---|
| `ENUM_SMC_TREND` | トレンド方向 | BULLISH(1), BEARISH(-1), RANGING(0) |
| `ENUM_ZONE_STATE` | ゾーン状態 | FRESH(0), TESTED(1), MITIGATED(2), BROKEN(3) |
| `ENUM_STRUCTURE_TYPE` | 構造ブレイク種別 | NONE(0), BOS(1), CHOCH(2) |
| `ENUM_SMC_SESSION` | セッション | NONE, ASIAN, LONDON, NEWYORK, LDN_NY_OL |
| `ENUM_ZONE_PROBABILITY` | ゾーン確率 | HIGH(2), MEDIUM(1), LOW(0) |
| `ENUM_FVG_PROBABILITY` | FVG確率 | HIGH_PROB(2), LOW_PROB(1), BREAKAWAY(0) |
| `ENUM_LIQUIDITY_TYPE` | 流動性タイプ | EQUAL_HIGHS, EQUAL_LOWS, POOL_HIGH/LOW, SWEEP_HIGH/LOW |
| `ENUM_VIX_LEVEL` | VIXレベル | LOW, NORMAL, HIGH, EXTREME |
| `ENUM_CS_METHOD` | 通貨強弱計算方法 | RATE_CHANGE, RSI, STOCHASTIC |
| `ENUM_LOG_LEVEL` | ログレベル | DEBUG, INFO, WARN, ERROR |
| `ENUM_ENTRY_SIGNAL` | エントリーシグナル | BUY(1), SELL(-1), WAIT(0) |

### 構造体

| 構造体 | 用途 | 主要フィールド |
|---|---|---|
| `SmcSwingPoint` | スイングポイント | price, time, barIndex, isHigh, strength, isBroken |
| `SmcZone` | ゾーン（OB/FVG/Breaker共通） | topPrice, bottomPrice, state, probability, score, isBullish |
| `SmcStructureBreak` | BOS/CHoCH | type, breakPrice, swingPrice, isBullish |
| `SmcLiquidityLevel` | 流動性レベル | price, touchCount, isSweep, type |
| `SmcConfluenceZone` | コンフルエンスゾーン | totalScore, factorCount, factors[] |
| `SmcRangeInfo` | レンジ情報 | highPrice, lowPrice, duration, isBroken |
| `SmcCurrencyInfo` | 通貨強弱情報 | name, strength, momentum, rank |
| `SmcOTEZone` | OTEゾーン | fibLevel618/705/786, swingHigh/Low |
| `SmcSessionInfo` | セッション情報 | session, startHourGMT, endHourGMT, sessionHigh/Low |

全構造体に `Init()` メソッドがあり、ゼロ初期化を保証します。

---

## 基底クラス（CSmcBase）

全モジュールが継承する基底クラス。以下の共通機能を提供：

### Protected メンバ

```
m_symbol        : string         - 対象シンボル
m_timeframe     : ENUM_TIMEFRAMES - 対象タイムフレーム
m_point         : double         - 1ポイントの価格
m_digits        : int            - 価格桁数
m_pipSize       : double         - 1Pipの価格サイズ
m_pipDigits     : int            - Pip桁数
m_enableDraw    : bool           - 描画有効フラグ
m_prefix        : string         - チャートオブジェクト接頭辞
m_atrHandle     : int            - ATRインジケーターハンドル
m_initialized   : bool           - 初期化完了フラグ
```

### Pip自動検出ロジック

```
5桁/3桁: pipSize = point × 10    (例: 0.00001 → 0.0001)
4桁/2桁: pipSize = point          (例: 0.0001 → 0.0001)
その他:   pipSize = point × 10    (ゴールド・指数用)
```

---

## 描画システム（CSmcDrawing）

全staticメソッドの描画ユーティリティクラス。モジュールからの描画呼び出しを統一。

### 描画メソッド一覧

| メソッド | 用途 |
|---|---|
| `DrawZone()` | 矩形ゾーン（OB, FVG等） |
| `ExtendZone()` | 既存ゾーンの右端を延長 |
| `DrawHLine()` | 水平線（流動性レベル等） |
| `DrawTrendLine()` | トレンドライン（BOS/CHoCH等） |
| `DrawArrow()` | 矢印マーカー（スイングポイント等） |
| `DrawText()` | テキストラベル |
| `DrawLabel()` | 固定位置ラベル（ダッシュボード等） |
| `DrawPanel()` | 背景パネル |
| `DeleteObject()` | 単体削除 |
| `DeleteObjectsByPrefix()` | 接頭辞一致で一括削除 |
| `Redraw()` | `ChartRedraw(0)` 呼び出し |

### オブジェクト命名規則

各モジュールは固有の接頭辞を使用し、Clean時にプレフィックスで一括削除：

```
SMC_SW_    : SwingPoints
SMC_STR_   : MarketStructure
SMC_OB_    : OrderBlock
SMC_FVG_   : FairValueGap
SMC_LIQ_   : Liquidity
SMC_PD_    : PremiumDiscount
SMC_OTE_   : OptimalTradeEntry
SMC_KZ_    : KillZone
SMC_BRK_   : BreakerBlock
SMC_CONF_  : ConfluenceDetector
SMC_CS_    : CurrencyStrength
SMC_VIX_   : VIXCalculator
```

---

## マネージャーパターン（CSmcManager）

### 設計思想

`CSmcManager` は **Mediator パターン** を採用。各モジュールは互いを直接参照せず、マネージャー経由で依存を解決します。

### 初期化順序

```
1. SwingPoints       ← 基盤モジュール（全モジュールが依存）
2. MarketStructure   ← SwingPoints 共有受け取り
3. OrderBlock        ← MarketStructure 共有受け取り
4. FairValueGap      ← 独立（依存なし）
5. Liquidity         ← SwingPoints 共有受け取り
6. PremiumDiscount   ← SwingPoints 共有受け取り
7. OptimalTradeEntry ← SwingPoints 共有受け取り
8. KillZone          ← 独立（依存なし）
9. BreakerBlock      ← OB + Structure 共有受け取り
10. Confluence       ← 全モジュールをSet〇〇()で注入
11. CurrencyStrength ← オプション（フラグで制御）
12. VIXCalculator    ← オプション（フラグで制御）
```

### メモリ管理

- マネージャーは全モジュールを `new` で作成
- デストラクタで逆順に `delete`
- 共有されたSwingPointsは作成元（マネージャー）のみが解放

---

## リソース共有戦略

### 問題

MarketStructure, Liquidity, PremiumDiscount, OTE の4モジュールは全てSwingPointsに依存。各モジュールが独自にSwingPointsを作成すると、同じ計算が4回実行される。

### 解決策

各モジュールのInitは `CSmcSwingPoints *swingPoints = NULL` パラメータを持つ。

- **NULLの場合**: 自前のSwingPointsを `new` で作成（`m_ownSwing = true`）
- **NULLでない場合**: 受け取ったポインタを使用（`m_ownSwing = false`）

```cpp
// SmcManager内部
m_swing = new CSmcSwingPoints();
m_swing.Init(symbol, tf, draw);

m_structure = new CSmcMarketStructure();
m_structure.Init(symbol, tf, draw, m_swing);  // 共有

m_liquidity = new CSmcLiquidity();
m_liquidity.Init(symbol, tf, draw, m_swing);  // 共有
```

- 単体使用時は自動的に内部SwingPointsを作成
- マネージャー使用時は1つのSwingPointsを全モジュールで共有

---

## ユーティリティ設計

### Static クラス

TradeUtils, TimeUtils, MathUtils, Logger, DataExporter は全て**staticメソッドのみ**のクラスとして実装。インスタンス化不要で、どこからでも呼び出し可能。

```cpp
double lot = CSmcTradeUtils::CalcLotByRisk(_Symbol, 1.0, 20.0);
bool newBar = CSmcTimeUtils::IsNewBar(_Symbol, _Period);
double stdDev = CSmcMathUtils::StandardDeviation(arr, count);
CSmcLogger::Info("Trade opened");
```

### テンプレート関数（ArrayUtils）

MQL5はテンプレートクラスに制限があるため、配列操作はテンプレート**関数**として実装。

```cpp
template<typename T>
void SmcArrayPush(T &arr[], const T &item) { ... }
```

---

## MQL5コーディング規約

| 規約 | 例 |
|---|---|
| クラス名: `C` + PascalCase | `CSmcOrderBlock` |
| メンバ変数: `m_` プレフィックス | `m_bullishCount` |
| メソッド: PascalCase | `GetBullishOB()` |
| 列挙型: `ENUM_SMC_` + UPPER_CASE | `ENUM_SMC_TREND` |
| 列挙値: モジュール略称 + UPPER_CASE | `SMC_TREND_BULLISH` |
| 構造体: `Smc` + PascalCase | `SmcSwingPoint` |
| 定数: UPPER_CASE | `SMC_LIB_VERSION` |
| チャートオブジェクト接頭辞: `SMC_` + 略称 + `_` | `SMC_OB_BULL_0` |
| インクルードガード: `__SMC_` + UPPER_CASE + `_MQH__` | `__SMC_ORDER_BLOCK_MQH__` |
