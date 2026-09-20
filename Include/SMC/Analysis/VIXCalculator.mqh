//+------------------------------------------------------------------+
//|                                                VIXCalculator.mqh |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_VIX_CALCULATOR_MQH__
#define __SMC_VIX_CALCULATOR_MQH__

#include "../Core/SmcBase.mqh"

//+------------------------------------------------------------------+
//| CSmcVIXCalculator - ボラティリティ指数計算                         |
//|                                                                    |
//| ヒストリカルボラティリティ(対数収益率の標準偏差 x sqrt(252))        |
//| による VIX相当値を算出。                                           |
//+------------------------------------------------------------------+
class CSmcVIXCalculator : public CSmcBase
  {
private:
   //--- 設定
   int               m_calcPeriod;     // 計算期間 (バー数)
   ENUM_TIMEFRAMES   m_calcTF;         // 計算タイムフレーム (default: D1)
   string            m_calcSymbol;     // VIX計算対象シンボル

   //--- 結果
   double            m_currentVIX;     // 現在のVIX値
   ENUM_VIX_LEVEL    m_currentLevel;   // 現在のレベル
   int               m_vixTrend;       // VIXトレンド (1=上昇, 0=横, -1=下降)
   double            m_prevVIX;        // 前回のVIX値
   double            m_vixHistory[];   // One value per completed calculation bar
   bool              m_ready;
   datetime          m_lastEvaluated;

   //--- レベル閾値
   double            m_threshLow;
   double            m_threshNormal;
   double            m_threshHigh;

public:
                     CSmcVIXCalculator();
                    ~CSmcVIXCalculator();

   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false,
                          const int calcPeriod = 20,
                          const ENUM_TIMEFRAMES calcTF = PERIOD_D1);
   virtual bool      Update();
   virtual void      Clean();

   //--- VIX値
   double            GetVIX()        const { return m_currentVIX; }
   bool              IsReady()       const { return m_ready; }
   ENUM_VIX_LEVEL    GetVIXLevel()   const { return m_currentLevel; }
   int               GetVIXTrend()   const { return m_vixTrend; }
   string            GetVIXLevelName() const;

   //--- トレーディング調整
   double            GetLotMultiplier()  const;
   double            GetSLMultiplier()   const;
   bool              IsEntryAllowed()    const;

   //--- 統計
   double            GetPercentile(const int period = 252) const;
   double            GetVIXMA(const int period = 10)       const;

   //--- 閾値設定
   void              SetThresholds(const double low, const double normal, const double high);

private:
   bool              Calculate();
   bool              CalcHistoricalVolatility(double &value, datetime &evaluated);
   void              ResetOutputs();
   ENUM_VIX_LEVEL    ClassifyLevel(const double vix) const;
   void              UpdateTrend();
   string            DetectVIXSymbol() const;
  };

//+------------------------------------------------------------------+
CSmcVIXCalculator::CSmcVIXCalculator()
   : m_calcPeriod(20)
   , m_calcTF(PERIOD_D1)
   , m_calcSymbol("")
   , m_currentVIX(0)
   , m_currentLevel(VIX_NORMAL)
   , m_vixTrend(0)
   , m_prevVIX(0)
   , m_ready(false)
   , m_lastEvaluated(0)
   , m_threshLow(15.0)
   , m_threshNormal(25.0)
   , m_threshHigh(35.0)
  {
  }

CSmcVIXCalculator::~CSmcVIXCalculator()
  {
   ArrayFree(m_vixHistory);
  }

//+------------------------------------------------------------------+
bool CSmcVIXCalculator::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                             const bool enableDraw, const int calcPeriod,
                             const ENUM_TIMEFRAMES calcTF)
  {
   ResetOutputs();
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   SetModulePrefix("VIX");
   m_calcPeriod = MathMax(5, calcPeriod);
   m_calcTF     = calcTF == PERIOD_CURRENT ? m_timeframe : calcTF;
   m_calcSymbol = m_symbol;

   ArrayResize(m_vixHistory, 0);

   return true;
  }

