# API リファレンス

全クラス・全メソッドの完全リファレンスです。

## 目次

1. [CSmcBase](#csmcbase)
2. [CSmcSwingPoints](#csmcswingpoints)
3. [CSmcMarketStructure](#csmcmarketstructure)
4. [CSmcOrderBlock](#csmcorderblock)
5. [CSmcFairValueGap](#csmcfairvaluegap)
6. [CSmcLiquidity](#csmcliquidity)
7. [CSmcPremiumDiscount](#csmcpremiumdiscount)
8. [CSmcOptimalTradeEntry](#csmcoptimaltradeentry)
9. [CSmcKillZone](#csmckillzone)
10. [CSmcBreakerBlock](#csmcbreakerblock)
11. [CSmcConfluence](#csmcconfluence)
12. [CSmcManager](#csmcmanager)
13. [CSmcCurrencyStrength](#csmccurrencystrength)
14. [CSmcVIXCalculator](#csmcvixcalculator)
15. [CSmcTradeUtils](#csmctradeutils)
16. [CSmcTimeUtils](#csmctimeutils)
17. [CSmcMathUtils](#csmcmathutils)
18. [ArrayUtils テンプレート関数](#arrayutils-テンプレート関数)
19. [CSmcLogger](#csmclogger)
20. [CSmcDataExporter](#csmcdataexporter)
21. [CSmcOnnxWrapper](#csmconnxwrapper)

---

## CSmcBase

**ファイル**: `Include/SMC/Core/SmcBase.mqh`
**継承**: なし（基底クラス）

全SMCモジュールの基底クラス。シンボル/タイムフレーム管理、Pip変換、価格データアクセスを提供。

### Public メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `Init(symbol, timeframe, enableDraw)` | `bool` | 初期化。シンボル情報取得、ATR作成 |
| `Update()` | `bool` | 純粋仮想。各モジュールで実装 |
| `Clean()` | `void` | チャートオブジェクトの削除 |
| `Symbol()` | `string` | 対象シンボル名 |
| `Timeframe()` | `ENUM_TIMEFRAMES` | 対象タイムフレーム |
| `IsInitialized()` | `bool` | 初期化完了判定 |
| `IsDrawEnabled()` | `bool` | 描画有効判定 |
| `SetDrawEnabled(enabled)` | `void` | 描画ON/OFF変更 |

### Protected メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `PipsToPrice(pips)` | `double` | Pips値→価格差に変換 |
| `PriceToPips(priceDistance)` | `double` | 価格差→Pips値に変換 |
| `NormalizePrice(price)` | `double` | 価格を桁数で正規化 |
| `GetATR(period, shift)` | `double` | ATR取得 (デフォルト: 14期間) |
| `GetAverageRange(period, shift)` | `double` | 平均レンジ（H-L）取得 |
| `GetAverageCandleBody(period, shift)` | `double` | 平均ローソク足実体サイズ |
| `High(shift)` / `Low(shift)` | `double` | 高値/安値 |
| `Open(shift)` / `Close(shift)` | `double` | 始値/終値 |
| `Volume(shift)` | `long` | ボリューム |
| `Time(shift)` | `datetime` | バー時刻 |
| `IsBullishCandle(shift)` | `bool` | 陽線判定 |
| `IsBearishCandle(shift)` | `bool` | 陰線判定 |
| `CandleBody(shift)` | `double` | 実体サイズ（絶対値） |
| `CandleRange(shift)` | `double` | レンジ（H-L） |
| `UpperWick(shift)` / `LowerWick(shift)` | `double` | 上ヒゲ/下ヒゲサイズ |

---

## CSmcSwingPoints

**ファイル**: `Include/SMC/SwingPoints.mqh`
**継承**: `CSmcBase`

両側確認方式によるスイングハイ/ロー検出。全SMCモジュールの基盤。

### Init

```cpp
bool Init(string symbol, ENUM_TIMEFRAMES timeframe,
          bool enableDraw = false,
          int swingPeriod = 5,      // 左右確認バー数
          int maxPoints = 50,       // 最大保持ポイント数
          int lookbackBars = 500);  // 検索範囲バー数
```

### Public メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `SetSwingPeriod(period)` | `void` | スイング確認バー数を変更 |
| `SetColors(highClr, lowClr)` | `void` | 描画色を変更 |
| `GetHighCount()` | `int` | 検出済みスイングハイ数 |
| `GetLowCount()` | `int` | 検出済みスイングロー数 |
| `GetSwingHigh(index, &point)` | `bool` | index番目のスイングハイ取得 (0=最新) |
| `GetSwingLow(index, &point)` | `bool` | index番目のスイングロー取得 (0=最新) |
| `GetHighPrice(index)` | `double` | index番目のスイングハイ価格 |
| `GetLowPrice(index)` | `double` | index番目のスイングロー価格 |
| `GetTrendDirection()` | `ENUM_SMC_TREND` | HH/HL, LH/LLによるトレンド判定 |
| `IsHighBroken(index)` | `bool` | スイングハイがブレイクされたか |
| `IsLowBroken(index)` | `bool` | スイングローがブレイクされたか |
| `LastSwingHigh()` | `double` | 直近スイングハイ価格 |
| `LastSwingLow()` | `double` | 直近スイングロー価格 |
| `PrevSwingHigh()` | `double` | 2番目のスイングハイ価格 |
| `PrevSwingLow()` | `double` | 2番目のスイングロー価格 |

---

## CSmcMarketStructure

**ファイル**: `Include/SMC/MarketStructure.mqh`
**継承**: `CSmcBase`
**依存**: `CSmcSwingPoints`

BOS / CHoCH / トレンド / レンジ分析。

### Init

```cpp
bool Init(string symbol, ENUM_TIMEFRAMES timeframe,
          bool enableDraw = false,
          CSmcSwingPoints *swingPoints = NULL);  // NULL=自前作成
```

### Public メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `SwingPoints()` | `CSmcSwingPoints*` | 内部SwingPoints参照 |
| `GetTrend()` | `ENUM_SMC_TREND` | 現在のトレンド |
| `GetPreviousTrend()` | `ENUM_SMC_TREND` | 前回のトレンド |
| `IsBullish()` / `IsBearish()` / `IsRanging()` | `bool` | トレンド判定 |
| `GetLastBOS(&brk)` | `bool` | 直近BOS取得 |
| `GetLastCHoCH(&brk)` | `bool` | 直近CHoCH取得 |
| `HasRecentBOS(withinBars)` | `bool` | 直近N本以内にBOSがあるか |
| `HasRecentCHoCH(withinBars)` | `bool` | 直近N本以内にCHoCHがあるか |
| `GetCurrentRange(&range)` | `bool` | 現在のレンジ情報取得 |
| `IsInRange()` | `bool` | レンジ内にいるか |
| `GetEntryDirection()` | `ENUM_ENTRY_SIGNAL` | 構造に基づくエントリー方向 |

---

## CSmcOrderBlock

**ファイル**: `Include/SMC/OrderBlock.mqh`
**継承**: `CSmcBase`
**依存**: `CSmcMarketStructure`

オーダーブロック検出・状態管理。

### Init

```cpp
bool Init(string symbol, ENUM_TIMEFRAMES timeframe,
          bool enableDraw = false,
          CSmcMarketStructure *structure = NULL);
```

### Public メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `SetMaxAge(age)` | `void` | OBの最大寿命（バー数） |
| `SetMinStrength(str)` | `void` | インパルスムーブ最小強度倍率 |
| `GetBullishCount()` / `GetBearishCount()` | `int` | OB数 |
| `GetBullishOB(index, &ob)` | `bool` | 強気OB取得 |
| `GetBearishOB(index, &ob)` | `bool` | 弱気OB取得 |
| `GetNearestBullishOB(price, &ob)` | `bool` | 価格に最も近い強気OB |
| `GetNearestBearishOB(price, &ob)` | `bool` | 価格に最も近い弱気OB |
| `GetFreshBullishCount()` / `GetFreshBearishCount()` | `int` | Fresh状態のOB数 |
| `GetStopLossForBuy(&ob)` | `double` | 買いSL価格（OB下端 - 2pips） |
| `GetStopLossForSell(&ob)` | `double` | 売りSL価格（OB上端 + 2pips） |
| `Structure()` | `CSmcMarketStructure*` | 内部Structure参照 |

---

## CSmcFairValueGap

**ファイル**: `Include/SMC/FairValueGap.mqh`
**継承**: `CSmcBase`
**依存**: なし（独立）

Fair Value Gap（FVG/インバランス）検出。

### Init

```cpp
bool Init(string symbol, ENUM_TIMEFRAMES timeframe,
          bool enableDraw = false,
          double minSizePips = 2.0,   // 最小FVGサイズ
          int maxAge = 200);          // 最大寿命バー数
```

### Public メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `SetMinSizePips(pips)` | `void` | 最小FVGサイズ変更 |
| `SetMaxAge(age)` | `void` | 最大寿命変更 |
| `GetBullishCount()` / `GetBearishCount()` | `int` | FVG数 |
| `GetBullishFVG(index, &fvg)` | `bool` | 強気FVG取得 |
| `GetBearishFVG(index, &fvg)` | `bool` | 弱気FVG取得 |
| `GetNearestBullishFVG(price, &fvg)` | `bool` | 最寄り強気FVG |
| `GetNearestBearishFVG(price, &fvg)` | `bool` | 最寄り弱気FVG |
| `GetFreshBullishCount()` / `GetFreshBearishCount()` | `int` | Fresh FVG数 |
| `IsPriceInBullishFVG(price)` | `bool` | 価格がBullish FVG内か |
| `IsPriceInBearishFVG(price)` | `bool` | 価格がBearish FVG内か |

---

## CSmcLiquidity

**ファイル**: `Include/SMC/Liquidity.mqh`
**継承**: `CSmcBase`
**依存**: `CSmcSwingPoints`

Equal Highs/Lows、流動性プール、流動性スイープ検出。

### Init

```cpp
bool Init(string symbol, ENUM_TIMEFRAMES timeframe,
          bool enableDraw = false,
          CSmcSwingPoints *swingPoints = NULL,
          double tolerancePips = 3.0);
```

### Public メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `SetTolerancePips(pips)` | `void` | Equal H/L許容範囲 |
| `SetMinTouches(touches)` | `void` | プール判定最小タッチ数 |
| `GetLevelCount()` | `int` | 検出レベル数 |
| `GetLevel(index, &level)` | `bool` | レベル取得 |
| `GetEqualHighsCount()` / `GetEqualLowsCount()` | `int` | EQH/EQL数 |
| `GetNearestEqualHigh(price, &level)` | `bool` | 最寄りEQH |
| `GetNearestEqualLow(price, &level)` | `bool` | 最寄りEQL |
| `IsLiquiditySweep(type)` | `bool` | 指定タイプのスイープ有無 |
| `HasRecentSweep(withinBars)` | `bool` | 直近N本以内にスイープ有無 |

---

## CSmcPremiumDiscount

**ファイル**: `Include/SMC/PremiumDiscount.mqh`
**継承**: `CSmcBase`
**依存**: `CSmcSwingPoints`

Premium / Discount / Equilibrium ゾーン計算。

### Public メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `IsPremium(price)` | `bool` | 価格がPremiumゾーン（>50%）にあるか |
| `IsDiscount(price)` | `bool` | 価格がDiscountゾーン（<50%）にあるか |
| `GetZonePercent(price)` | `double` | 価格のゾーン位置（0〜100%） |
| `GetEquilibrium()` | `double` | 50%基準価格 |
| `GetPremiumLevel()` | `double` | Premiumゾーン下限 |
| `GetDiscountLevel()` | `double` | Discountゾーン上限 |

---

## CSmcOptimalTradeEntry

**ファイル**: `Include/SMC/OptimalTradeEntry.mqh`
**継承**: `CSmcBase`
**依存**: `CSmcSwingPoints`

OTE（Fibonacci 0.618-0.786 ベース）エントリーゾーン。

### Public メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `GetOTEZone(&zone)` | `bool` | OTEゾーン情報取得（SmcOTEZone構造体） |
| `IsInOTEZone(price)` | `bool` | 価格がOTEゾーン内か |
| `GetFibLevel(level)` | `double` | 指定フィボナッチレベルの価格 |

---

## CSmcKillZone

**ファイル**: `Include/SMC/KillZone.mqh`
**継承**: `CSmcBase`
**依存**: なし（独立）

ICT Kill Zones（セッション時間フィルター）。

### Public メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `SetGMTOffset(offset)` | `void` | GMTオフセット設定 |
| `IsInKillZone()` | `bool` | 現在いずれかのKZにいるか |
| `GetCurrentSession()` | `ENUM_SMC_SESSION` | 現在のセッション |
| `GetSessionInfo(session, &info)` | `bool` | セッション詳細取得 |
| `GetSessionHigh(session)` | `double` | セッション高値 |
| `GetSessionLow(session)` | `double` | セッション安値 |

### デフォルトセッション時間（GMT）

| セッション | 開始 | 終了 |
|---|---|---|
| Asian | 00:00 | 08:00 |
| London | 07:00 | 16:00 |
| New York | 12:00 | 21:00 |
| London-NY Overlap | 12:00 | 16:00 |

---

## CSmcBreakerBlock

**ファイル**: `Include/SMC/BreakerBlock.mqh`
**継承**: `CSmcBase`
**依存**: `CSmcOrderBlock`, `CSmcMarketStructure`

Breaker Block / Mitigation Block 検出。

### Public メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `GetBreakerCount()` | `int` | Breaker Block数 |
| `GetMitigationCount()` | `int` | Mitigation Block数 |
| `GetBreakerBlock(index, &zone)` | `bool` | Breaker Block取得 |
| `GetMitigationBlock(index, &zone)` | `bool` | Mitigation Block取得 |

---

## CSmcConfluence

**ファイル**: `Include/SMC/ConfluenceDetector.mqh`
**継承**: `CSmcBase`
**依存**: 全SMCモジュール（Set〇〇で注入）

コンフルエンス判定（全要素のスコアリング）。

### Public メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `SetStructure(ptr)` | `void` | MarketStructureモジュール設定 |
| `SetOrderBlock(ptr)` | `void` | OrderBlockモジュール設定 |
| `SetFVG(ptr)` | `void` | FVGモジュール設定 |
| `SetLiquidity(ptr)` | `void` | Liquidityモジュール設定 |
| `SetOTE(ptr)` | `void` | OTEモジュール設定 |
| `SetKillZone(ptr)` | `void` | KillZoneモジュール設定 |
| `SetBreaker(ptr)` | `void` | BreakerBlockモジュール設定 |
| `SetMinConfluence(count)` | `void` | 最小要因数（デフォルト: 3） |
| `SetMinScore(score)` | `void` | 最小スコア（デフォルト: 0.5） |
| `GetEntrySignal()` | `ENUM_ENTRY_SIGNAL` | BUY/SELL/WAIT |
| `GetBuyZone(&zone)` | `bool` | 買いコンフルエンスゾーン取得 |
| `GetSellZone(&zone)` | `bool` | 売りコンフルエンスゾーン取得 |

---

## CSmcManager

**ファイル**: `Include/SMC/SmcManager.mqh`
**依存**: 全モジュール

全SMCモジュール統合マネージャー。

### Init

```cpp
bool Init(string symbol, ENUM_TIMEFRAMES timeframe,
          bool enableDraw = false,
          bool enableCS = true,     // 通貨強弱
          bool enableVIX = true);   // VIX計算
```

### Public メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `Update()` | `bool` | 全モジュール一括更新 |
| `Clean()` | `void` | 全チャートオブジェクト削除 |
| `Swing()` | `CSmcSwingPoints*` | SwingPointsアクセス |
| `Structure()` | `CSmcMarketStructure*` | MarketStructureアクセス |
| `OB()` | `CSmcOrderBlock*` | OrderBlockアクセス |
| `FVG()` | `CSmcFairValueGap*` | FVGアクセス |
| `Liquidity()` | `CSmcLiquidity*` | Liquidityアクセス |
| `PD()` | `CSmcPremiumDiscount*` | PremiumDiscountアクセス |
| `OTE()` | `CSmcOptimalTradeEntry*` | OTEアクセス |
| `KZ()` | `CSmcKillZone*` | KillZoneアクセス |
| `Breaker()` | `CSmcBreakerBlock*` | BreakerBlockアクセス |
| `Confluence()` | `CSmcConfluence*` | ConfluenceDetectorアクセス |
| `CurrStr()` | `CSmcCurrencyStrength*` | CurrencyStrengthアクセス |
| `VIX()` | `CSmcVIXCalculator*` | VIXCalculatorアクセス |
| `GetTrend()` | `ENUM_SMC_TREND` | 現在のトレンド |
| `GetSignal()` | `ENUM_ENTRY_SIGNAL` | コンフルエンスシグナル |
| `IsBullish()` / `IsBearish()` | `bool` | トレンド判定 |
| `IsInitialized()` | `bool` | 初期化完了判定 |

---

## CSmcCurrencyStrength

**ファイル**: `Include/SMC/Analysis/CurrencyStrength.mqh`
**継承**: `CSmcBase`

8主要通貨（USD, EUR, GBP, JPY, AUD, CAD, NZD, CHF）の28ペアから相対強弱を算出。

### Init

```cpp
bool Init(string symbol, ENUM_TIMEFRAMES timeframe,
          bool enableDraw = false,
          ENUM_CS_METHOD method = CS_METHOD_RATE_CHANGE,
          int period = 10);
```

### Public メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `SetMethod(method)` | `void` | 計算方法変更 |
| `SetPeriod(period)` | `void` | 計算期間変更 |
| `GetStrength(currency)` | `double` | 通貨の強弱値（-100〜+100） |
| `GetMomentum(currency)` | `double` | 通貨のモメンタム（変化速度） |
| `GetRank(currency)` | `int` | 通貨のランク（1=最強, 8=最弱） |
| `GetCurrencyInfo(currency, &info)` | `bool` | 通貨詳細情報取得 |
| `GetStrongest()` | `string` | 最強通貨名 |
| `GetWeakest()` | `string` | 最弱通貨名 |
| `GetBestPair()` | `string` | 最強vs最弱ペア名 |
| `GetSortedCurrencies(&sorted[])` | `void` | 強弱順ソート済み通貨配列 |
| `IsStrongVsWeak(base, quote)` | `bool` | base通貨がquote通貨より強いか |

---

## CSmcVIXCalculator

**ファイル**: `Include/SMC/Analysis/VIXCalculator.mqh`
**継承**: `CSmcBase`

ヒストリカルボラティリティ（対数収益率の標準偏差 × √252）によるVIX相当値算出。

### Init

```cpp
bool Init(string symbol, ENUM_TIMEFRAMES timeframe,
          bool enableDraw = false,
          int calcPeriod = 20,              // 計算期間（バー数）
          ENUM_TIMEFRAMES calcTF = PERIOD_D1); // 計算TF
```

### Public メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `GetVIX()` | `double` | 現在のVIX値 |
| `GetVIXLevel()` | `ENUM_VIX_LEVEL` | LOW/NORMAL/HIGH/EXTREME |
| `GetVIXTrend()` | `int` | 1=上昇, 0=横, -1=下降 |
| `GetVIXLevelName()` | `string` | レベル名文字列 |
| `GetLotMultiplier()` | `double` | ロット調整倍率（LOW:1.2, NORMAL:1.0, HIGH:0.7, EXTREME:0.3） |
| `GetSLMultiplier()` | `double` | SL調整倍率（LOW:0.8, NORMAL:1.0, HIGH:1.5, EXTREME:2.0） |
| `IsEntryAllowed()` | `bool` | EXTREME以外でtrue |
| `GetPercentile(period)` | `double` | 現在VIXのパーセンタイル値 |
| `GetVIXMA(period)` | `double` | VIX移動平均 |
| `SetThresholds(low, normal, high)` | `void` | レベル閾値カスタマイズ |

---

## CSmcTradeUtils

**ファイル**: `Include/SMC/Utils/TradeUtils.mqh`
**タイプ**: Static ユーティリティクラス

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `CalcLotByRisk(symbol, riskPercent, slPips)` | `double` | リスク%ベースのロット計算 |
| `CalcLotByFixedAmount(symbol, amount, slPips)` | `double` | 固定金額ベースのロット計算 |
| `NormalizeLot(symbol, lot)` | `double` | ブローカーのロットステップ/最小/最大に正規化 |
| `GetSpreadPips(symbol)` | `double` | 現在スプレッド（pips） |
| `IsSpreadOK(symbol, maxSpreadPips)` | `bool` | スプレッドが許容範囲内か |
| `GetSwapLong(symbol)` / `GetSwapShort(symbol)` | `double` | スワップ値 |
| `IsTradeAllowed(symbol)` | `bool` | 取引可否チェック（市場・EA許可・マージン） |

---

## CSmcTimeUtils

**ファイル**: `Include/SMC/Utils/TimeUtils.mqh`
**タイプ**: Static ユーティリティクラス

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `GetGMTOffset()` | `int` | ブローカーGMTオフセット自動検出 |
| `ToGMT(time, offset)` | `datetime` | ローカル→GMT変換 |
| `FromGMT(time, offset)` | `datetime` | GMT→ローカル変換 |
| `IsNewBar(symbol, tf)` | `bool` | 新バー検出（シンボル+TF別に追跡） |
| `GetDayOfWeek()` | `int` | 曜日取得（0=日, 6=土） |
| `IsWeekend()` | `bool` | 週末判定 |
| `IsEndOfDay(hourGMT)` | `bool` | 取引日終了判定 |
| `IsEndOfWeek()` | `bool` | 取引週終了判定 |
| `IsDST()` | `bool` | サマータイム判定（ヒューリスティック） |
| `SecondsSinceBarOpen(symbol, tf)` | `int` | 現在バー開始からの経過秒数 |

---

## CSmcMathUtils

**ファイル**: `Include/SMC/Utils/MathUtils.mqh`
**タイプ**: Static ユーティリティクラス

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `StandardDeviation(&arr[], count)` | `double` | 標準偏差 |
| `ZScore(value, &arr[], count)` | `double` | Zスコア |
| `Correlation(&x[], &y[], count)` | `double` | ピアソン相関係数 |
| `LinearRegression(&arr[], count, &slope, &intercept)` | `bool` | 線形回帰（傾き・切片） |
| `Percentile(&arr[], count, pct)` | `double` | パーセンタイル（0.0-1.0） |
| `EMA(value, prev, period)` | `double` | 指数移動平均の1ステップ計算 |
| `NormalizeMinMax(value, min, max)` | `double` | Min-Max正規化（0-1） |
| `Sigmoid(x)` | `double` | シグモイド関数 |
| `ReLU(x)` | `double` | ReLU関数 |

---

## ArrayUtils テンプレート関数

**ファイル**: `Include/SMC/Utils/ArrayUtils.mqh`

| 関数 | 説明 |
|---|---|
| `SmcArrayPush(&arr[], &item)` | 末尾に要素追加 |
| `SmcArrayPop(&arr[], &item)` | 末尾から要素取り出し |
| `SmcArrayInsertAt(&arr[], &item, index)` | 指定位置に挿入 |
| `SmcArrayRemoveAt(&arr[], index)` | 指定位置から削除 |
| `SmcArrayMax(&arr[], count)` | 最大値 |
| `SmcArrayMin(&arr[], count)` | 最小値 |
| `SmcArraySum(&arr[], count)` | 合計値 |
| `SmcArrayReverse(&arr[], count)` | 配列反転 |
| `SmcArraySlice(&src[], &dst[], start, length)` | 部分配列取得 |

---

## CSmcLogger

**ファイル**: `Include/SMC/Utils/Logger.mqh`
**タイプ**: Static シングルトン型クラス

| メソッド | 説明 |
|---|---|
| `SetLevel(level)` | ログレベル設定（DEBUG/INFO/WARN/ERROR） |
| `SetModule(name)` | モジュール名タグ設定 |
| `EnableFileLog(filename)` | ファイルログ有効化（1MBローテーション） |
| `DisableFileLog()` | ファイルログ無効化 |
| `Debug(msg)` | DEBUGレベルログ |
| `Info(msg)` | INFOレベルログ |
| `Warn(msg)` | WARNレベルログ |
| `Error(msg)` | ERRORレベルログ |

**出力フォーマット**: `[LEVEL][Module][HH:MM:SS] message`

---

## CSmcDataExporter

**ファイル**: `Include/SMC/Utils/DataExporter.mqh`
**タイプ**: Static ユーティリティクラス

| メソッド | 説明 |
|---|---|
| `ExportOHLCV(symbol, tf, bars, filename)` | OHLCV基本データをCSVエクスポート |
| `ExportWithIndicators(symbol, tf, bars, filename)` | OHLCV + テクニカル指標付きCSV |
| `ExportSmcFeatures(symbol, tf, bars, filename, &smc)` | OHLCV + SMC特徴量付きCSV |
| `ExportMultiSymbol(symbols[], tf, bars, folder)` | 複数シンボル一括エクスポート |

---

## CSmcOnnxWrapper

**ファイル**: `Include/SMC/Utils/OnnxWrapper.mqh`
**タイプ**: インスタンスクラス

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `LoadFromFile(modelPath)` | `bool` | ファイルからONNXモデル読み込み |
| `LoadFromBuffer(&buffer[])` | `bool` | バッファからONNXモデル読み込み |
| `SetInputShape(features)` | `void` | 入力特徴量数設定 |
| `SetOutputShape(outputs)` | `void` | 出力クラス数設定 |
| `LoadScaler(meanFile, scaleFile)` | `bool` | スケーラーパラメータ読み込み |
| `ApplyScaler(&features[])` | `bool` | 特徴量にスケーラー適用 |
| `Predict(&features[], &output[])` | `bool` | 推論実行 |
| `PredictClass(&features[])` | `int` | 分類予測（argmax） |
| `GetConfidence(&output[])` | `double` | 信頼度（最大確率） |
| `IsLoaded()` | `bool` | モデル読み込み済み判定 |
| `GetNumFeatures()` / `GetNumOutputs()` | `int` | 特徴量数/出力数 |
| `Release()` | `void` | モデルハンドル解放 |
