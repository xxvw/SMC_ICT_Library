//+------------------------------------------------------------------+
//|                                                     SmcBase.mqh  |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, ICT_Library_MQ5     |
//+------------------------------------------------------------------+
#property copyright "ICT_Library_MQ5"
#property version   "1.00"
#property strict

#ifndef __SMC_BASE_MQH__
#define __SMC_BASE_MQH__

#include "SmcTypes.mqh"

//+------------------------------------------------------------------+
//| CSmcBase - 全SMCモジュールの基底クラス                            |
//|                                                                    |
//| 共通機能:                                                          |
//|   - シンボル/タイムフレーム管理                                    |
//|   - Pips ⇔ Price 変換                                             |
//|   - ATR / 平均レンジ計算                                           |
//|   - チャートオブジェクト管理                                       |
//+------------------------------------------------------------------+
class CSmcBase
  {
protected:
   string            m_symbol;        // 対象シンボル
   ENUM_TIMEFRAMES   m_timeframe;     // 対象タイムフレーム
   double            m_point;         // 1ポイントの価格
   double            m_tickSize;      // Minimum tradable price increment
   int               m_digits;        // 価格桁数
   double            m_pipSize;       // 1Pipの価格サイズ
   int               m_pipDigits;     // Pip桁数 (3桁/5桁通貨用)
   bool              m_enableDraw;    // チャート描画有効化
   string            m_prefix;        // チャートオブジェクト接頭辞
   int               m_atrHandle;     // ATRインジケーターハンドル
   bool              m_initialized;   // 初期化完了フラグ
   MqlRates          m_rates[];       // Chronological; last element is forming bar
   bool              m_sharedRates;
   // Transitional source compatibility for subclasses that have never
   // requested a captured context. An attempted capture permanently disables
   // terminal getter fallback until the next Init(), even if capture fails.
   bool              m_ratesContextAttempted;
   bool              m_ratesValid;
   string            m_instanceId;

public:
                     CSmcBase();
                    ~CSmcBase();

   //--- 初期化・更新
   virtual bool      Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false);
   virtual bool      Update() = 0;    // 純粋仮想: 各モジュールで実装
   virtual void      Clean();         // チャートオブジェクトの削除

   // Rates are copied so every detector sees one immutable evaluation context.
   void              SetRates(const MqlRates &rates[]);
   int               RatesCount() const { return ArraySize(m_rates); }

   //--- アクセサ
   string            Symbol()       const { return m_symbol; }
   ENUM_TIMEFRAMES   Timeframe()    const { return m_timeframe; }
   bool              IsInitialized() const { return m_initialized; }
   bool              IsDrawEnabled() const { return m_enableDraw; }
   void              SetDrawEnabled(const bool enabled)
     { if(!enabled) Clean(); m_enableDraw = enabled; }

protected:
   bool              PrepareRates(const int requested = 1001);
   bool              ValidateRates() const;
   void              SetModulePrefix(const string module);

   //--- Pips変換
   double            PipsToPrice(const double pips) const;
   double            PriceToPips(const double priceDistance) const;
   double            NormalizePrice(const double price) const;

   //--- ボラティリティ
   double            GetATR(const int period = 14, const int shift = 0);
   double            GetAverageRange(const int period = 20, const int shift = 0);
   double            GetAverageCandleBody(const int period = 20, const int shift = 0);

   //--- 価格データアクセス
   double            High(const int shift)  const;
   double            Low(const int shift)   const;
   double            Open(const int shift)  const;
   double            Close(const int shift) const;
   long              Volume(const int shift) const;
   datetime          Time(const int shift)  const;

   //--- ローソク足判定
   bool              IsBullishCandle(const int shift) const;
   bool              IsBearishCandle(const int shift) const;
   double            CandleBody(const int shift) const;
   double            CandleRange(const int shift) const;
   double            UpperWick(const int shift) const;
   double            LowerWick(const int shift) const;

   //--- ユーティリティ
   void              DetectPipSize();
  };

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
CSmcBase::CSmcBase()
   : m_symbol("")
   , m_timeframe(PERIOD_CURRENT)
   , m_point(0)
   , m_tickSize(0)
   , m_digits(0)
   , m_pipSize(0)
   , m_pipDigits(0)
   , m_enableDraw(false)
   , m_prefix("")
   , m_atrHandle(INVALID_HANDLE)
   , m_initialized(false)
   , m_sharedRates(false)
   , m_ratesContextAttempted(false)
   , m_ratesValid(false)
  {
   static ulong nextInstance = 0;
   nextInstance++;
   m_instanceId = IntegerToString((long)GetMicrosecondCount()) + "_" +
                  IntegerToString((long)nextInstance);
   SetModulePrefix("BASE");
  }

//+------------------------------------------------------------------+
//| Destructor                                                         |
//+------------------------------------------------------------------+
CSmcBase::~CSmcBase()
  {
   if(m_atrHandle != INVALID_HANDLE)
     {
      IndicatorRelease(m_atrHandle);
      m_atrHandle = INVALID_HANDLE;
     }
   Clean();
  }