//+------------------------------------------------------------------+
void CSmcVIXCalculator::ResetOutputs()
  {
   m_currentVIX = 0;
   m_prevVIX = 0;
   m_currentLevel = VIX_NORMAL;
   m_vixTrend = 0;
   m_ready = false;
   m_lastEvaluated = 0;
   ArrayResize(m_vixHistory, 0);
  }

bool CSmcVIXCalculator::Update()
  {
   if(!m_initialized || !Calculate())
     {
      ResetOutputs();
      return false;
     }
   UpdateTrend();
   return true;
  }

void CSmcVIXCalculator::Clean()
  {
   CSmcBase::Clean();
  }

//+------------------------------------------------------------------+
string CSmcVIXCalculator::GetVIXLevelName() const
  {
   if(!m_ready)
      return "Not ready";
   switch(m_currentLevel)
     {
      case VIX_LOW:     return "Low";
      case VIX_NORMAL:  return "Normal";
      case VIX_HIGH:    return "High";
      case VIX_EXTREME: return "Extreme";
      default:          return "Unknown";
     }
  }

//+------------------------------------------------------------------+
//| ロット調整倍率                                                     |
//+------------------------------------------------------------------+
double CSmcVIXCalculator::GetLotMultiplier() const
  {
   if(!m_ready)
      return 0.0;
   switch(m_currentLevel)
     {
      case VIX_LOW:     return 1.2;   // 低ボラ: やや大きめ
      case VIX_NORMAL:  return 1.0;   // 通常: 標準
      case VIX_HIGH:    return 0.7;   // 高ボラ: 縮小
      case VIX_EXTREME: return 0.3;   // 極端: 大幅縮小
      default:          return 1.0;
     }
  }

//+------------------------------------------------------------------+
//| SL調整倍率                                                         |
//+------------------------------------------------------------------+
double CSmcVIXCalculator::GetSLMultiplier() const
  {
   if(!m_ready)
      return 0.0;
   switch(m_currentLevel)
     {
      case VIX_LOW:     return 0.8;
      case VIX_NORMAL:  return 1.0;
      case VIX_HIGH:    return 1.5;
      case VIX_EXTREME: return 2.0;
      default:          return 1.0;
     }
  }

bool CSmcVIXCalculator::IsEntryAllowed() const
  {
   return m_ready && m_currentLevel != VIX_EXTREME;
  }

//+------------------------------------------------------------------+
void CSmcVIXCalculator::SetThresholds(const double low, const double normal,
                                      const double high)
  {
   m_threshLow    = low;
   m_threshNormal = normal;
   m_threshHigh   = high;
  }

//+------------------------------------------------------------------+
bool CSmcVIXCalculator::Calculate()
  {
   double value = 0;
   datetime evaluated = 0;
   if(!CalcHistoricalVolatility(value, evaluated))
      return false;
   if(evaluated < m_lastEvaluated)
      ResetOutputs();
   int size = ArraySize(m_vixHistory);
   // Repeated updates of one closed candle never inflate history or momentum.
   if(size > 0 && evaluated == m_lastEvaluated)
     {
      m_prevVIX = size > 1 ? m_vixHistory[size - 2] : 0;
      m_vixHistory[size - 1] = value;
     }
   else
     {
      m_prevVIX = size > 0 ? m_vixHistory[size - 1] : 0;
      ArrayResize(m_vixHistory, size + 1);
      m_vixHistory[size] = value;
     }
   if(ArraySize(m_vixHistory) > 500)
     {
      double recent[];
      ArrayCopy(recent, m_vixHistory, 0, ArraySize(m_vixHistory) - 250, 250);
      ArrayCopy(m_vixHistory, recent);
      ArrayResize(m_vixHistory, 250);
     }
   m_currentVIX = value;
   m_currentLevel = ClassifyLevel(value);
   m_lastEvaluated = evaluated;
   m_ready = true;
   return true;
  }

