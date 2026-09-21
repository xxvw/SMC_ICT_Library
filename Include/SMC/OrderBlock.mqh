//+------------------------------------------------------------------+
//|                                                   OrderBlock.mqh |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, ICT_Library_MQ5     |
//+------------------------------------------------------------------+
#property copyright "ICT_Library_MQ5"
#property version   "1.00"
#property strict

#ifndef __SMC_ORDER_BLOCK_MQH__
#define __SMC_ORDER_BLOCK_MQH__

#include "MarketStructure.mqh"

//+------------------------------------------------------------------+
//| CSmcOrderBlock - オーダーブロック検出・管理                         |
//|                                                                    |
//| BOS/CHoCH前の最後の逆方向キャンドルをOBとして検出。               |
//| 状態管理: FRESH -> TESTED -> MITIGATED -> BROKEN                   |
//+------------------------------------------------------------------+
class CSmcOrderBlock : public CSmcBase
  {
private:
   //--- モジュール参照
   CSmcMarketStructure *m_structure;
   bool              m_ownStructure;

   //--- 設定
   int               m_lookbackBars;
   int               m_maxOBs;
   int               m_maxAge;
   double            m_minStrength;     // 最小インパルス強度倍率

   //--- データ
   SmcZone           m_bullishOBs[];
   SmcZone           m_bearishOBs[];
   int               m_bullishCount;
   int               m_bearishCount;

   //--- 描画色
   color             m_colorBullish;
   color             m_colorBearish;

public:
                     CSmcOrderBlock();
                    ~CSmcOrderBlock();

   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false,
                          CSmcMarketStructure *structure = NULL);
   virtual bool      Update();
   virtual void      Clean();

   //--- 設定
   void              SetEvaluationLimits(const int lookbackBars, const int maxRecords)
     {
      m_lookbackBars = MathMax(1, lookbackBars);
      m_maxOBs = MathMax(1, maxRecords);
      ArrayResize(m_bullishOBs, m_maxOBs);
      ArrayResize(m_bearishOBs, m_maxOBs);
      m_bullishCount = 0;
      m_bearishCount = 0;
     }
   void              SetMaxAge(const int age) { m_maxAge = MathMax(0, age); }
   void              SetMinStrength(const double str) { m_minStrength = str; }

   //--- Bullish OB
   int               GetBullishCount() const { return m_bullishCount; }
   bool              GetBullishOB(const int index, SmcZone &ob) const;
   bool              GetNearestBullishOB(const double price, SmcZone &ob) const;

   //--- Bearish OB
   int               GetBearishCount() const { return m_bearishCount; }
   bool              GetBearishOB(const int index, SmcZone &ob) const;
   bool              GetNearestBearishOB(const double price, SmcZone &ob) const;

   //--- ユーティリティ
   int               GetFreshBullishCount() const;
   int               GetFreshBearishCount() const;
   double            GetStopLossForBuy(const SmcZone &ob) const;
   double            GetStopLossForSell(const SmcZone &ob) const;

   //--- 構造参照
   CSmcMarketStructure *Structure() { return m_structure; }

private:
   void              DetectOrderBlocks();
   void              UpdateStates();
   int               FindImpulseConfirmation(const int startBar, const int direction);
   void              ReplayZone(SmcZone &zone);
   double            CalcOBScore(const SmcZone &ob) const;
   void              DrawOrderBlocks();
  };

//+------------------------------------------------------------------+
CSmcOrderBlock::CSmcOrderBlock()
   : m_structure(NULL)
   , m_ownStructure(false)
   , m_lookbackBars(500)
   , m_maxOBs(20)
   , m_maxAge(100)
   , m_minStrength(1.5)
   , m_bullishCount(0)
   , m_bearishCount(0)
   , m_colorBullish(C'0,150,200')
   , m_colorBearish(C'200,100,50')
  {
  }

CSmcOrderBlock::~CSmcOrderBlock()
  {
   if(m_ownStructure && m_structure != NULL)
     {
      delete m_structure;
      m_structure = NULL;
     }
   ArrayFree(m_bullishOBs);
   ArrayFree(m_bearishOBs);
  }

//+------------------------------------------------------------------+
bool CSmcOrderBlock::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw, CSmcMarketStructure *structure)
  {
   m_bullishCount = 0; m_bearishCount = 0;
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   SetModulePrefix("OB");
   m_bullishCount = 0;
   m_bearishCount = 0;
   bool keepOwned = m_ownStructure && m_structure == structure && structure != NULL;
   if(m_ownStructure && m_structure != NULL && !keepOwned)
      delete m_structure;
   m_structure = keepOwned ? structure : NULL;
   m_ownStructure = keepOwned;

   if(structure != NULL)
     {
      m_structure    = structure;
      m_ownStructure = keepOwned;
     }
   else
     {
      m_structure = new CSmcMarketStructure();
      if(!m_structure.Init(symbol, timeframe, enableDraw))
        {
         delete m_structure;
         m_structure = NULL;
         m_initialized = false;
         return false;
        }
      m_ownStructure = true;
     }

   ArrayResize(m_bullishOBs, m_maxOBs);
   ArrayResize(m_bearishOBs, m_maxOBs);

   return true;
  }

