//+------------------------------------------------------------------+
//|                                                   OrderBlock.mqh |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
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
   void              SetMaxAge(const int age) { m_maxAge = age; }
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
   bool              IsImpulsiveMove(const int startBar, const int direction);
   double            CalcOBScore(const SmcZone &ob) const;
   void              DrawOrderBlocks();
  };

//+------------------------------------------------------------------+
CSmcOrderBlock::CSmcOrderBlock()
   : m_structure(NULL)
   , m_ownStructure(false)
   , m_lookbackBars(100)
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
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   m_prefix = "SMC_OB_";

   if(structure != NULL)
     {
      m_structure    = structure;
      m_ownStructure = false;
     }
   else
     {
      m_structure = new CSmcMarketStructure();
      if(!m_structure.Init(symbol, timeframe, enableDraw))
        {
         delete m_structure;
         m_structure = NULL;
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
   if(!m_initialized || m_structure == NULL)
      return false;

   if(m_ownStructure)
      m_structure.Update();

   m_bullishCount = 0;
   m_bearishCount = 0;

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
      if(m_bullishOBs[i].IsFresh())
         count++;
   return count;
  }

int CSmcOrderBlock::GetFreshBearishCount() const
  {
   int count = 0;
   for(int i = 0; i < m_bearishCount; i++)
      if(m_bearishOBs[i].IsFresh())
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
   double avgRange = GetAverageRange(20);
   if(avgRange == 0)
      return;

   int limit = MathMin(m_lookbackBars, iBars(m_symbol, m_timeframe) - 5);

   for(int i = 2; i < limit; i++)
     {
      bool isBull = IsBullishCandle(i);
      bool isBear = IsBearishCandle(i);

      //--- Bullish OB: 陰線の後に強い上昇インパルス
      if(isBear && IsImpulsiveMove(i - 1, 1))
        {
         if(m_bullishCount < m_maxOBs)
           {
            m_bullishOBs[m_bullishCount].Init();
            m_bullishOBs[m_bullishCount].topPrice      = High(i);
            m_bullishOBs[m_bullishCount].bottomPrice    = Low(i);
            m_bullishOBs[m_bullishCount].formationTime  = Time(i);
            m_bullishOBs[m_bullishCount].formationBar   = i;
            m_bullishOBs[m_bullishCount].isBullish      = true;
            m_bullishOBs[m_bullishCount].state           = ZONE_FRESH;
            m_bullishOBs[m_bullishCount].candleCount     = 1;
            m_bullishOBs[m_bullishCount].age             = i;
            m_bullishOBs[m_bullishCount].isValid         = true;

            //--- 確率分類
            m_bullishOBs[m_bullishCount].probability =
               (m_bullishOBs[m_bullishCount].candleCount == 1) ? PROB_HIGH : PROB_LOW;

            m_bullishOBs[m_bullishCount].score = CalcOBScore(m_bullishOBs[m_bullishCount]);
            m_bullishCount++;
           }
        }

      //--- Bearish OB: 陽線の後に強い下降インパルス
      if(isBull && IsImpulsiveMove(i - 1, -1))
        {
         if(m_bearishCount < m_maxOBs)
           {
            m_bearishOBs[m_bearishCount].Init();
            m_bearishOBs[m_bearishCount].topPrice      = High(i);
            m_bearishOBs[m_bearishCount].bottomPrice    = Low(i);
            m_bearishOBs[m_bearishCount].formationTime  = Time(i);
            m_bearishOBs[m_bearishCount].formationBar   = i;
            m_bearishOBs[m_bearishCount].isBullish      = false;
            m_bearishOBs[m_bearishCount].state           = ZONE_FRESH;
            m_bearishOBs[m_bearishCount].candleCount     = 1;
            m_bearishOBs[m_bearishCount].age             = i;
            m_bearishOBs[m_bearishCount].isValid         = true;
            m_bearishOBs[m_bearishCount].probability =
               (m_bearishOBs[m_bearishCount].candleCount == 1) ? PROB_HIGH : PROB_LOW;
            m_bearishOBs[m_bearishCount].score = CalcOBScore(m_bearishOBs[m_bearishCount]);
            m_bearishCount++;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| インパルシブムーブ判定                                             |
//+------------------------------------------------------------------+
bool CSmcOrderBlock::IsImpulsiveMove(const int startBar, const int direction)
  {
   double avgBody = GetAverageCandleBody(20);
   if(avgBody == 0)
      return false;

   int consecutive = 0;
   double totalMove = 0;

   for(int i = startBar; i >= MathMax(0, startBar - 3); i--)
     {
      double body = CandleBody(i);
      if(direction > 0 && IsBullishCandle(i) && body > avgBody * m_minStrength)
        {
         totalMove += body;
         consecutive++;
        }
      else if(direction < 0 && IsBearishCandle(i) && body > avgBody * m_minStrength)
        {
         totalMove += body;
         consecutive++;
        }
     }

   return (consecutive >= 1 && totalMove > avgBody * 2.0);
  }

//+------------------------------------------------------------------+
//| OB状態更新                                                         |
//+------------------------------------------------------------------+
void CSmcOrderBlock::UpdateStates()
  {
   double currentBid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   //--- Bullish OB状態更新
   for(int i = 0; i < m_bullishCount; i++)
     {
      if(!m_bullishOBs[i].isValid)
         continue;

      m_bullishOBs[i].age = m_bullishOBs[i].formationBar;

      //--- 寿命切れ
      if(m_bullishOBs[i].age > m_maxAge)
        {
         m_bullishOBs[i].state   = ZONE_BROKEN;
         m_bullishOBs[i].isValid = false;
         continue;
        }

      //--- 価格がOBゾーン内に入った場合
      if(currentBid <= m_bullishOBs[i].topPrice && currentBid >= m_bullishOBs[i].bottomPrice)
        {
         if(m_bullishOBs[i].state == ZONE_FRESH)
            m_bullishOBs[i].state = ZONE_TESTED;
        }

      //--- 下抜けでブレイク
      if(currentBid < m_bullishOBs[i].bottomPrice && m_bullishOBs[i].state == ZONE_TESTED)
        {
         m_bullishOBs[i].state   = ZONE_BROKEN;
         m_bullishOBs[i].isValid = false;
        }
     }

   //--- Bearish OB状態更新
   for(int i = 0; i < m_bearishCount; i++)
     {
      if(!m_bearishOBs[i].isValid)
         continue;

      m_bearishOBs[i].age = m_bearishOBs[i].formationBar;

      if(m_bearishOBs[i].age > m_maxAge)
        {
         m_bearishOBs[i].state   = ZONE_BROKEN;
         m_bearishOBs[i].isValid = false;
         continue;
        }

      if(currentBid >= m_bearishOBs[i].bottomPrice && currentBid <= m_bearishOBs[i].topPrice)
        {
         if(m_bearishOBs[i].state == ZONE_FRESH)
            m_bearishOBs[i].state = ZONE_TESTED;
        }

      if(currentBid > m_bearishOBs[i].topPrice && m_bearishOBs[i].state == ZONE_TESTED)
        {
         m_bearishOBs[i].state   = ZONE_BROKEN;
         m_bearishOBs[i].isValid = false;
        }
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
