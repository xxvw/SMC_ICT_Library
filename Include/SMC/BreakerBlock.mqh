//+------------------------------------------------------------------+
//|                                                 BreakerBlock.mqh |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_BREAKER_BLOCK_MQH__
#define __SMC_BREAKER_BLOCK_MQH__

#include "OrderBlock.mqh"

//+------------------------------------------------------------------+
//| CSmcBreakerBlock - Breaker / Mitigation ブロック                   |
//|                                                                    |
//| Breaker Block: OBが失敗(ブレイク)した後、反対方向のS/Rに変化。    |
//| Mitigation Block: OBがテストされ部分的に消費された後のゾーン。     |
//+------------------------------------------------------------------+
class CSmcBreakerBlock : public CSmcBase
  {
private:
   CSmcOrderBlock   *m_orderBlock;
   CSmcMarketStructure *m_structure;
   bool              m_ownOB;

   //--- データ
   SmcZone           m_breakerBlocks[];
   SmcZone           m_mitigationBlocks[];
   int               m_breakerCount;
   int               m_mitigationCount;
   int               m_maxBlocks;

   //--- 描画色
   color             m_colorBreaker;
   color             m_colorMitigation;

public:
                     CSmcBreakerBlock();
                    ~CSmcBreakerBlock();

   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false,
                          CSmcOrderBlock *orderBlock = NULL,
                          CSmcMarketStructure *structure = NULL);
   virtual bool      Update();
   virtual void      Clean();

   //--- Breaker Blocks
   int               GetBreakerCount() const { return m_breakerCount; }
   bool              GetBreakerBlock(const int index, SmcZone &zone) const;
   bool              GetNearestBreaker(const double price, const bool bullish, SmcZone &zone) const;

   //--- Mitigation Blocks
   int               GetMitigationCount() const { return m_mitigationCount; }
   bool              GetMitigationBlock(const int index, SmcZone &zone) const;

   //--- モジュール参照
   CSmcOrderBlock   *OrderBlock() { return m_orderBlock; }

private:
   void              DetectBreakerBlocks();
   void              DetectMitigationBlocks();
   void              UpdateStates();
   void              DrawBlocks();
  };

//+------------------------------------------------------------------+
CSmcBreakerBlock::CSmcBreakerBlock()
   : m_orderBlock(NULL)
   , m_structure(NULL)
   , m_ownOB(false)
   , m_breakerCount(0)
   , m_mitigationCount(0)
   , m_maxBlocks(15)
   , m_colorBreaker(C'150,0,200')
   , m_colorMitigation(C'200,150,0')
  {
  }

CSmcBreakerBlock::~CSmcBreakerBlock()
  {
   if(m_ownOB && m_orderBlock != NULL)
      delete m_orderBlock;
   ArrayFree(m_breakerBlocks);
   ArrayFree(m_mitigationBlocks);
  }

//+------------------------------------------------------------------+
bool CSmcBreakerBlock::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                            const bool enableDraw, CSmcOrderBlock *orderBlock,
                            CSmcMarketStructure *structure)
  {
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   m_prefix = "SMC_BRK_";

   if(orderBlock != NULL)
     {
      m_orderBlock = orderBlock;
      m_structure  = (structure != NULL) ? structure : orderBlock.Structure();
      m_ownOB      = false;
     }
   else
     {
      m_orderBlock = new CSmcOrderBlock();
      if(!m_orderBlock.Init(symbol, timeframe, false))
        { delete m_orderBlock; m_orderBlock = NULL; return false; }
      m_structure = m_orderBlock.Structure();
      m_ownOB     = true;
     }

   ArrayResize(m_breakerBlocks, m_maxBlocks);
   ArrayResize(m_mitigationBlocks, m_maxBlocks);

   return true;
  }

//+------------------------------------------------------------------+
bool CSmcBreakerBlock::Update()
  {
   if(!m_initialized || m_orderBlock == NULL)
      return false;

   if(m_ownOB)
      m_orderBlock.Update();

   m_breakerCount    = 0;
   m_mitigationCount = 0;

   DetectBreakerBlocks();
   DetectMitigationBlocks();
   UpdateStates();

   if(m_enableDraw)
      DrawBlocks();

   return true;
  }

void CSmcBreakerBlock::Clean()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   if(m_ownOB && m_orderBlock != NULL)
      m_orderBlock.Clean();
   CSmcDrawing::Redraw();
  }

//+------------------------------------------------------------------+
bool CSmcBreakerBlock::GetBreakerBlock(const int index, SmcZone &zone) const
  {
   if(index < 0 || index >= m_breakerCount)
      return false;
   zone = m_breakerBlocks[index];
   return true;
  }

bool CSmcBreakerBlock::GetNearestBreaker(const double price, const bool bullish,
      SmcZone &zone) const
  {
   double minDist = DBL_MAX;
   bool found     = false;

   for(int i = 0; i < m_breakerCount; i++)
     {
      if(!m_breakerBlocks[i].IsActive() || m_breakerBlocks[i].isBullish != bullish)
         continue;
      double dist = MathAbs(price - m_breakerBlocks[i].GetCenter());
      if(dist < minDist)
        { minDist = dist; zone = m_breakerBlocks[i]; found = true; }
     }
   return found;
  }

bool CSmcBreakerBlock::GetMitigationBlock(const int index, SmcZone &zone) const
  {
   if(index < 0 || index >= m_mitigationCount)
      return false;
   zone = m_mitigationBlocks[index];
   return true;
  }