//+------------------------------------------------------------------+
bool CSmcOrderBlock::Update()
  {
   if(m_enableDraw)
      CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   m_bullishCount = 0;
   m_bearishCount = 0;
   if(!m_initialized || m_structure == NULL || !PrepareRates(m_lookbackBars + 24) || RatesCount() < 23)
      return false;

   if(m_ownStructure)
     {
      m_structure.SetRates(m_rates);
      if(!m_structure.Update())
         return false;
     }

   DetectOrderBlocks();
   UpdateStates();

   if(m_enableDraw)
      DrawOrderBlocks();

   return true;
  }

void CSmcOrderBlock::Clean()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   if(m_ownStructure && m_structure != NULL)
      m_structure.Clean();
   CSmcDrawing::Redraw();
  }

//+------------------------------------------------------------------+
bool CSmcOrderBlock::GetBullishOB(const int index, SmcZone &ob) const
  {
   if(index < 0 || index >= m_bullishCount)
      return false;
   ob = m_bullishOBs[index];
   return true;
  }

bool CSmcOrderBlock::GetBearishOB(const int index, SmcZone &ob) const
  {
   if(index < 0 || index >= m_bearishCount)
      return false;
   ob = m_bearishOBs[index];
   return true;
  }

//+------------------------------------------------------------------+
bool CSmcOrderBlock::GetNearestBullishOB(const double price, SmcZone &ob) const
  {
   double minDist = DBL_MAX;
   bool found     = false;

   for(int i = 0; i < m_bullishCount; i++)
     {
      if(!m_bullishOBs[i].IsActive())
         continue;
      double dist = MathAbs(price - m_bullishOBs[i].GetCenter());
      if(dist < minDist)
        {
         minDist = dist;
         ob      = m_bullishOBs[i];
         found   = true;
        }
     }
   return found;
  }

bool CSmcOrderBlock::GetNearestBearishOB(const double price, SmcZone &ob) const
  {
   double minDist = DBL_MAX;
   bool found     = false;

   for(int i = 0; i < m_bearishCount; i++)
     {
      if(!m_bearishOBs[i].IsActive())
         continue;
      double dist = MathAbs(price - m_bearishOBs[i].GetCenter());
      if(dist < minDist)
        {
         minDist = dist;
         ob      = m_bearishOBs[i];
         found   = true;
        }
     }
   return found;
  }

//+------------------------------------------------------------------+
int CSmcOrderBlock::GetFreshBullishCount() const
  {
   int count = 0;
   for(int i = 0; i < m_bullishCount; i++)
      if(m_bullishOBs[i].IsActive() && m_bullishOBs[i].IsFresh())
         count++;
   return count;
  }

int CSmcOrderBlock::GetFreshBearishCount() const
  {
   int count = 0;
   for(int i = 0; i < m_bearishCount; i++)
      if(m_bearishOBs[i].IsActive() && m_bearishOBs[i].IsFresh())
         count++;
   return count;
  }

double CSmcOrderBlock::GetStopLossForBuy(const SmcZone &ob) const
  {
   return ob.bottomPrice - PipsToPrice(2);
  }

double CSmcOrderBlock::GetStopLossForSell(const SmcZone &ob) const
  {
   return ob.topPrice + PipsToPrice(2);
  }

//+------------------------------------------------------------------+
//| OB検出: BOS/CHoCH前の最後の逆方向ローソク足                       |
//+------------------------------------------------------------------+
void CSmcOrderBlock::DetectOrderBlocks()
  {
   // A source candle requires 20 preceding candles for its impulse baseline.
   int limit = MathMin(m_lookbackBars + 1, RatesCount() - 21);
   for(int bar = 2; bar <= limit; bar++)
     {
      bool bullish = IsBearishCandle(bar);
      if(!bullish && !IsBullishCandle(bar))
         continue;
      int confirmed = FindImpulseConfirmation(bar - 1, bullish ? 1 : -1);
      if(confirmed < 1)
         continue;

      SmcZone zone;
      zone.Init();
      zone.topPrice = High(bar);
      zone.bottomPrice = Low(bar);
      zone.formationTime = Time(bar);
      zone.formationBar = bar;
      zone.confirmedTime = Time(confirmed);
      zone.confirmedBar = confirmed;
      zone.isBullish = bullish;
      zone.probability = PROB_HIGH;
      zone.isValid = true;
      if(bullish && m_bullishCount < m_maxOBs)
         m_bullishOBs[m_bullishCount++] = zone;
      else if(!bullish && m_bearishCount < m_maxOBs)
         m_bearishOBs[m_bearishCount++] = zone;
     }
  }