// Requires period+1 strictly positive, finite completed closes. Zero variance
// is a valid zero result; unavailable/invalid data is an Update() failure.
// Shared primary rates are coherent only when calcTF matches the primary TF.
// The legacy default remains D1; a manager's M5 context cannot become D1 data.
// The existing annualization convention (sqrt(252)) remains unchanged.
bool CSmcVIXCalculator::CalcHistoricalVolatility(double &value, datetime &evaluated)
  {
   if(m_calcPeriod > 2147483645)
      return false; // Keep period+2 representable before any array operation.
   MqlRates rates[];
   if(m_calcTF == m_timeframe && m_ratesContextAttempted)
     {
      if(!m_ratesValid || RatesCount() < m_calcPeriod + 2)
         return false;
      ArrayCopy(rates, m_rates, 0, RatesCount() - m_calcPeriod - 2, m_calcPeriod + 1);
     }
   else
     {
      ArraySetAsSeries(rates, false);
      if(CopyRates(m_calcSymbol, m_calcTF, 1, m_calcPeriod + 1, rates) != m_calcPeriod + 1)
         return false;
     }
   double returns[];
   ArrayResize(returns, m_calcPeriod);
   double mean = 0;
   for(int i = 0; i <= m_calcPeriod; i++)
     {
      if(rates[i].time <= 0 || !MathIsValidNumber(rates[i].close) || rates[i].close <= 0 ||
         (i > 0 && rates[i].time <= rates[i - 1].time))
         return false;
      if(i == 0)
         continue;
      returns[i - 1] = MathLog(rates[i].close / rates[i - 1].close);
      if(!MathIsValidNumber(returns[i - 1]))
         return false;
      mean += returns[i - 1];
     }
   mean /= m_calcPeriod;
   double variance = 0;
   for(int i = 0; i < m_calcPeriod; i++)
      variance += (returns[i] - mean) * (returns[i] - mean);
   variance /= m_calcPeriod - 1;
   value = MathSqrt(variance) * MathSqrt(252.0) * 100.0;
   evaluated = rates[m_calcPeriod].time;
   return MathIsValidNumber(value) && value >= 0;
  }

//+------------------------------------------------------------------+
ENUM_VIX_LEVEL CSmcVIXCalculator::ClassifyLevel(const double vix) const
  {
   if(vix < m_threshLow)     return VIX_LOW;
   if(vix < m_threshNormal)  return VIX_NORMAL;
   if(vix < m_threshHigh)    return VIX_HIGH;
   return VIX_EXTREME;
  }

void CSmcVIXCalculator::UpdateTrend()
  {
   if(ArraySize(m_vixHistory) < 2)
     { m_vixTrend = 0; return; }

   double diff = m_currentVIX - m_prevVIX;
   if(diff > 0.5)       m_vixTrend = 1;
   else if(diff < -0.5) m_vixTrend = -1;
   else                  m_vixTrend = 0;
  }

//+------------------------------------------------------------------+
double CSmcVIXCalculator::GetPercentile(const int period) const
  {
   int size = ArraySize(m_vixHistory);
   if(!m_ready || period <= 0) return 0.0;
   if(size < 2) return 50.0;

   int lookback = MathMin(period, size);
   int below = 0;

   for(int i = size - lookback; i < size; i++)
      if(m_vixHistory[i] <= m_currentVIX)
         below++;

   return ((double)below / lookback) * 100.0;
  }

double CSmcVIXCalculator::GetVIXMA(const int period) const
  {
   int size = ArraySize(m_vixHistory);
   if(!m_ready || period <= 0) return 0.0;
   if(size < period) return m_currentVIX;

   double sum = 0;
   for(int i = size - period; i < size; i++)
      sum += m_vixHistory[i];

   return sum / period;
  }

#endif // __SMC_VIX_CALCULATOR_MQH__
//+------------------------------------------------------------------+