//+------------------------------------------------------------------+
//| 初期化                                                             |
//+------------------------------------------------------------------+
bool CSmcBase::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                    const bool enableDraw)
  {
   Clean();
   m_initialized = false;
   m_sharedRates = false;
   m_ratesContextAttempted = false;
   m_ratesValid = false;
   ArrayFree(m_rates);
   if(m_atrHandle != INVALID_HANDLE)
     {
      IndicatorRelease(m_atrHandle);
      m_atrHandle = INVALID_HANDLE;
     }
   m_symbol     = (symbol == "" || symbol == "0") ? _Symbol : symbol;
   m_timeframe  = (timeframe == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : timeframe;
   m_enableDraw = enableDraw;

//--- シンボル情報取得
   m_point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   m_tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(m_tickSize <= 0) m_tickSize = m_point;

   if(m_point == 0)
     {
      Print("[SMC] Error: Invalid symbol - ", m_symbol);
      return false;
     }

//--- Pipサイズ検出
   DetectPipSize();

// Rates and volatility calculations share the same captured history.
   m_initialized = true;
   return true;
  }

//+------------------------------------------------------------------+
//| チャートオブジェクトの削除                                         |
//+------------------------------------------------------------------+
void CSmcBase::Clean()
  {
   if(m_prefix == "")
      return;

   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i);
      if(StringFind(name, m_prefix) == 0)
         ObjectDelete(0, name);
     }
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Pips値を価格差に変換                                               |
//+------------------------------------------------------------------+
double CSmcBase::PipsToPrice(const double pips) const
  {
   return NormalizeDouble(pips * m_pipSize, m_digits);
  }

//+------------------------------------------------------------------+
//| 価格差をPips値に変換                                               |
//+------------------------------------------------------------------+
double CSmcBase::PriceToPips(const double priceDistance) const
  {
   if(m_pipSize == 0)
      return 0;
   return NormalizeDouble(priceDistance / m_pipSize, 1);
  }

//+------------------------------------------------------------------+
//| 価格を正規化                                                       |
//+------------------------------------------------------------------+
double CSmcBase::NormalizePrice(const double price) const
  {
   return NormalizeDouble(price, m_digits);
  }

//+------------------------------------------------------------------+
//| ATR取得                                                            |
//+------------------------------------------------------------------+
double CSmcBase::GetATR(const int period, const int shift)
  {
   if(period <= 0 || shift < 0 ||
      (m_ratesContextAttempted && shift + period >= RatesCount()))
      return 0;
   double sum = 0;
   for(int i = shift; i < shift + period; i++)
     {
      double previousClose = Close(i + 1);
      sum += MathMax(High(i) - Low(i),
                     MathMax(MathAbs(High(i) - previousClose),
                             MathAbs(Low(i) - previousClose)));
     }
   return sum / period;
  }

//+------------------------------------------------------------------+
//| 平均レンジ (High - Low) 取得                                       |
//+------------------------------------------------------------------+
double CSmcBase::GetAverageRange(const int period, const int shift)
  {
   if(period <= 0 || shift < 0 ||
      (m_ratesContextAttempted && shift + period > RatesCount()))
      return 0;
   double sum = 0;
   int count  = 0;

   for(int i = shift; i < shift + period; i++)
     {
      double range = High(i) - Low(i);
      sum += range;
      count++;
     }

   return (count > 0) ? sum / count : 0;
  }

//+------------------------------------------------------------------+
//| 平均ローソク足実体サイズ取得                                       |
//+------------------------------------------------------------------+
double CSmcBase::GetAverageCandleBody(const int period, const int shift)
  {
   if(period <= 0 || shift < 0 ||
      (m_ratesContextAttempted && shift + period > RatesCount()))
      return 0;
   double sum = 0;
   int count  = 0;

   for(int i = shift; i < shift + period; i++)
     {
      double body = CandleBody(i);
      sum += body;
      count++;
     }

   return (count > 0) ? sum / count : 0;
  }

//+------------------------------------------------------------------+
//| 各価格データへのアクセス                                           |
//+------------------------------------------------------------------+
double CSmcBase::High(const int shift) const
  {
   if(!m_ratesContextAttempted)
      return shift >= 0 ? iHigh(m_symbol, m_timeframe, shift) : 0;
   int index = RatesCount() - 1 - shift;
   return (shift >= 0 && index >= 0 && index < RatesCount()) ? m_rates[index].high : 0;
  }

double CSmcBase::Low(const int shift) const
  {
   if(!m_ratesContextAttempted)
      return shift >= 0 ? iLow(m_symbol, m_timeframe, shift) : 0;
   int index = RatesCount() - 1 - shift;
   return (shift >= 0 && index >= 0 && index < RatesCount()) ? m_rates[index].low : 0;
  }

double CSmcBase::Open(const int shift) const
  {
   if(!m_ratesContextAttempted)
      return shift >= 0 ? iOpen(m_symbol, m_timeframe, shift) : 0;
   int index = RatesCount() - 1 - shift;
   return (shift >= 0 && index >= 0 && index < RatesCount()) ? m_rates[index].open : 0;
  }

