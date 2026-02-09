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
   void              SetTolerancePips(const double pips) { m_tolerancePips = pips; }
   void              SetMinTouches(const int touches) { m_minTouches = touches; }

   //--- レベル取得
   int               GetLevelCount() const { return m_levelCount; }
   bool              GetLevel(const int index, SmcLiquidityLevel &level) const;

   //--- Equal Highs/Lows
   int               GetEqualHighsCount() const;
   int               GetEqualLowsCount() const;
   bool              GetNearestEqualHigh(const double price, SmcLiquidityLevel &level) const;
   bool              GetNearestEqualLow(const double price, SmcLiquidityLevel &level) const;

   //--- 流動性スイープ
   bool              IsLiquiditySweep(const ENUM_LIQUIDITY_TYPE type) const;
   bool              HasRecentSweep(const int withinBars = 5) const;

   //--- SwingPoints参照
   CSmcSwingPoints  *SwingPoints() { return m_swingPoints; }

private:
   void              DetectEqualHighsLows();
   void              DetectLiquidityPools();
   void              DetectSweeps();
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
  }

//+------------------------------------------------------------------+
bool CSmcLiquidity::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                         const bool enableDraw, CSmcSwingPoints *swingPoints,
                         const double tolerancePips)
  {
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   m_prefix         = "SMC_LIQ_";
   m_tolerancePips  = tolerancePips;

   if(swingPoints != NULL)
     {
      m_swingPoints = swingPoints;
      m_ownSwing    = false;
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
   return true;
  }

//+------------------------------------------------------------------+
bool CSmcLiquidity::Update()
  {
   if(!m_initialized || m_swingPoints == NULL)
      return false;

   if(m_ownSwing)
      m_swingPoints.Update();

   m_levelCount = 0;

   DetectEqualHighsLows();
   DetectLiquidityPools();
   DetectSweeps();

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
   datetime threshold = Time(withinBars);
   for(int i = 0; i < m_levelCount; i++)
      if(m_levels[i].isSweep && m_levels[i].sweepTime >= threshold)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Equal Highs/Lows検出                                               |
//+------------------------------------------------------------------+
void CSmcLiquidity::DetectEqualHighsLows()
  {
   double tolerance = PipsToPrice(m_tolerancePips);
   int highCount    = m_swingPoints.GetHighCount();
   int lowCount     = m_swingPoints.GetLowCount();

//--- Equal Highs検出
   for(int i = 0; i < highCount - 1 && m_levelCount < m_maxLevels; i++)
     {
      SmcSwingPoint sp1;
      m_swingPoints.GetSwingHigh(i, sp1);

      for(int j = i + 1; j < highCount; j++)
        {
         SmcSwingPoint sp2;
         m_swingPoints.GetSwingHigh(j, sp2);

         if(MathAbs(sp1.price - sp2.price) <= tolerance)
           {
            m_levels[m_levelCount].Init();
            m_levels[m_levelCount].price      = (sp1.price + sp2.price) / 2.0;
            m_levels[m_levelCount].firstTime   = sp2.time;
            m_levels[m_levelCount].lastTime    = sp1.time;
            m_levels[m_levelCount].touchCount  = 2;
            m_levels[m_levelCount].type        = LIQ_EQUAL_HIGHS;
            m_levels[m_levelCount].isValid     = true;
            m_levelCount++;
            break;
           }
        }
     }

//--- Equal Lows検出
   for(int i = 0; i < lowCount - 1 && m_levelCount < m_maxLevels; i++)
     {
      SmcSwingPoint sp1;
      m_swingPoints.GetSwingLow(i, sp1);

      for(int j = i + 1; j < lowCount; j++)
        {
         SmcSwingPoint sp2;
         m_swingPoints.GetSwingLow(j, sp2);

         if(MathAbs(sp1.price - sp2.price) <= tolerance)
           {
            m_levels[m_levelCount].Init();
            m_levels[m_levelCount].price      = (sp1.price + sp2.price) / 2.0;
            m_levels[m_levelCount].firstTime   = sp2.time;
            m_levels[m_levelCount].lastTime    = sp1.time;
            m_levels[m_levelCount].touchCount  = 2;
            m_levels[m_levelCount].type        = LIQ_EQUAL_LOWS;
            m_levels[m_levelCount].isValid     = true;
            m_levelCount++;
            break;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| 流動性プール検出                                                   |
//+------------------------------------------------------------------+
void CSmcLiquidity::DetectLiquidityPools()
  {
//--- 既存のEqual H/Lに追加タッチをカウント
   double tolerance = PipsToPrice(m_tolerancePips);

   for(int i = 0; i < m_levelCount; i++)
     {
      if(!m_levels[i].isValid)
         continue;

      int totalCount = (m_levels[i].IsHighSide()) ?
                       m_swingPoints.GetHighCount() : m_swingPoints.GetLowCount();

      for(int j = 0; j < totalCount; j++)
        {
         SmcSwingPoint sp;
         if(m_levels[i].IsHighSide())
            m_swingPoints.GetSwingHigh(j, sp);
         else
            m_swingPoints.GetSwingLow(j, sp);

         if(MathAbs(sp.price - m_levels[i].price) <= tolerance)
           {
            m_levels[i].touchCount++;
            if(sp.time > m_levels[i].lastTime)
               m_levels[i].lastTime = sp.time;
           }
        }

      //--- 3回以上タッチでプールに昇格
      if(m_levels[i].touchCount >= 3)
        {
         if(m_levels[i].type == LIQ_EQUAL_HIGHS)
            m_levels[i].type = LIQ_POOL_HIGH;
         else if(m_levels[i].type == LIQ_EQUAL_LOWS)
            m_levels[i].type = LIQ_POOL_LOW;
        }
     }
  }

//+------------------------------------------------------------------+
//| 流動性スイープ検出                                                 |
//+------------------------------------------------------------------+
void CSmcLiquidity::DetectSweeps()
  {
   double tolerance = PipsToPrice(m_tolerancePips);

   for(int i = 0; i < m_levelCount; i++)
     {
      if(!m_levels[i].isValid || m_levels[i].isSweep)
         continue;

      //--- 直近数バーでレベルを超えて反転したか
      for(int j = 0; j < 5; j++)
        {
         if(m_levels[i].IsHighSide())
           {
            //--- 高値がレベルを超えた後にクローズがレベル以下
            if(High(j) > m_levels[i].price + tolerance &&
               Close(j) < m_levels[i].price)
              {
               m_levels[i].isSweep   = true;
               m_levels[i].sweepTime = Time(j);
               m_levels[i].type      = LIQ_SWEEP_HIGH;
               break;
              }
           }
         else
           {
            //--- 安値がレベルを下回った後にクローズがレベル以上
            if(Low(j) < m_levels[i].price - tolerance &&
               Close(j) > m_levels[i].price)
              {
               m_levels[i].isSweep   = true;
               m_levels[i].sweepTime = Time(j);
               m_levels[i].type      = LIQ_SWEEP_LOW;
               break;
              }
           }
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