// Preserve the legacy four-candle impulse rule, but record its first closed
// confirmation and use only the candles preceding the candidate as baseline.
int CSmcOrderBlock::FindImpulseConfirmation(const int startBar, const int direction)
  {
   double avgBody = GetAverageCandleBody(20, startBar + 2);
   if(avgBody <= 0)
      return -1;
   double totalMove = 0;
   for(int bar = startBar; bar >= MathMax(1, startBar - 3); bar--)
     {
      bool matches = direction > 0 ? IsBullishCandle(bar) : IsBearishCandle(bar);
      double body = CandleBody(bar);
      if(matches && body > avgBody * m_minStrength)
         totalMove += body;
      if(totalMove > avgBody * 2.0)
         return bar;
     }
   return -1;
  }

//+------------------------------------------------------------------+
void CSmcOrderBlock::UpdateStates()
  {
   for(int i = 0; i < m_bullishCount; i++)
     {
      ReplayZone(m_bullishOBs[i]);
      m_bullishOBs[i].score = CalcOBScore(m_bullishOBs[i]);
     }
   for(int i = 0; i < m_bearishCount; i++)
     {
      ReplayZone(m_bearishOBs[i]);
      m_bearishOBs[i].score = CalcOBScore(m_bearishOBs[i]);
     }
  }

void CSmcOrderBlock::ReplayZone(SmcZone &zone)
  {
   zone.age = zone.confirmedBar - 1;
   double tick = m_tickSize > 0 ? m_tickSize : m_point;
   for(int bar = zone.confirmedBar - 1; bar >= 1; bar--)
     {
      if(zone.confirmedBar - bar > m_maxAge)
        {
         zone.isExpired = true;
         zone.isValid = false;
         break;
        }
      bool broken = zone.isBullish ? Close(bar) <= NormalizePrice(zone.bottomPrice - tick) :
                                     Close(bar) >= NormalizePrice(zone.topPrice + tick);
      if(broken)
        {
         zone.state = ZONE_BROKEN;
         zone.brokenTime = Time(bar);
         zone.isValid = false;
         break;
        }
      bool touched = Low(bar) <= zone.topPrice && High(bar) >= zone.bottomPrice;
      if(!touched)
         continue;
      if(zone.state == ZONE_FRESH)
         zone.state = ZONE_TESTED;
      bool midpoint = zone.isBullish ? Low(bar) <= zone.GetCenter() :
                                       High(bar) >= zone.GetCenter();
      if(midpoint)
         zone.state = ZONE_MITIGATED;
     }
  }

//+------------------------------------------------------------------+
double CSmcOrderBlock::CalcOBScore(const SmcZone &ob) const
  {
   double score = 0.5;

   if(ob.probability == PROB_HIGH)
      score += 0.2;
   if(ob.state == ZONE_FRESH)
      score += 0.15;
   if(ob.age < 20)
      score += 0.15;

   return MathMin(1.0, score);
  }

//+------------------------------------------------------------------+
void CSmcOrderBlock::DrawOrderBlocks()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);

   for(int i = 0; i < m_bullishCount; i++)
     {
      if(!m_bullishOBs[i].IsActive())
         continue;
      string name = m_prefix + "BULL_" + IntegerToString(i);
      CSmcDrawing::DrawZone(name, m_bullishOBs[i].formationTime,
                            m_bullishOBs[i].topPrice, Time(0),
                            m_bullishOBs[i].bottomPrice,
                            m_bullishOBs[i].IsFresh() ? m_colorBullish : clrGray);

      string label = m_prefix + "BULL_L_" + IntegerToString(i);
      string txt   = "OB+" + (m_bullishOBs[i].IsFresh() ? " [F]" : " [T]");
      CSmcDrawing::DrawText(label, m_bullishOBs[i].formationTime,
                            m_bullishOBs[i].topPrice, txt, m_colorBullish, 7);
     }

   for(int i = 0; i < m_bearishCount; i++)
     {
      if(!m_bearishOBs[i].IsActive())
         continue;
      string name = m_prefix + "BEAR_" + IntegerToString(i);
      CSmcDrawing::DrawZone(name, m_bearishOBs[i].formationTime,
                            m_bearishOBs[i].topPrice, Time(0),
                            m_bearishOBs[i].bottomPrice,
                            m_bearishOBs[i].IsFresh() ? m_colorBearish : clrGray);

      string label = m_prefix + "BEAR_L_" + IntegerToString(i);
      string txt   = "OB-" + (m_bearishOBs[i].IsFresh() ? " [F]" : " [T]");
      CSmcDrawing::DrawText(label, m_bearishOBs[i].formationTime,
                            m_bearishOBs[i].topPrice, txt, m_colorBearish, 7);
     }

   CSmcDrawing::Redraw();
  }

#endif // __SMC_ORDER_BLOCK_MQH__
//+------------------------------------------------------------------+