double CSmcBase::Close(const int shift) const
  {
   if(!m_ratesContextAttempted)
      return shift >= 0 ? iClose(m_symbol, m_timeframe, shift) : 0;
   int index = RatesCount() - 1 - shift;
   return (shift >= 0 && index >= 0 && index < RatesCount()) ? m_rates[index].close : 0;
  }

long CSmcBase::Volume(const int shift) const
  {
   if(!m_ratesContextAttempted)
      return shift >= 0 ? iVolume(m_symbol, m_timeframe, shift) : 0;
   int index = RatesCount() - 1 - shift;
   return (shift >= 0 && index >= 0 && index < RatesCount()) ? m_rates[index].tick_volume : 0;
  }

datetime CSmcBase::Time(const int shift) const
  {
   if(!m_ratesContextAttempted)
      return shift >= 0 ? iTime(m_symbol, m_timeframe, shift) : 0;
   int index = RatesCount() - 1 - shift;
   return (shift >= 0 && index >= 0 && index < RatesCount()) ? m_rates[index].time : 0;
  }

//+------------------------------------------------------------------+
//| ローソク足判定                                                     |
//+------------------------------------------------------------------+
bool CSmcBase::IsBullishCandle(const int shift) const
  {
   return Close(shift) > Open(shift);
  }

bool CSmcBase::IsBearishCandle(const int shift) const
  {
   return Close(shift) < Open(shift);
  }

double CSmcBase::CandleBody(const int shift) const
  {
   return MathAbs(Close(shift) - Open(shift));
  }

double CSmcBase::CandleRange(const int shift) const
  {
   return High(shift) - Low(shift);
  }

double CSmcBase::UpperWick(const int shift) const
  {
   return High(shift) - MathMax(Open(shift), Close(shift));
  }

double CSmcBase::LowerWick(const int shift) const
  {
   return MathMin(Open(shift), Close(shift)) - Low(shift);
  }

//+------------------------------------------------------------------+
//| Pipサイズ自動検出                                                  |
//|                                                                    |
//| FX 5桁: point=0.00001, pipSize=0.0001                              |
//| FX 3桁: point=0.001,   pipSize=0.01                                |
//| Gold:   point=0.01,    pipSize=0.1 (or 1.0 depending on broker)   |
//| Index:  point=0.01,    pipSize=1.0                                 |
//+------------------------------------------------------------------+
void CSmcBase::DetectPipSize()
  {
//--- FX ペアの場合 (5桁 or 3桁)
   if(m_digits == 5 || m_digits == 3)
     {
      m_pipSize   = m_point * 10;
      m_pipDigits = m_digits - 1;
     }
//--- FX ペア (4桁 or 2桁)
   else if(m_digits == 4 || m_digits == 2)
     {
      m_pipSize   = m_point;
      m_pipDigits = m_digits;
     }
//--- ゴールド / 指数 (1桁 or 0桁)
   else
     {
      m_pipSize   = m_point * 10;
      m_pipDigits = MathMax(0, m_digits - 1);
     }
  }

//+------------------------------------------------------------------+
//| Shared chronological input, or one terminal read for standalone use |
//+------------------------------------------------------------------+
void CSmcBase::SetRates(const MqlRates &rates[])
  {
   m_ratesContextAttempted = true;
   ArrayFree(m_rates);
   ArrayCopy(m_rates, rates);
   ArraySetAsSeries(m_rates, false);
   m_sharedRates = true;
   m_ratesValid = ValidateRates();
  }

bool CSmcBase::PrepareRates(const int requested)
  {
   m_ratesContextAttempted = true;
   if(m_sharedRates)
      return m_ratesValid && RatesCount() >= 2;
   ArrayFree(m_rates);
   ArraySetAsSeries(m_rates, false);
   int copied = CopyRates(m_symbol, m_timeframe, 0, MathMax(2, requested), m_rates);
   m_ratesValid = copied >= 2 && ValidateRates();
   return m_ratesValid;
  }

bool CSmcBase::ValidateRates() const
  {
   for(int i = 0; i < RatesCount(); i++)
     {
      if(m_rates[i].time <= 0 ||
         (i > 0 && m_rates[i].time <= m_rates[i - 1].time) ||
         !MathIsValidNumber(m_rates[i].open) || !MathIsValidNumber(m_rates[i].high) ||
         !MathIsValidNumber(m_rates[i].low) || !MathIsValidNumber(m_rates[i].close) ||
         m_rates[i].high < MathMax(m_rates[i].open, m_rates[i].close) ||
         m_rates[i].low > MathMin(m_rates[i].open, m_rates[i].close))
         return false;
     }
   return RatesCount() >= 2;
  }

void CSmcBase::SetModulePrefix(const string module)
  {
   m_prefix = "SMC_" + module + "_" + IntegerToString(ChartID()) + "_" +
              m_instanceId + "_";
  }

#endif // __SMC_BASE_MQH__
//+------------------------------------------------------------------+
