# 実践コード例集

## 目次

1. [単体モジュール使用](#単体モジュール使用)
2. [SmcManager統合使用](#smcmanager統合使用)
3. [EA開発パターン](#ea開発パターン)
4. [インジケーター開発パターン](#インジケーター開発パターン)
5. [フィルタリング・条件付きエントリー](#フィルタリング条件付きエントリー)
6. [通貨強弱の活用](#通貨強弱の活用)
7. [VIXによるリスク管理](#vixによるリスク管理)
8. [ONNX推論の組み込み](#onnx推論の組み込み)
9. [ロギング活用](#ロギング活用)
10. [データエクスポート](#データエクスポート)

---

## 単体モジュール使用

### OrderBlock だけを使う

```cpp
#include <SMC/OrderBlock.mqh>

CSmcOrderBlock ob;

int OnInit()
{
   // MarketStructure は内部で自動作成される
   if(!ob.Init(_Symbol, _Period, true))
      return INIT_FAILED;

   ob.SetMaxAge(80);           // OBの最大寿命
   ob.SetMinStrength(2.0);     // インパルス強度を厳しく
   return INIT_SUCCEEDED;
}

void OnTick()
{
   ob.Update();

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // 全Fresh Bullish OBをチェック
   for(int i = 0; i < ob.GetBullishCount(); i++)
   {
      SmcZone zone;
      if(ob.GetBullishOB(i, zone) && zone.IsFresh())
      {
         Print("Fresh Bullish OB #", i,
               " [", zone.bottomPrice, " - ", zone.topPrice, "]",
               " Score: ", zone.score);

         // 価格がOBに接近したら通知
         if(bid <= zone.topPrice && bid >= zone.bottomPrice)
            Alert("Price in Bullish OB zone!");
      }
   }
}
```

### MarketStructure でBOS/CHoCHを監視

```cpp
#include <SMC/MarketStructure.mqh>

CSmcMarketStructure ms;

int OnInit()
{
   if(!ms.Init(_Symbol, _Period, true))
      return INIT_FAILED;
   return INIT_SUCCEEDED;
}

void OnTick()
{
   ms.Update();

   // トレンド変化を検出
   if(ms.GetTrend() != ms.GetPreviousTrend())
   {
      Print("Trend changed from ",
            EnumToString(ms.GetPreviousTrend()),
            " to ", EnumToString(ms.GetTrend()));
   }

   // CHoCH（トレンド転換）検出
   SmcStructureBreak choch;
   if(ms.GetLastCHoCH(choch) && choch.barIndex <= 3)
   {
      Alert("CHoCH detected! ",
            choch.isBullish ? "Bullish" : "Bearish",
            " at ", choch.breakPrice);
   }

   // レンジ内判定
   if(ms.IsInRange())
   {
      SmcRangeInfo range;
      ms.GetCurrentRange(range);
      Print("In Range: ", range.lowPrice, " - ", range.highPrice,
            " (", range.duration, " bars)");
   }
}
```

### Liquidity でスイープを検出

```cpp
#include <SMC/Liquidity.mqh>

CSmcLiquidity liq;

int OnInit()
{
   if(!liq.Init(_Symbol, _Period, true, NULL, 2.5))
      return INIT_FAILED;
   return INIT_SUCCEEDED;
}

void OnTick()
{
   liq.Update();

   // 直近のスイープを検出
   if(liq.HasRecentSweep(3))
   {
      Print("Liquidity sweep detected within last 3 bars!");

      // スイープ詳細を取得
      for(int i = 0; i < liq.GetLevelCount(); i++)
      {
         SmcLiquidityLevel level;
         if(liq.GetLevel(i, level) && level.isSweep)
         {
            Print("Sweep at ", level.price,
                  " Type: ", EnumToString(level.type),
                  " Touches: ", level.touchCount);
         }
      }
   }
}
```

---

## SmcManager統合使用

### 全モジュールのサマリー表示

```cpp
#include <SMC/SmcManager.mqh>

CSmcManager *smc;

int OnInit()
{
   smc = new CSmcManager();
   if(!smc.Init(_Symbol, _Period, true, true, true))
   {
      delete smc;
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

void OnTick()
{
   smc.Update();

   // 全モジュールのサマリーを出力
   Print("=== SMC Summary ===");
   Print("Trend: ", EnumToString(smc.GetTrend()));
   Print("Signal: ", EnumToString(smc.GetSignal()));

   // SwingPoints
   Print("Swing Highs: ", smc.Swing().GetHighCount(),
         ", Lows: ", smc.Swing().GetLowCount());

   // OB
   Print("Bullish OBs: ", smc.OB().GetBullishCount(),
         " (Fresh: ", smc.OB().GetFreshBullishCount(), ")");
   Print("Bearish OBs: ", smc.OB().GetBearishCount(),
         " (Fresh: ", smc.OB().GetFreshBearishCount(), ")");

   // FVG
   Print("Bullish FVGs: ", smc.FVG().GetBullishCount(),
         " (Fresh: ", smc.FVG().GetFreshBullishCount(), ")");

   // KillZone
   Print("In Kill Zone: ", smc.KZ().IsInKillZone());

   // VIX
   if(smc.VIX() != NULL)
      Print("VIX: ", DoubleToString(smc.VIX().GetVIX(), 2),
            " (", smc.VIX().GetVIXLevelName(), ")");

   // Currency Strength
   if(smc.CurrStr() != NULL)
      Print("Strongest: ", smc.CurrStr().GetStrongest(),
            " | Weakest: ", smc.CurrStr().GetWeakest());
}

void OnDeinit(const int reason)
{
   if(smc != NULL) { smc.Clean(); delete smc; }
}
```

---

## EA開発パターン

### コンフルエンス + OBベース SL/TP のEA

```cpp
#include <SMC/SmcManager.mqh>
#include <SMC/Utils/TradeUtils.mqh>
#include <Trade/Trade.mqh>

input double InpRisk = 1.0;
input int    InpMagic = 12345;

CSmcManager *smc;
CTrade       trade;
datetime     lastBar;

int OnInit()
{
   smc = new CSmcManager();
   if(!smc.Init(_Symbol, _Period, false, false, true))
      return INIT_FAILED;

   trade.SetExpertMagicNumber(InpMagic);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   // 新バーのみ処理
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == lastBar) return;
   lastBar = barTime;

   smc.Update();

   // 既存ポジションがあればスキップ
   if(PositionSelect(_Symbol)) return;

   // VIXフィルター
   if(smc.VIX() != NULL && !smc.VIX().IsEntryAllowed()) return;

   // スプレッドフィルター
   if(!CSmcTradeUtils::IsSpreadOK(_Symbol, 3.0)) return;

   // コンフルエンスシグナル
   ENUM_ENTRY_SIGNAL sig = smc.GetSignal();
   if(sig == SIGNAL_WAIT) return;

   double price, sl, tp, lotSize;

   if(sig == SIGNAL_BUY)
   {
      SmcZone ob;
      if(!smc.OB().GetNearestBullishOB(SymbolInfoDouble(_Symbol, SYMBOL_ASK), ob))
         return;

      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl    = smc.OB().GetStopLossForBuy(ob);

      double slPips = (price - sl) / (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10);
      if(slPips <= 0) return;

      // VIXによるロット・SL調整
      double lotMul = (smc.VIX() != NULL) ? smc.VIX().GetLotMultiplier() : 1.0;
      double slMul  = (smc.VIX() != NULL) ? smc.VIX().GetSLMultiplier() : 1.0;

      sl      = price - (price - sl) * slMul;
      lotSize = CSmcTradeUtils::CalcLotByRisk(_Symbol, InpRisk, slPips) * lotMul;
      tp      = price + (price - sl) * 2.0;  // RR 1:2

      trade.Buy(lotSize, _Symbol, price, sl, tp, "SMC Confluence Buy");
   }
   else if(sig == SIGNAL_SELL)
   {
      SmcZone ob;
      if(!smc.OB().GetNearestBearishOB(SymbolInfoDouble(_Symbol, SYMBOL_BID), ob))
         return;

      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl    = smc.OB().GetStopLossForSell(ob);

      double slPips = (sl - price) / (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10);
      if(slPips <= 0) return;

      double lotMul = (smc.VIX() != NULL) ? smc.VIX().GetLotMultiplier() : 1.0;
      double slMul  = (smc.VIX() != NULL) ? smc.VIX().GetSLMultiplier() : 1.0;

      sl      = price + (sl - price) * slMul;
      lotSize = CSmcTradeUtils::CalcLotByRisk(_Symbol, InpRisk, slPips) * lotMul;
      tp      = price - (sl - price) * 2.0;

      trade.Sell(lotSize, _Symbol, price, sl, tp, "SMC Confluence Sell");
   }
}

void OnDeinit(const int reason)
{
   if(smc) { smc.Clean(); delete smc; }
}
```

---

## インジケーター開発パターン

### FVG + PremiumDiscount ゾーン可視化

```cpp
#property indicator_chart_window
#property indicator_buffers 0

#include <SMC/FairValueGap.mqh>
#include <SMC/PremiumDiscount.mqh>

input int InpSwingPeriod = 5;

CSmcFairValueGap fvg;
CSmcPremiumDiscount pd;

int OnInit()
{
   fvg.Init(_Symbol, _Period, true, 2.0, 200);
   pd.Init(_Symbol, _Period, true);
   return INIT_SUCCEEDED;
}

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   fvg.Update();
   pd.Update();

   // Discountゾーン内のFreshなFVGを強調表示
   Comment("Premium/Discount: ",
           pd.IsPremium(close[rates_total-1]) ? "PREMIUM" :
           pd.IsDiscount(close[rates_total-1]) ? "DISCOUNT" : "EQUILIBRIUM",
           " (", DoubleToString(pd.GetZonePercent(close[rates_total-1]), 1), "%)");

   return rates_total;
}

void OnDeinit(const int reason)
{
   fvg.Clean();
   pd.Clean();
}
```

---

## フィルタリング・条件付きエントリー

### 複合フィルター例

```cpp
// Kill Zone + Discount/Premium + Fresh OB + トレンド一致
bool IsBuyAllowed()
{
   // 1. トレンドが上昇
   if(!smc.IsBullish()) return false;

   // 2. Kill Zone内
   if(!smc.KZ().IsInKillZone()) return false;

   // 3. Discountゾーン
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(!smc.PD().IsDiscount(bid)) return false;

   // 4. Fresh Bullish OBが存在
   if(smc.OB().GetFreshBullishCount() == 0) return false;

   // 5. 直近に流動性スイープがあった
   if(!smc.Liquidity().HasRecentSweep(5)) return false;

   // 6. OTEゾーン内
   if(!smc.OTE().IsInOTEZone(bid)) return false;

   return true;
}
```

---

## 通貨強弱の活用

### 最強 vs 最弱ペアの自動選択

```cpp
#include <SMC/Analysis/CurrencyStrength.mqh>

CSmcCurrencyStrength cs;

void OnStart()
{
   cs.Init(_Symbol, PERIOD_M5, false, CS_METHOD_RSI, 14);
   cs.Update();

   // ランキング表示
   string sorted[];
   cs.GetSortedCurrencies(sorted);
   for(int i = 0; i < ArraySize(sorted); i++)
   {
      SmcCurrencyInfo info;
      cs.GetCurrencyInfo(sorted[i], info);
      Print("#", info.rank, " ", info.name,
            " Str: ", DoubleToString(info.strength, 2),
            " Mom: ", DoubleToString(info.momentum, 2));
   }

   // 最強 vs 最弱ペア
   Print("Best Pair: ", cs.GetBestPair());

   // 現在のシンボルが強弱一致しているか
   string base = StringSubstr(_Symbol, 0, 3);
   string quote = StringSubstr(_Symbol, 3, 3);
   if(cs.IsStrongVsWeak(base, quote))
      Print(base, " is stronger than ", quote, " → BUY bias");
}
```

---

## VIXによるリスク管理

```cpp
#include <SMC/Analysis/VIXCalculator.mqh>

CSmcVIXCalculator vix;

void OnStart()
{
   vix.Init(_Symbol, PERIOD_H1, false, 20, PERIOD_D1);
   vix.Update();

   Print("VIX: ", DoubleToString(vix.GetVIX(), 2));
   Print("Level: ", vix.GetVIXLevelName());
   Print("Trend: ", vix.GetVIXTrend() > 0 ? "Rising" :
                     vix.GetVIXTrend() < 0 ? "Falling" : "Flat");

   // リスク調整
   double baseLot = 0.1;
   double adjustedLot = baseLot * vix.GetLotMultiplier();
   Print("Base Lot: ", baseLot, " → Adjusted: ", adjustedLot);

   double baseSL = 20.0;  // pips
   double adjustedSL = baseSL * vix.GetSLMultiplier();
   Print("Base SL: ", baseSL, " → Adjusted: ", adjustedSL);

   // エントリー可否
   Print("Entry Allowed: ", vix.IsEntryAllowed());

   // パーセンタイル
   Print("VIX Percentile: ", DoubleToString(vix.GetPercentile(252), 1), "%");
}
```

---

## ONNX推論の組み込み

```cpp
#include <SMC/Utils/OnnxWrapper.mqh>
#include <SMC/SmcManager.mqh>

CSmcOnnxWrapper onnx;
CSmcManager *smc;

int OnInit()
{
   smc = new CSmcManager();
   smc.Init(_Symbol, _Period, false, false, false);

   if(!onnx.LoadFromFile("models\\trend_classifier.onnx"))
      return INIT_FAILED;

   onnx.SetInputShape(30);
   onnx.SetOutputShape(3);
   onnx.LoadScaler("models\\trend_classifier_mean.npy",
                    "models\\trend_classifier_scale.npy");

   return INIT_SUCCEEDED;
}

void OnTick()
{
   smc.Update();

   // 特徴量を構築
   float features[];
   ArrayResize(features, 30);
   // ... SMCモジュールから特徴量を抽出して features[] に設定 ...

   // スケーリング + 予測
   onnx.ApplyScaler(features);
   int prediction = onnx.PredictClass(features);

   // SMCシグナルとML予測の一致を確認
   ENUM_ENTRY_SIGNAL smcSignal = smc.GetSignal();
   if(smcSignal == SIGNAL_BUY && prediction == 2)       // Bullish
      Print("Strong BUY: SMC + ML agree");
   else if(smcSignal == SIGNAL_SELL && prediction == 0)  // Bearish
      Print("Strong SELL: SMC + ML agree");
}

void OnDeinit(const int reason)
{
   onnx.Release();
   if(smc) { smc.Clean(); delete smc; }
}
```

---

## ロギング活用

```cpp
#include <SMC/Utils/Logger.mqh>

int OnInit()
{
   CSmcLogger::SetLevel(LOG_DEBUG);
   CSmcLogger::SetModule("MyEA");
   CSmcLogger::EnableFileLog("MyEA_log.txt");

   CSmcLogger::Info("EA initialized");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   CSmcLogger::Debug("Processing tick...");
   // ... 処理 ...
   CSmcLogger::Warn("Spread is high: 5.2 pips");
}

void OnDeinit(const int reason)
{
   CSmcLogger::Info("EA deinitialized");
   CSmcLogger::DisableFileLog();
}
```

**出力例:**
```
[INFO][MyEA][14:30:05] EA initialized
[DEBUG][MyEA][14:30:06] Processing tick...
[WARN][MyEA][14:30:06] Spread is high: 5.2 pips
```

---

## データエクスポート

### ML学習用CSVエクスポート

```cpp
#include <SMC/Utils/DataExporter.mqh>

input string InpSymbol = "EURUSD";
input int    InpBars   = 50000;

void OnStart()
{
   // 基本OHLCVデータ
   CSmcDataExporter::ExportOHLCV(InpSymbol, _Period, InpBars,
                                  InpSymbol + "_ohlcv.csv");

   // テクニカル指標付き
   CSmcDataExporter::ExportWithIndicators(InpSymbol, _Period, InpBars,
                                           InpSymbol + "_indicators.csv");

   Print("Export completed!");
}
```
