//+------------------------------------------------------------------+
//|                                                  TradeUtils.mqh  |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_TRADE_UTILS_MQH__
#define __SMC_TRADE_UTILS_MQH__

#include "../Core/SmcTypes.mqh"

//+------------------------------------------------------------------+
//| CSmcTradeUtils - Trading utility functions                       |
//|                                                                    |
//| Static utility methods for:                                      |
//|   - Lot size calculations (risk-based, fixed amount)             |
//|   - Spread analysis                                               |
//|   - Swap information                                              |
//|   - Trade permission checks                                       |
//+------------------------------------------------------------------+
class CSmcTradeUtils
  {
public:
   //--- Lot Calculation Methods / ロット計算メソッド
   
   //+------------------------------------------------------------------+
   //| Calculate lot size based on account balance risk percentage     |
   //| 口座残高のリスクパーセンテージに基づいてロットサイズを計算      |
   //+------------------------------------------------------------------+
   static double CalcLotByRisk(const string symbol, const double riskPercent, const double slPips)
     {
      if(riskPercent <= 0.0 || slPips <= 0.0)
         return 0.0;
      
      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(accountBalance <= 0.0)
         return 0.0;
      
      double riskAmount = accountBalance * riskPercent / 100.0;
      return CalcLotByFixedAmount(symbol, riskAmount, slPips);
     }
   
   //+------------------------------------------------------------------+
   //| Calculate lot size based on fixed dollar risk amount            |
   //| 固定ドルリスク額に基づいてロットサイズを計算                    |
   //+------------------------------------------------------------------+
   static double CalcLotByFixedAmount(const string symbol, const double amount, const double slPips)
     {
      if(amount <= 0.0 || slPips <= 0.0)
         return 0.0;
      
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      
      if(tickValue <= 0.0 || tickSize <= 0.0 || point <= 0.0)
         return 0.0;
      
      // Calculate price distance for stop loss
      // ストップロス用の価格距離を計算
      double slPrice = slPips * point * 10.0; // Assuming 1 pip = 10 points for 5-digit brokers
      if(StringFind(symbol, "JPY") >= 0 || StringFind(symbol, "XAU") >= 0)
         slPrice = slPips * point; // 3-digit brokers
      
      // Calculate lot size: riskAmount / (slPrice / tickSize * tickValue)
      // ロットサイズ計算: リスク額 / (ストップロス価格 / ティックサイズ * ティック値)
      double lotSize = amount / (slPrice / tickSize * tickValue);
      
      return NormalizeLot(symbol, lotSize);
     }
   
   //+------------------------------------------------------------------+
   //| Normalize lot size to broker's lot step, min, and max            |
   //| ブローカーのロットステップ、最小値、最大値に正規化             |
   //+------------------------------------------------------------------+
   static double NormalizeLot(const string symbol, const double lot)
     {
      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      
      if(lotStep <= 0.0)
         return 0.0;
      
      // Round to nearest lot step
      // 最も近いロットステップに丸める
      double normalizedLot = MathFloor(lot / lotStep) * lotStep;
      
      // Apply min/max constraints
      // 最小値/最大値の制約を適用
      if(normalizedLot < minLot)
         normalizedLot = minLot;
      if(normalizedLot > maxLot)
         normalizedLot = maxLot;
      
      return NormalizeDouble(normalizedLot, 2);
     }
   
   //--- Spread Analysis Methods / スプレッド分析メソッド
   
   //+------------------------------------------------------------------+
   //| Get current spread in pips                                       |
   //| 現在のスプレッドをピップ単位で取得                               |
   //+------------------------------------------------------------------+
   static double GetSpreadPips(const string symbol)
     {
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      
      if(ask <= 0.0 || bid <= 0.0 || point <= 0.0)
         return 0.0;
      
      double spread = ask - bid;
      
      // Convert to pips (1 pip = 10 points for 5-digit, 1 point for 3-digit)
      // ピップに変換（5桁通貨は1ピップ=10ポイント、3桁通貨は1ポイント）
      if(StringFind(symbol, "JPY") >= 0 || StringFind(symbol, "XAU") >= 0)
         return spread / point;
      else
         return spread / (point * 10.0);
     }
   
   //+------------------------------------------------------------------+
   //| Check if spread is within acceptable limits                      |
   //| スプレッドが許容範囲内かチェック                                 |
   //+------------------------------------------------------------------+
   static bool IsSpreadOK(const string symbol, const double maxSpreadPips)
     {
      double currentSpread = GetSpreadPips(symbol);
      return (currentSpread > 0.0 && currentSpread <= maxSpreadPips);
     }
   
   //--- Swap Information Methods / スワップ情報メソッド
   
   //+------------------------------------------------------------------+
   //| Get swap value for long positions                                |
   //| ロングポジションのスワップ値を取得                               |
   //+------------------------------------------------------------------+
   static double GetSwapLong(const string symbol)
     {
      return SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG);
     }
   
   //+------------------------------------------------------------------+
   //| Get swap value for short positions                               |
   //| ショートポジションのスワップ値を取得                             |
   //+------------------------------------------------------------------+
   static double GetSwapShort(const string symbol)
     {
      return SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT);
     }
   
   //--- Trade Permission Methods / 取引許可メソッド
   
   //+------------------------------------------------------------------+
   //| Check if trading is allowed for the symbol                       |
   //| シンボルで取引が許可されているかチェック                         |
   //+------------------------------------------------------------------+
   static bool IsTradeAllowed(const string symbol)
     {
      // Check if market is open
      // 市場が開いているかチェック
      if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE))
         return false;
      
      // Check if EA trading is allowed
      // EA取引が許可されているかチェック
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
         return false;
      
      if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
         return false;
      
      // Check if symbol is visible and selectable
      // シンボルが表示可能で選択可能かチェック
      if(!SymbolSelect(symbol, true))
         return false;
      
      // Check if there's sufficient margin
      // 十分なマージンがあるかチェック
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(freeMargin <= 0.0)
         return false;
      
      // Check if symbol is currently tradeable
      // シンボルが現在取引可能かチェック
      long tradeMode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
      if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
         return false;
      
      return true;
     }
  };

#endif // __SMC_TRADE_UTILS_MQH__
//+------------------------------------------------------------------+