//+------------------------------------------------------------------+
//| Breaker Block検出: ブレイクされたOBが反対方向のS/Rに変化           |
//+------------------------------------------------------------------+
void CSmcBreakerBlock::DetectBreakerBlocks()
  {
//--- Bearish OBがブレイクされた -> Bullish Breaker Block
   for(int i = 0; i < m_orderBlock.GetBearishCount() && m_breakerCount < m_maxBlocks; i++)
     {
      SmcZone ob;
      m_orderBlock.GetBearishOB(i, ob);

      if(ob.state == ZONE_BROKEN && ob.isValid)
        {
         SmcZone breaker = ob;
         breaker.isBullish = true;  // 方向反転
         breaker.state     = ZONE_FRESH;
         breaker.score     = 0.7;
         m_breakerBlocks[m_breakerCount] = breaker;
         m_breakerCount++;
        }
     }

//--- Bullish OBがブレイクされた -> Bearish Breaker Block
   for(int i = 0; i < m_orderBlock.GetBullishCount() && m_breakerCount < m_maxBlocks; i++)
     {
      SmcZone ob;
      m_orderBlock.GetBullishOB(i, ob);

      if(ob.state == ZONE_BROKEN && ob.isValid)
        {
         SmcZone breaker = ob;
         breaker.isBullish = false;  // 方向反転
         breaker.state     = ZONE_FRESH;
         breaker.score     = 0.7;
         m_breakerBlocks[m_breakerCount] = breaker;
         m_breakerCount++;
        }
     }
  }

//+------------------------------------------------------------------+
//| Mitigation Block検出: テスト済みOBのゾーン                         |
//+------------------------------------------------------------------+
void CSmcBreakerBlock::DetectMitigationBlocks()
  {
   for(int i = 0; i < m_orderBlock.GetBullishCount() && m_mitigationCount < m_maxBlocks; i++)
     {
      SmcZone ob;
      m_orderBlock.GetBullishOB(i, ob);
      if(ob.state == ZONE_TESTED || ob.state == ZONE_MITIGATED)
        {
         m_mitigationBlocks[m_mitigationCount] = ob;
         m_mitigationBlocks[m_mitigationCount].state = ZONE_MITIGATED;
         m_mitigationBlocks[m_mitigationCount].score = 0.5;
         m_mitigationCount++;
        }
     }

   for(int i = 0; i < m_orderBlock.GetBearishCount() && m_mitigationCount < m_maxBlocks; i++)
     {
      SmcZone ob;
      m_orderBlock.GetBearishOB(i, ob);
      if(ob.state == ZONE_TESTED || ob.state == ZONE_MITIGATED)
        {
         m_mitigationBlocks[m_mitigationCount] = ob;
         m_mitigationBlocks[m_mitigationCount].state = ZONE_MITIGATED;
         m_mitigationBlocks[m_mitigationCount].score = 0.5;
         m_mitigationCount++;
        }
     }
  }

//+------------------------------------------------------------------+
void CSmcBreakerBlock::UpdateStates()
  {
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   for(int i = 0; i < m_breakerCount; i++)
     {
      if(!m_breakerBlocks[i].isValid)
         continue;

      //--- テスト判定
      if(bid >= m_breakerBlocks[i].bottomPrice && bid <= m_breakerBlocks[i].topPrice)
        {
         if(m_breakerBlocks[i].state == ZONE_FRESH)
            m_breakerBlocks[i].state = ZONE_TESTED;
        }

      //--- ブレイク判定
      if(m_breakerBlocks[i].isBullish && bid < m_breakerBlocks[i].bottomPrice)
        {
         if(m_breakerBlocks[i].state == ZONE_TESTED)
            m_breakerBlocks[i].state = ZONE_BROKEN;
        }
      if(!m_breakerBlocks[i].isBullish && bid > m_breakerBlocks[i].topPrice)
        {
         if(m_breakerBlocks[i].state == ZONE_TESTED)
            m_breakerBlocks[i].state = ZONE_BROKEN;
        }
     }
  }

//+------------------------------------------------------------------+
void CSmcBreakerBlock::DrawBlocks()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);

   for(int i = 0; i < m_breakerCount; i++)
     {
      if(!m_breakerBlocks[i].IsActive())
         continue;
      string name = m_prefix + "BRK_" + IntegerToString(i);
      CSmcDrawing::DrawZone(name, m_breakerBlocks[i].formationTime,
                            m_breakerBlocks[i].topPrice, Time(0),
                            m_breakerBlocks[i].bottomPrice, m_colorBreaker, 25);

      string label = m_prefix + "BRK_L_" + IntegerToString(i);
      CSmcDrawing::DrawText(label, m_breakerBlocks[i].formationTime,
                            m_breakerBlocks[i].topPrice,
                            m_breakerBlocks[i].isBullish ? "BRK+" : "BRK-",
                            m_colorBreaker, 7);
     }

   for(int i = 0; i < m_mitigationCount; i++)
     {
      if(!m_mitigationBlocks[i].IsActive())
         continue;
      string name = m_prefix + "MIT_" + IntegerToString(i);
      CSmcDrawing::DrawZone(name, m_mitigationBlocks[i].formationTime,
                            m_mitigationBlocks[i].topPrice, Time(0),
                            m_mitigationBlocks[i].bottomPrice, m_colorMitigation, 15);

      string label = m_prefix + "MIT_L_" + IntegerToString(i);
      CSmcDrawing::DrawText(label, m_mitigationBlocks[i].formationTime,
                            m_mitigationBlocks[i].topPrice, "MIT",
                            m_colorMitigation, 7);
     }

   CSmcDrawing::Redraw();
  }

#endif // __SMC_BREAKER_BLOCK_MQH__
//+------------------------------------------------------------------+
