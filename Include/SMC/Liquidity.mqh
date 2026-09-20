//+------------------------------------------------------------------+
//|                                                    Liquidity.mqh |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_LIQUIDITY_MQH__
#define __SMC_LIQUIDITY_MQH__

#include "SwingPoints.mqh"

//+------------------------------------------------------------------+
//| CSmcLiquidity - 流動性分析                                         |
//|                                                                    |
//| Equal Highs/Lows、流動性プール、流動性スイープを検出。            |
//+------------------------------------------------------------------+
class CSmcLiquidity : public CSmcBase
  {
private:
   CSmcSwingPoints  *m_swingPoints;
   bool              m_ownSwing;

   //--- 設定
   double            m_tolerancePips;   // Equal H/L の許容範囲 (Pips)
   int               m_minTouches;      // 流動性プールの最小タッチ数
   int               m_maxLevels;       // 最大レベル数

   //--- データ
   SmcLiquidityLevel m_levels[];
   int               m_levelCount;
   datetime          m_confirmedTimes[]; // First bar where the level was available

   //--- 描画色
   color             m_colorEQH;
   color             m_colorEQL;
   color             m_colorSweep;

public:
                     CSmcLiquidity();
                    ~CSmcLiquidity();

   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false,
                          CSmcSwingPoints *swingPoints = NULL,
                          const double tolerancePips = 3.0);
   virtual bool      Update();
   virtual void      Clean();

   //--- 設定
   void              SetMaxLevels(const int maxRecords)
     { m_maxLevels = MathMax(1, maxRecords); m_levelCount = 0; }
   void              SetTolerancePips(const double pips) { m_tolerancePips = MathMax(0.0, pips); }
   void              SetMinTouches(const int touches) { m_minTouches = MathMax(2, touches); }

   //--- レベル取得
   int               GetLevelCount() const { return m_levelCount; }
   datetime          GetLevelConfirmedTime(const int index) const
     { return index >= 0 && index < m_levelCount ? m_confirmedTimes[index] : 0; }
   bool              GetLevel(const int index, SmcLiquidityLevel &level) const;

   //--- Equal Highs/Lows
   int               GetEqualHighsCount() const;
   int               GetEqualLowsCount() const;
   bool              GetNearestEqualHigh(const double price, SmcLiquidityLevel &level) const;
   bool              GetNearestEqualLow(const double price, SmcLiquidityLevel &level) const;

   //--- 流動性スイープ
   bool              IsLiquiditySweep(const ENUM_LIQUIDITY_TYPE type) const;
   bool              HasRecentSweep(const int withinBars = 5) const;
   bool              HasRecentSweep(const ENUM_LIQUIDITY_TYPE type, const int withinBars) const;

   //--- SwingPoints参照
   CSmcSwingPoints  *SwingPoints() { return m_swingPoints; }

private:
   void              DetectEqualHighsLows();
   void              DetectLiquidityPools();
   void              AddSwingTouch(const SmcSwingPoint &point, const datetime confirmedTime);
   void              DetectSweeps(const int barIndex);
   void              DrawLiquidity();
  };

//+------------------------------------------------------------------+
CSmcLiquidity::CSmcLiquidity()
   : m_swingPoints(NULL)
   , m_ownSwing(false)
   , m_tolerancePips(3.0)
   , m_minTouches(2)
   , m_maxLevels(30)
   , m_levelCount(0)
   , m_colorEQH(clrMagenta)
   , m_colorEQL(clrCyan)
   , m_colorSweep(clrYellow)
  {
  }

CSmcLiquidity::~CSmcLiquidity()
  {
   if(m_ownSwing && m_swingPoints != NULL)
     {
      delete m_swingPoints;
      m_swingPoints = NULL;
     }
   ArrayFree(m_levels);
   ArrayFree(m_confirmedTimes);
  }

