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
   double            m_vixHistory[];   // VIX履歴

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
   void              Calculate();
   double            CalcHistoricalVolatility();
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
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   m_prefix     = "SMC_VIX_";
   m_calcPeriod = MathMax(5, calcPeriod);
   m_calcTF     = calcTF;
   m_calcSymbol = symbol;

   ArrayResize(m_vixHistory, 0);

   return true;
  }

//+------------------------------------------------------------------+
bool CSmcVIXCalculator::Update()
  {
   if(!m_initialized)
      return false;

   m_prevVIX = m_currentVIX;
   Calculate();
   UpdateTrend();

   return true;
  }

void CSmcVIXCalculator::Clean()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   CSmcDrawing::Redraw();
  }

//+------------------------------------------------------------------+
string CSmcVIXCalculator::GetVIXLevelName() const
  {
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
   return m_currentLevel != VIX_EXTREME;
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
void CSmcVIXCalculator::Calculate()
  {
   m_currentVIX   = CalcHistoricalVolatility();
   m_currentLevel = ClassifyLevel(m_currentVIX);

//--- 履歴追加
   int size = ArraySize(m_vixHistory);
   ArrayResize(m_vixHistory, size + 1);
   m_vixHistory[size] = m_currentVIX;

//--- 履歴上限
   if(ArraySize(m_vixHistory) > 500)
     {
      int newSize = 250;
      double temp[];
      ArrayCopy(temp, m_vixHistory, 0, ArraySize(m_vixHistory) - newSize, newSize);
      ArrayCopy(m_vixHistory, temp);
      ArrayResize(m_vixHistory, newSize);
     }
  }

//+------------------------------------------------------------------+
//| ヒストリカルボラティリティ計算                                     |
//|                                                                    |
//| σ_ann = σ_daily × √252                                           |
//| σ_daily = StdDev(ln(Close[i]/Close[i+1]))                        |
//+------------------------------------------------------------------+
double CSmcVIXCalculator::CalcHistoricalVolatility()
  {
   double returns[];
   ArrayResize(returns, m_calcPeriod);

   for(int i = 0; i < m_calcPeriod; i++)
     {
      double close0 = iClose(m_calcSymbol, m_calcTF, i);
      double close1 = iClose(m_calcSymbol, m_calcTF, i + 1);
      if(close0 == 0 || close1 == 0)
         return m_currentVIX;  // フォールバック
      returns[i] = MathLog(close0 / close1);
     }

//--- 平均
   double mean = 0;
   for(int i = 0; i < m_calcPeriod; i++)
      mean += returns[i];
   mean /= m_calcPeriod;

//--- 標準偏差
   double variance = 0;
   for(int i = 0; i < m_calcPeriod; i++)
      variance += (returns[i] - mean) * (returns[i] - mean);
   variance /= (m_calcPeriod - 1);

   double dailyVol = MathSqrt(variance);

//--- 年率化 (√252 ≈ 15.87)
   double annualizedVol = dailyVol * MathSqrt(252.0) * 100.0;

   return annualizedVol;
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
   if(m_prevVIX == 0)
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
   if(size < period) return m_currentVIX;

   double sum = 0;
   for(int i = size - period; i < size; i++)
      sum += m_vixHistory[i];

   return sum / period;
  }

#endif // __SMC_VIX_CALCULATOR_MQH__
//+------------------------------------------------------------------+
