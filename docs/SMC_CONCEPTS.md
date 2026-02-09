# SMC/ICT コンセプト解説

Smart Money Concepts (SMC) と Inner Circle Trader (ICT) の各概念と、本ライブラリでの実装方法を解説します。

## 目次

1. [スイングポイント (Swing Points)](#1-スイングポイント-swing-points)
2. [マーケット構造 (Market Structure)](#2-マーケット構造-market-structure)
3. [オーダーブロック (Order Block)](#3-オーダーブロック-order-block)
4. [フェアバリューギャップ (Fair Value Gap / FVG)](#4-フェアバリューギャップ-fair-value-gap--fvg)
5. [流動性 (Liquidity)](#5-流動性-liquidity)
6. [プレミアム・ディスカウント (Premium / Discount)](#6-プレミアムディスカウント-premium--discount)
7. [最適エントリー (Optimal Trade Entry / OTE)](#7-最適エントリー-optimal-trade-entry--ote)
8. [キルゾーン (Kill Zones)](#8-キルゾーン-kill-zones)
9. [ブレイカーブロック (Breaker Block)](#9-ブレイカーブロック-breaker-block)
10. [コンフルエンス (Confluence)](#10-コンフルエンス-confluence)
11. [通貨強弱 (Currency Strength)](#11-通貨強弱-currency-strength)
12. [ボラティリティ (VIX Calculator)](#12-ボラティリティ-vix-calculator)

---

## 1. スイングポイント (Swing Points)

### 概念

スイングポイントとは、価格が反転した局所的な高値（スイングハイ）と安値（スイングロー）のことです。全てのSMC分析の基礎となります。

### 検出ロジック（両側確認方式）

左右N本のバーより高い（低い）価格を持つバーをスイングポイントとして検出。

```
スイングハイの条件:
  High[i] > High[i-1], High[i-2], ..., High[i-N]  (右側)
  High[i] > High[i+1], High[i+2], ..., High[i+N]  (左側)
```

### 強度（Strength）

基本のN本を超えても条件を満たし続ける場合、強度が増加します。強度の高いスイングポイントはより信頼性が高く、重要なサポート/レジスタンスになります。

### ブレイク判定

スイングポイント形成後、現在までのバーでその価格を超えたかを追跡。ブレイクされたスイングは灰色で表示されます。

### ライブラリ対応

| クラス | `CSmcSwingPoints` |
|---|---|
| 設定 | `swingPeriod`（左右確認バー数、デフォルト: 5） |
| 出力 | `SmcSwingPoint` 構造体の配列（新しい順） |

---

## 2. マーケット構造 (Market Structure)

### 概念

マーケット構造は、スイングポイントの並びから現在のトレンド方向と構造変化を判定します。

### トレンド判定

| パターン | トレンド |
|---|---|
| Higher High (HH) + Higher Low (HL) | **上昇トレンド (Bullish)** |
| Lower High (LH) + Lower Low (LL) | **下降トレンド (Bearish)** |
| その他 | **レンジ (Ranging)** |

### BOS (Break of Structure)

トレンド方向に沿ったスイングポイントのブレイク。**トレンド継続**を示唆。

- 上昇トレンド中にスイングハイを上方ブレイク → **Bullish BOS**
- 下降トレンド中にスイングローを下方ブレイク → **Bearish BOS**

### CHoCH (Change of Character)

トレンドと**逆方向**のスイングポイントのブレイク。**トレンド転換**を示唆。

- 下降トレンド中にスイングハイを上方ブレイク → **Bullish CHoCH**（反転上昇の兆候）
- 上昇トレンド中にスイングローを下方ブレイク → **Bearish CHoCH**（反転下降の兆候）

### レンジ検出

HH/LLが長期間更新されない場合をレンジとして検出。レンジの高値/安値はサポート/レジスタンスとして機能します。

### ライブラリ対応

| クラス | `CSmcMarketStructure` |
|---|---|
| 依存 | `CSmcSwingPoints` |
| 出力 | `ENUM_SMC_TREND`, `SmcStructureBreak`, `SmcRangeInfo` |

---

## 3. オーダーブロック (Order Block)

### 概念

オーダーブロック（OB）は、大口注文が集中した価格帯です。強い方向性のムーブ（インパルス）の直前にある、逆方向のローソク足のレンジ（高値-安値）をOBとして定義します。

### 検出ロジック

1. **Bullish OB**: 陰線（弱気キャンドル）→ 強い上昇インパルスが続く → その陰線がBullish OB
2. **Bearish OB**: 陽線（強気キャンドル）→ 強い下降インパルスが続く → その陽線がBearish OB

インパルスムーブの判定基準:
- ムーブする方向のキャンドル実体が、平均実体の `minStrength`（デフォルト: 1.5倍）以上
- 合計ムーブが平均実体の2.0倍以上

### 状態遷移

```
FRESH → TESTED → BROKEN
  │        │        │
  │        │        └── 価格がOBを完全に抜けた
  │        └── 価格がOBゾーン内に触れた
  └── まだ価格が触れていない（最も信頼性が高い）
```

### スコアリング

OBの品質を0.0〜1.0のスコアで評価：
- 高確率分類: +0.2
- Fresh状態: +0.15
- 若いOB（age < 20バー）: +0.15

### ライブラリ対応

| クラス | `CSmcOrderBlock` |
|---|---|
| 依存 | `CSmcMarketStructure` |
| 出力 | `SmcZone` 構造体配列（Bullish/Bearish別） |

---

## 4. フェアバリューギャップ (Fair Value Gap / FVG)

### 概念

FVGは3本のローソク足パターンで検出されるギャップ（インバランス）です。大口が一方向に大量注文を出した結果、中央のキャンドルに他の2本でカバーされない価格帯が生まれます。

### 検出ロジック

```
Bullish FVG:  3本目のLow > 1本目のHigh
              → ギャップ = [1本目のHigh ～ 3本目のLow]

Bearish FVG:  3本目のHigh < 1本目のLow
              → ギャップ = [3本目のHigh ～ 1本目のLow]
```

### 確率分類

| 分類 | 条件 | 意味 |
|---|---|---|
| HIGH_PROB | 3本全て同方向のキャンドル | トレンドと一致するFVG |
| BREAKAWAY | ギャップサイズが平均レンジの2倍以上 | ブレイクアウトFVG |
| LOW_PROB | その他 | 低確率FVG |

### 状態遷移

```
FRESH → TESTED → BROKEN (filled)
  │        │        │
  │        │        └── 価格がFVGを完全に通過（埋められた）
  │        └── 価格がFVGゾーン内に入った
  └── まだ価格が触れていない
```

### ライブラリ対応

| クラス | `CSmcFairValueGap` |
|---|---|
| 依存 | なし（独立） |
| 出力 | `SmcZone` 構造体配列 + `ENUM_FVG_PROBABILITY` |

---

## 5. 流動性 (Liquidity)

### 概念

流動性は、ストップロスや指値注文が集中している価格帯です。スマートマネーはこれらの流動性を「狩る」（sweep）ことで有利なエントリーを得ます。

### Equal Highs / Equal Lows

ほぼ同じ価格のスイングハイ/ローが2つ以上ある場合、その価格帯の上/下にストップロスが集中していると考えます。

検出基準: 2つのスイングの価格差が `tolerancePips`（デフォルト: 3.0 pips）以内。

### 流動性プール

3回以上タッチされた流動性レベル。Equal H/Lよりも多くの注文が蓄積されていると考えます。

### 流動性スイープ

流動性レベルを一時的に超えた後に反転するパターン。「フェイクブレイクアウト」とも呼ばれます。

検出基準:
- 高値がレベルを tolerance 以上超えた
- しかしクローズはレベル以下に戻った
- → スイープと判定

### ライブラリ対応

| クラス | `CSmcLiquidity` |
|---|---|
| 依存 | `CSmcSwingPoints` |
| 出力 | `SmcLiquidityLevel` 構造体配列 |

---

## 6. プレミアム・ディスカウント (Premium / Discount)

### 概念

直近のスイングレンジ（高値〜安値）を基準に、価格の相対的位置を判定します。

```
Swing High ─────── 100% (Premium Zone)
     │
     │              > 50% = Premium（売りに有利）
     │
Equilibrium ────── 50%
     │
     │              < 50% = Discount（買いに有利）
     │
Swing Low ──────── 0% (Discount Zone)
```

### トレーディングへの応用

- **買いエントリー**: Discountゾーンで探す
- **売りエントリー**: Premiumゾーンで探す
- **Equilibrium**: 方向性が曖昧

### ライブラリ対応

| クラス | `CSmcPremiumDiscount` |
|---|---|
| 依存 | `CSmcSwingPoints` |
| 出力 | `IsPremium()`, `IsDiscount()`, `GetZonePercent()` |

---

## 7. 最適エントリー (Optimal Trade Entry / OTE)

### 概念

ICTのOTEは、フィボナッチ・リトレースメントの0.618〜0.786レベルのゾーンです。トレンド中のプルバック（戻り）がこのゾーンで反転しやすいとされます。

### フィボナッチレベル

```
Swing High ─── 0%
    │
    │          0.236
    │          0.382
    │          0.50  (Equilibrium)
    │          0.618 ─┐
    │          0.705  ├── OTE ゾーン（スイートスポット）
    │          0.786 ─┘
    │
Swing Low ──── 100%
```

### ライブラリ対応

| クラス | `CSmcOptimalTradeEntry` |
|---|---|
| 依存 | `CSmcSwingPoints` |
| 出力 | `SmcOTEZone` 構造体（各Fibレベル価格を含む） |

---

## 8. キルゾーン (Kill Zones)

### 概念

ICTのKill Zonesは、特定のセッション時間帯で価格のボラティリティが高まり、機関投資家が活発に取引する時間帯です。

### デフォルトセッション（GMT）

| セッション | 時間（GMT） | 特徴 |
|---|---|---|
| **Asian** | 00:00 - 08:00 | レンジ形成、流動性蓄積 |
| **London** | 07:00 - 16:00 | 高ボラティリティ、トレンド開始 |
| **New York** | 12:00 - 21:00 | トレンド継続、反転の可能性 |
| **London-NY Overlap** | 12:00 - 16:00 | 最も高いボラティリティ |

### セッション追跡

各セッションの高値・安値・始値を追跡し、セッションブレイクアウト等の判定に活用。

### ライブラリ対応

| クラス | `CSmcKillZone` |
|---|---|
| 依存 | なし（独立） |
| 出力 | `SmcSessionInfo` 構造体配列 |

---

## 9. ブレイカーブロック (Breaker Block)

### 概念

ブレイカーブロックは「失敗したオーダーブロック」です。OBとして機能すると期待されたゾーンが価格にブレイクされ、今度は**反対の役割**（S/R反転）を果たします。

### Breaker Block

- Bullish OBがブレイクされた → **Bearish Breaker**（レジスタンスとして機能）
- Bearish OBがブレイクされた → **Bullish Breaker**（サポートとして機能）

### Mitigation Block

完全にはブレイクされず、**部分的に消費**されたOB。ゾーン内で価格がある程度動いた後に反転。

### ライブラリ対応

| クラス | `CSmcBreakerBlock` |
|---|---|
| 依存 | `CSmcOrderBlock`, `CSmcMarketStructure` |
| 出力 | `SmcZone` 構造体配列 |

---

## 10. コンフルエンス (Confluence)

### 概念

コンフルエンスとは、複数のSMC要素が同じ価格帯で重なることです。要素が多く重なるほど、そのゾーンでの反転確率が高くなります。

### スコアリングシステム

各要素に重み付けスコアを割り当て、合計スコアで判定：

| 要素 | 重み（例） |
|---|---|
| トレンド方向一致 | 0.2 |
| OB（Fresh） | 0.2 |
| FVG存在 | 0.15 |
| Discountゾーン（買いの場合） | 0.15 |
| OTEゾーン内 | 0.1 |
| Kill Zone内 | 0.1 |
| 流動性スイープ後 | 0.1 |

### シグナル条件

```
BUY Signal:
  factorCount >= minConfluence (3) AND
  totalScore  >= minScore (0.5)    AND
  isBullish == true

SELL Signal:
  factorCount >= minConfluence (3) AND
  totalScore  >= minScore (0.5)    AND
  isBullish == false
```

### ライブラリ対応

| クラス | `CSmcConfluence` |
|---|---|
| 依存 | 全SMCモジュール（Set〇〇で注入） |
| 出力 | `SmcConfluenceZone` 構造体, `ENUM_ENTRY_SIGNAL` |

---

## 11. 通貨強弱 (Currency Strength)

### 概念

8主要通貨（USD, EUR, GBP, JPY, AUD, CAD, NZD, CHF）の28ペアの価格変化から、各通貨の相対的な強さ/弱さを算出します。

### 計算方法

| メソッド | アルゴリズム |
|---|---|
| `RATE_CHANGE` | 各ペアのN期間の価格変化率を合算 |
| `RSI` | 各ペアのRSI値（50基準）を合算 |

### 活用例

- 最強通貨 vs 最弱通貨のペアを選択
- 通貨の方向性でフィルタリング（base通貨が強く、quote通貨が弱い場合のみ買い）

### ライブラリ対応

| クラス | `CSmcCurrencyStrength` |
|---|---|
| 依存 | なし（独立） |
| 出力 | `SmcCurrencyInfo` 構造体配列、ランキング |

---

## 12. ボラティリティ (VIX Calculator)

### 概念

ヒストリカルボラティリティ（HV）を計算し、市場環境の「温度」を測定します。

### 計算式

```
1. 対数収益率: r[i] = ln(Close[i] / Close[i+1])
2. 日次ボラティリティ: σ_daily = StdDev(r[])
3. 年率化: VIX = σ_daily × √252 × 100
```

### レベル分類

| レベル | VIX値 | 意味 | トレーディング調整 |
|---|---|---|---|
| **LOW** | 0-15 | 低ボラティリティ | ロット↑(×1.2), SL↓(×0.8) |
| **NORMAL** | 15-25 | 通常 | 標準(×1.0) |
| **HIGH** | 25-35 | 高ボラティリティ | ロット↓(×0.7), SL↑(×1.5) |
| **EXTREME** | 35+ | 極端 | ロット大幅↓(×0.3), SL↑(×2.0), エントリー禁止 |

### ライブラリ対応

| クラス | `CSmcVIXCalculator` |
|---|---|
| 依存 | なし（独立） |
| 出力 | VIX値, `ENUM_VIX_LEVEL`, ロット/SL調整倍率 |