//+------------------------------------------------------------------+
bool CSmcLiquidity::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                         const bool enableDraw, CSmcSwingPoints *swingPoints,
                         const double tolerancePips)
  {
   m_levelCount = 0;
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   SetModulePrefix("LQ");
   m_tolerancePips = MathMax(0.0, tolerancePips);
   m_levelCount = 0;

   bool keepOwned = m_ownSwing && m_swingPoints == swingPoints && swingPoints != NULL;
   if(m_ownSwing && m_swingPoints != NULL && m_swingPoints != swingPoints)
     {
      delete m_swingPoints;
      m_swingPoints = NULL;
      m_ownSwing = false;
     }

   if(swingPoints != NULL)
     {
      m_swingPoints = swingPoints;
      m_ownSwing    = keepOwned;
     }
   else
     {
      m_swingPoints = new CSmcSwingPoints();
      if(!m_swingPoints.Init(symbol, timeframe, false))
        {
         delete m_swingPoints;
         m_swingPoints = NULL;
         return false;
        }
      m_ownSwing = true;
     }

   ArrayResize(m_levels, m_maxLevels);
   ArrayResize(m_confirmedTimes, m_maxLevels);
   return true;
  }

//+------------------------------------------------------------------+
bool CSmcLiquidity::Update()
  {
   if(m_enableDraw)
      CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   m_levelCount = 0;
   if(!m_initialized || m_swingPoints == NULL)
      return false;
   if(!PrepareRates(m_swingPoints.GetLookbackBars() + 2 * m_swingPoints.GetSwingPeriod() + 2))
      return false;
   if(RatesCount() < m_swingPoints.GetSwingPeriod() * 2 + 2)
      return false;

   if(m_ownSwing)
     {
      m_swingPoints.SetRates(m_rates);
      if(!m_swingPoints.Update())
         return false;
     }

   DetectEqualHighsLows();
   DetectLiquidityPools();

   if(m_enableDraw)
      DrawLiquidity();

   return true;
  }

void CSmcLiquidity::Clean()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   if(m_ownSwing && m_swingPoints != NULL)
      m_swingPoints.Clean();
   CSmcDrawing::Redraw();
  }

//+------------------------------------------------------------------+
bool CSmcLiquidity::GetLevel(const int index, SmcLiquidityLevel &level) const
  {
   if(index < 0 || index >= m_levelCount)
      return false;
   level = m_levels[index];
   return true;
  }

int CSmcLiquidity::GetEqualHighsCount() const
  {
   int c = 0;
   for(int i = 0; i < m_levelCount; i++)
      if(m_levels[i].type == LIQ_EQUAL_HIGHS)
         c++;
   return c;
  }

int CSmcLiquidity::GetEqualLowsCount() const
  {
   int c = 0;
   for(int i = 0; i < m_levelCount; i++)
      if(m_levels[i].type == LIQ_EQUAL_LOWS)
         c++;
   return c;
  }

//+------------------------------------------------------------------+
bool CSmcLiquidity::GetNearestEqualHigh(const double price, SmcLiquidityLevel &level) const
  {
   double minDist = DBL_MAX;
   bool found     = false;

   for(int i = 0; i < m_levelCount; i++)
     {
      if(m_levels[i].type != LIQ_EQUAL_HIGHS || !m_levels[i].isValid)
         continue;
      double dist = MathAbs(price - m_levels[i].price);
      if(dist < minDist)
        {
         minDist = dist;
         level   = m_levels[i];
         found   = true;
        }
     }
   return found;
  }

bool CSmcLiquidity::GetNearestEqualLow(const double price, SmcLiquidityLevel &level) const
  {
   double minDist = DBL_MAX;
   bool found     = false;

   for(int i = 0; i < m_levelCount; i++)
     {
      if(m_levels[i].type != LIQ_EQUAL_LOWS || !m_levels[i].isValid)
         continue;
      double dist = MathAbs(price - m_levels[i].price);
      if(dist < minDist)
        {
         minDist = dist;
         level   = m_levels[i];
         found   = true;
        }
     }
   return found;
  }

//+------------------------------------------------------------------+
bool CSmcLiquidity::IsLiquiditySweep(const ENUM_LIQUIDITY_TYPE type) const
  {
   for(int i = 0; i < m_levelCount; i++)
      if(m_levels[i].type == type && m_levels[i].isSweep)
         return true;
   return false;
  }

