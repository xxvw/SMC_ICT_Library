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
   int               m_maxAge;

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

   void              SetMaxBlocks(const int maxRecords)
     {
      m_maxBlocks = MathMax(1, maxRecords);
      ArrayResize(m_breakerBlocks, m_maxBlocks);
      ArrayResize(m_mitigationBlocks, m_maxBlocks);
      m_breakerCount = 0; m_mitigationCount = 0;
     }
   void              SetMaxAge(const int age) { m_maxAge = MathMax(0, age); }

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
   void              AddNewest(SmcZone &zones[], int &count, const SmcZone &zone);
   void              AddBreaker(const SmcZone &ob);
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
   , m_maxAge(200)
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
   m_breakerCount = 0; m_mitigationCount = 0;
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   SetModulePrefix("BRK");
   m_breakerCount = 0;
   m_mitigationCount = 0;
   bool keepOwned = m_ownOB && m_orderBlock == orderBlock && orderBlock != NULL;
   if(m_ownOB && m_orderBlock != NULL && !keepOwned)
      delete m_orderBlock;
   m_orderBlock = keepOwned ? orderBlock : NULL;
   m_structure = NULL;
   m_ownOB = keepOwned;

   if(orderBlock != NULL)
     {
      m_orderBlock = orderBlock;
      m_structure  = (structure != NULL) ? structure : orderBlock.Structure();
      m_ownOB      = keepOwned;
     }
   else
     {
      m_orderBlock = new CSmcOrderBlock();
      if(!m_orderBlock.Init(symbol, timeframe, false, structure))
        { delete m_orderBlock; m_orderBlock = NULL; m_initialized = false; return false; }
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
   if(m_enableDraw)
      CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   m_breakerCount = 0;
   m_mitigationCount = 0;
   if(!m_initialized || m_orderBlock == NULL || !PrepareRates(524))
      return false;

   if(m_ownOB)
     {
      m_orderBlock.SetRates(m_rates);
      if(!m_orderBlock.Update())
         return false;
     }

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
   for(int i = 0; i < m_orderBlock.GetBearishCount(); i++)
     {
      SmcZone ob;
      if(m_orderBlock.GetBearishOB(i, ob))
         AddBreaker(ob);
     }
   for(int i = 0; i < m_orderBlock.GetBullishCount(); i++)
     {
      SmcZone ob;
      if(m_orderBlock.GetBullishOB(i, ob))
         AddBreaker(ob);
     }
  }

void CSmcBreakerBlock::AddBreaker(const SmcZone &ob)
  {
   // BROKEN source OBs are intentionally invalid for entry, but remain history.
   if(ob.state != ZONE_BROKEN || ob.isExpired || ob.brokenTime <= 0)
      return;
   int activation = -1;
   for(int bar = 1; bar < RatesCount(); bar++)
      if(Time(bar) == ob.brokenTime)
        {
         activation = bar;
         break;
        }
   if(activation < 1)
      return;

   SmcZone breaker = ob;
   breaker.sourceFormationTime = ob.formationTime;
   breaker.sourceConfirmedTime = ob.confirmedTime;
   breaker.formationTime = ob.brokenTime;
   breaker.formationBar = activation;
   breaker.confirmedTime = ob.brokenTime;
   breaker.confirmedBar = activation;
   breaker.brokenTime = 0;
   breaker.isBullish = !ob.isBullish;
   breaker.state = ZONE_FRESH;
   breaker.isValid = true;
   breaker.isExpired = false;
   breaker.age = activation - 1;
   breaker.score = 0.7;
   AddNewest(m_breakerBlocks, m_breakerCount, breaker);
  }

// Retain the newest records across both directions in chronological getter order.
void CSmcBreakerBlock::AddNewest(SmcZone &zones[], int &count, const SmcZone &zone)
  {
   int position = 0;
   while(position < count && zones[position].confirmedTime >= zone.confirmedTime)
      position++;
   if(position >= m_maxBlocks)
      return;
   int last = MathMin(count, m_maxBlocks - 1);
   for(int i = last; i > position; i--)
      zones[i] = zones[i - 1];
   zones[position] = zone;
   if(count < m_maxBlocks)
      count++;
  }

//+------------------------------------------------------------------+
void CSmcBreakerBlock::DetectMitigationBlocks()
  {
   for(int direction = 0; direction < 2; direction++)
     {
      int count = direction == 0 ? m_orderBlock.GetBullishCount() : m_orderBlock.GetBearishCount();
      for(int i = 0; i < count; i++)
        {
         SmcZone ob;
         bool found = direction == 0 ? m_orderBlock.GetBullishOB(i, ob) :
                                       m_orderBlock.GetBearishOB(i, ob);
         if(!found || !ob.IsActive())
            continue;
         if(ob.state == ZONE_MITIGATED)
           {
            ob.state = ZONE_MITIGATED;
            ob.score = 0.5;
            AddNewest(m_mitigationBlocks, m_mitigationCount, ob);
           }
        }
     }
  }

//+------------------------------------------------------------------+
void CSmcBreakerBlock::UpdateStates()
  {
   double tick = m_tickSize > 0 ? m_tickSize : m_point;
   for(int i = 0; i < m_breakerCount; i++)
     {
      for(int bar = m_breakerBlocks[i].confirmedBar - 1; bar >= 1; bar--)
        {
         if(m_breakerBlocks[i].confirmedBar - bar > m_maxAge)
           {
            m_breakerBlocks[i].isExpired = true;
            m_breakerBlocks[i].isValid = false;
            break;
           }
         bool broken = m_breakerBlocks[i].isBullish ?
            Close(bar) <= NormalizePrice(m_breakerBlocks[i].bottomPrice - tick) :
            Close(bar) >= NormalizePrice(m_breakerBlocks[i].topPrice + tick);
         if(broken)
           {
            m_breakerBlocks[i].state = ZONE_BROKEN;
            m_breakerBlocks[i].brokenTime = Time(bar);
            m_breakerBlocks[i].isValid = false;
            break;
           }
         bool touched = Low(bar) <= m_breakerBlocks[i].topPrice &&
                        High(bar) >= m_breakerBlocks[i].bottomPrice;
         if(!touched)
            continue;
         if(m_breakerBlocks[i].state == ZONE_FRESH)
            m_breakerBlocks[i].state = ZONE_TESTED;
         bool midpoint = m_breakerBlocks[i].isBullish ?
            Low(bar) <= m_breakerBlocks[i].GetCenter() :
            High(bar) >= m_breakerBlocks[i].GetCenter();
         if(midpoint)
            m_breakerBlocks[i].state = ZONE_MITIGATED;
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