bool CSmcLiquidity::HasRecentSweep(const int withinBars) const
  {
   if(withinBars < 1 || RatesCount() < 2)
      return false;
   datetime threshold = Time(MathMin(withinBars, RatesCount() - 1));
   for(int i = 0; i < m_levelCount; i++)
      if(m_levels[i].isSweep && m_levels[i].sweepTime >= threshold)
         return true;
   return false;
  }

bool CSmcLiquidity::HasRecentSweep(const ENUM_LIQUIDITY_TYPE type, const int withinBars) const
  {
   if(withinBars < 1 || RatesCount() < 2)
      return false;
   datetime threshold = Time(MathMin(withinBars, RatesCount() - 1));
   for(int i = 0; i < m_levelCount; i++)
      if(m_levels[i].isSweep && m_levels[i].type == type &&
         m_levels[i].sweepTime >= threshold)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Equal Highs/Lows検出                                               |
//+------------------------------------------------------------------+
void CSmcLiquidity::DetectEqualHighsLows()
  {
   // Replay raw pivots across the configured lookback. The SwingPoints
   // getter retention limit is a presentation limit, not replay input.
   // Results retain only this finite lookback; older formations age out.
   int period = m_swingPoints.GetSwingPeriod();
   int limit = MathMin(m_swingPoints.GetLookbackBars() + 1, RatesCount() - period);
   int capacity = MathMax(0, 2 * (limit - period));
   ArrayResize(m_levels, capacity);
   ArrayResize(m_confirmedTimes, capacity);

   for(int bar = limit - 1 - period; bar >= 1; bar--)
     {
      // New levels created at this close cannot be swept by that same bar.
      DetectSweeps(bar);
      int pivot = bar + period;
      double pivotHigh = High(pivot);
      double pivotLow = Low(pivot);
      bool isHigh = pivotHigh != 0;
      bool isLow = pivotLow != 0;
      for(int offset = 1; offset <= period; offset++)
        {
         if(High(pivot + offset) >= pivotHigh || High(pivot - offset) >= pivotHigh)
            isHigh = false;
         if(Low(pivot + offset) <= pivotLow || Low(pivot - offset) <= pivotLow)
            isLow = false;
        }
      SmcSwingPoint point;
      point.Init();
      point.time = Time(pivot);
      point.barIndex = pivot;
      point.strength = period;
      point.isValid = true;
      if(isHigh)
        {
         point.price = pivotHigh;
         point.isHigh = true;
         AddSwingTouch(point, Time(bar));
        }
      if(isLow)
        {
         point.price = pivotLow;
         point.isHigh = false;
         AddSwingTouch(point, Time(bar));
        }
     }
  }

//+------------------------------------------------------------------+
//| Each confirmed swing contributes once to one unswept level.       |
//+------------------------------------------------------------------+
void CSmcLiquidity::AddSwingTouch(const SmcSwingPoint &point, const datetime confirmedTime)
  {
   double tolerance = PipsToPrice(m_tolerancePips);
   int nearest = -1;
   double distance = DBL_MAX;
   for(int i = 0; i < m_levelCount; i++)
     {
      if(m_levels[i].IsHighSide() != point.isHigh || m_levels[i].isSweep)
         continue;
      double candidate = MathAbs(point.price - m_levels[i].price);
      if(candidate <= tolerance && candidate < distance)
        {
         nearest = i;
         distance = candidate;
        }
     }

   if(nearest < 0)
     {
      nearest = m_levelCount++;
      m_levels[nearest].Init();
      m_levels[nearest].price = point.price;
      m_levels[nearest].firstTime = point.time;
      m_levels[nearest].lastTime = point.time;
      m_levels[nearest].touchCount = 1;
      m_levels[nearest].type = point.isHigh ? LIQ_EQUAL_HIGHS : LIQ_EQUAL_LOWS;
      m_confirmedTimes[nearest] = 0;
      return;
     }

   // Defensive deduplication keeps each pivot time unique within its side.
   if(point.time <= m_levels[nearest].lastTime)
      return;
   int touches = m_levels[nearest].touchCount;
   // Freeze the price once tradable: later touches must not rewrite a
   // historical sweep threshold or the level's formation time.
   if(touches < m_minTouches)
      m_levels[nearest].price = (m_levels[nearest].price * touches + point.price) / (touches + 1);
   m_levels[nearest].touchCount++;
   m_levels[nearest].lastTime = point.time;
   if(m_levels[nearest].touchCount == m_minTouches)
     {
      m_levels[nearest].isValid = true;
      m_confirmedTimes[nearest] = confirmedTime;
     }
  }

//+------------------------------------------------------------------+
//| Publish completed levels, newest formation first.                 |
//+------------------------------------------------------------------+
void CSmcLiquidity::DetectLiquidityPools()
  {
   int count = 0;
   for(int i = 0; i < m_levelCount; i++)
     {
      if(m_levels[i].touchCount < m_minTouches)
         continue;
      if(!m_levels[i].isSweep && m_levels[i].touchCount >= MathMax(3, m_minTouches))
         m_levels[i].type = m_levels[i].IsHighSide() ? LIQ_POOL_HIGH : LIQ_POOL_LOW;
      m_levels[count] = m_levels[i];
      m_confirmedTimes[count] = m_confirmedTimes[i];
      count++;
     }
   m_levelCount = count;
   for(int i = 0; i < m_levelCount - 1; i++)
      for(int j = i + 1; j < m_levelCount; j++)
         if(m_confirmedTimes[j] > m_confirmedTimes[i])
           {
            SmcLiquidityLevel level = m_levels[i];
            m_levels[i] = m_levels[j];
            m_levels[j] = level;
            datetime confirmed = m_confirmedTimes[i];
            m_confirmedTimes[i] = m_confirmedTimes[j];
            m_confirmedTimes[j] = confirmed;
           }
   m_levelCount = MathMin(m_levelCount, m_maxLevels);
  }

//+------------------------------------------------------------------+
//| Sweeps are terminal and can only follow confirmed formation.      |
//+------------------------------------------------------------------+
void CSmcLiquidity::DetectSweeps(const int barIndex)
  {
   double minimumBreak = m_tickSize > 0 ? m_tickSize : m_point;
   datetime barTime = Time(barIndex);
   for(int i = 0; i < m_levelCount; i++)
     {
      if(!m_levels[i].isValid || m_levels[i].isSweep ||
         barTime <= m_confirmedTimes[i])
         continue;
      bool highSide = m_levels[i].IsHighSide();
      bool swept = highSide ?
         (High(barIndex) >= NormalizePrice(m_levels[i].price + minimumBreak) && Close(barIndex) < m_levels[i].price) :
         (Low(barIndex) <= NormalizePrice(m_levels[i].price - minimumBreak) && Close(barIndex) > m_levels[i].price);
      if(swept)
        {
         m_levels[i].isSweep = true;
         m_levels[i].sweepTime = barTime;
         m_levels[i].type = highSide ? LIQ_SWEEP_HIGH : LIQ_SWEEP_LOW;
        }
     }
  }

//+------------------------------------------------------------------+
void CSmcLiquidity::DrawLiquidity()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);

   for(int i = 0; i < m_levelCount; i++)
     {
      if(!m_levels[i].isValid)
         continue;

      string name = m_prefix + IntegerToString(i);
      color clr;
      string txt;
      ENUM_LINE_STYLE style;

      if(m_levels[i].isSweep)
        {
         clr   = m_colorSweep;
         txt   = "SWEEP";
         style = STYLE_DASHDOT;
        }
      else if(m_levels[i].IsHighSide())
        {
         clr   = m_colorEQH;
         txt   = (m_levels[i].type == LIQ_POOL_HIGH) ? "LIQ POOL" : "EQH";
         style = STYLE_DOT;
        }
      else
        {
         clr   = m_colorEQL;
         txt   = (m_levels[i].type == LIQ_POOL_LOW) ? "LIQ POOL" : "EQL";
         style = STYLE_DOT;
        }

      CSmcDrawing::DrawHLine(name, m_levels[i].price, clr, 1, style);

      string label = m_prefix + "L_" + IntegerToString(i);
      CSmcDrawing::DrawText(label, m_levels[i].lastTime,
                            m_levels[i].price,
                            txt + " (" + IntegerToString(m_levels[i].touchCount) + "x)",
                            clr, 7);
     }

   CSmcDrawing::Redraw();
  }

#endif // __SMC_LIQUIDITY_MQH__
//+------------------------------------------------------------------+
