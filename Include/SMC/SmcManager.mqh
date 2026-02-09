//+------------------------------------------------------------------+
//|                                                   SmcManager.mqh |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_MANAGER_MQH__
#define __SMC_MANAGER_MQH__

#include "SwingPoints.mqh"
#include "MarketStructure.mqh"
#include "OrderBlock.mqh"
#include "FairValueGap.mqh"
#include "Liquidity.mqh"
#include "PremiumDiscount.mqh"
#include "OptimalTradeEntry.mqh"
#include "KillZone.mqh"
#include "BreakerBlock.mqh"
#include "ConfluenceDetector.mqh"
#include "Analysis/CurrencyStrength.mqh"
#include "Analysis/VIXCalculator.mqh"

//+------------------------------------------------------------------+
//| CSmcManager - 全SMCモジュール統合マネージャー                      |
//|                                                                    |
//| 全モジュールを正しい依存関係順に初期化・更新する。                 |
//| 共通SwingPointsインスタンスを共有し、リソース効率を最適化。       |
//+------------------------------------------------------------------+
class CSmcManager
  {
private:
   //--- モジュール
   CSmcSwingPoints       *m_swing;
   CSmcMarketStructure   *m_structure;
   CSmcOrderBlock        *m_ob;
   CSmcFairValueGap      *m_fvg;
   CSmcLiquidity         *m_liquidity;
   CSmcPremiumDiscount   *m_pd;
   CSmcOptimalTradeEntry *m_ote;
   CSmcKillZone          *m_kz;
   CSmcBreakerBlock      *m_breaker;
   CSmcConfluence        *m_confluence;
   CSmcCurrencyStrength  *m_cs;
   CSmcVIXCalculator     *m_vix;

   //--- 状態
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   bool              m_initialized;
   bool              m_enableDraw;

   //--- モジュール有効化フラグ
   bool              m_enableCS;
   bool              m_enableVIX;

public:
                     CSmcManager();
                    ~CSmcManager();

   //--- 初期化
   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false,
                          const bool enableCS = true,
                          const bool enableVIX = true);
   bool              Update();
   void              Clean();

   //--- モジュールアクセサ
   CSmcSwingPoints       *Swing()      { return m_swing; }
   CSmcMarketStructure   *Structure()  { return m_structure; }
   CSmcOrderBlock        *OB()         { return m_ob; }
   CSmcFairValueGap      *FVG()        { return m_fvg; }
   CSmcLiquidity         *Liquidity()  { return m_liquidity; }
   CSmcPremiumDiscount   *PD()         { return m_pd; }
   CSmcOptimalTradeEntry *OTE()        { return m_ote; }
   CSmcKillZone          *KZ()         { return m_kz; }
   CSmcBreakerBlock      *Breaker()    { return m_breaker; }
   CSmcConfluence        *Confluence() { return m_confluence; }
   CSmcCurrencyStrength  *CurrStr()    { return m_cs; }
   CSmcVIXCalculator     *VIX()        { return m_vix; }

   //--- ショートカット
   ENUM_SMC_TREND        GetTrend()     const;
   ENUM_ENTRY_SIGNAL     GetSignal()    const;
   bool                  IsBullish()    const;
   bool                  IsBearish()    const;
   bool                  IsInitialized() const { return m_initialized; }
  };

//+------------------------------------------------------------------+
CSmcManager::CSmcManager()
   : m_swing(NULL)
   , m_structure(NULL)
   , m_ob(NULL)
   , m_fvg(NULL)
   , m_liquidity(NULL)
   , m_pd(NULL)
   , m_ote(NULL)
   , m_kz(NULL)
   , m_breaker(NULL)
   , m_confluence(NULL)
   , m_cs(NULL)
   , m_vix(NULL)
   , m_symbol("")
   , m_timeframe(PERIOD_CURRENT)
   , m_initialized(false)
   , m_enableDraw(false)
   , m_enableCS(true)
   , m_enableVIX(true)
  {
  }

//+------------------------------------------------------------------+
CSmcManager::~CSmcManager()
  {
   Clean();

   if(m_confluence != NULL) { delete m_confluence; m_confluence = NULL; }
   if(m_breaker != NULL)    { delete m_breaker;    m_breaker = NULL; }
   if(m_kz != NULL)         { delete m_kz;         m_kz = NULL; }
   if(m_ote != NULL)        { delete m_ote;        m_ote = NULL; }
   if(m_pd != NULL)         { delete m_pd;         m_pd = NULL; }
   if(m_liquidity != NULL)  { delete m_liquidity;  m_liquidity = NULL; }
   if(m_fvg != NULL)        { delete m_fvg;        m_fvg = NULL; }
   if(m_ob != NULL)         { delete m_ob;         m_ob = NULL; }
   if(m_structure != NULL)  { delete m_structure;   m_structure = NULL; }
   if(m_swing != NULL)      { delete m_swing;       m_swing = NULL; }
   if(m_cs != NULL)         { delete m_cs;          m_cs = NULL; }
   if(m_vix != NULL)        { delete m_vix;         m_vix = NULL; }
  }

//+------------------------------------------------------------------+
bool CSmcManager::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                       const bool enableDraw, const bool enableCS,
                       const bool enableVIX)
  {
   m_symbol     = (symbol == "" || symbol == "0") ? _Symbol : symbol;
   m_timeframe  = (timeframe == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : timeframe;
   m_enableDraw = enableDraw;
   m_enableCS   = enableCS;
   m_enableVIX  = enableVIX;

//--- 1. SwingPoints (基盤 - 全モジュールが共有)
   m_swing = new CSmcSwingPoints();
   if(!m_swing.Init(m_symbol, m_timeframe, enableDraw))
      return false;

//--- 2. MarketStructure (SwingPointsを共有)
   m_structure = new CSmcMarketStructure();
   if(!m_structure.Init(m_symbol, m_timeframe, enableDraw, m_swing))
      return false;

//--- 3. OrderBlock (MarketStructureを共有)
   m_ob = new CSmcOrderBlock();
   if(!m_ob.Init(m_symbol, m_timeframe, enableDraw, m_structure))
      return false;

//--- 4. FairValueGap (独立)
   m_fvg = new CSmcFairValueGap();
   if(!m_fvg.Init(m_symbol, m_timeframe, enableDraw))
      return false;

//--- 5. Liquidity (SwingPointsを共有)
   m_liquidity = new CSmcLiquidity();
   if(!m_liquidity.Init(m_symbol, m_timeframe, enableDraw, m_swing))
      return false;

//--- 6. PremiumDiscount (SwingPointsを共有)
   m_pd = new CSmcPremiumDiscount();
   if(!m_pd.Init(m_symbol, m_timeframe, enableDraw, m_swing))
      return false;

//--- 7. OptimalTradeEntry (SwingPointsを共有)
   m_ote = new CSmcOptimalTradeEntry();
   if(!m_ote.Init(m_symbol, m_timeframe, enableDraw, m_swing))
      return false;

//--- 8. KillZone (独立)
   m_kz = new CSmcKillZone();
   if(!m_kz.Init(m_symbol, m_timeframe, enableDraw))
      return false;

//--- 9. BreakerBlock (OrderBlock/MarketStructureを共有)
   m_breaker = new CSmcBreakerBlock();
   if(!m_breaker.Init(m_symbol, m_timeframe, enableDraw, m_ob, m_structure))
      return false;

//--- 10. Confluence (全モジュール参照)
   m_confluence = new CSmcConfluence();
   if(!m_confluence.Init(m_symbol, m_timeframe, enableDraw))
      return false;
   m_confluence.SetStructure(m_structure);
   m_confluence.SetOrderBlock(m_ob);
   m_confluence.SetFVG(m_fvg);
   m_confluence.SetLiquidity(m_liquidity);
   m_confluence.SetOTE(m_ote);
   m_confluence.SetKillZone(m_kz);
   m_confluence.SetBreaker(m_breaker);

//--- 11. CurrencyStrength (オプション)
   if(m_enableCS)
     {
      m_cs = new CSmcCurrencyStrength();
      m_cs.Init(m_symbol, m_timeframe, false);
     }

//--- 12. VIXCalculator (オプション)
   if(m_enableVIX)
     {
      m_vix = new CSmcVIXCalculator();
      m_vix.Init(m_symbol, m_timeframe, false);
     }

   m_initialized = true;
   Print("[SMC Manager] Initialized for ", m_symbol, " ", EnumToString(m_timeframe));
   return true;
  }

//+------------------------------------------------------------------+
//| 全モジュールを正しい依存関係順に更新                               |
//+------------------------------------------------------------------+
bool CSmcManager::Update()
  {
   if(!m_initialized)
      return false;

//--- 更新順序: 依存関係の上流から下流へ
   m_swing.Update();          // 1. SwingPoints (基盤)
   m_structure.Update();      // 2. MarketStructure (SwingPoints依存)
   m_ob.Update();             // 3. OrderBlock (MarketStructure依存)
   m_fvg.Update();            // 4. FVG (独立)
   m_liquidity.Update();      // 5. Liquidity (SwingPoints依存)
   m_pd.Update();             // 6. PremiumDiscount (SwingPoints依存)
   m_ote.Update();            // 7. OTE (SwingPoints依存)
   m_kz.Update();             // 8. KillZone (独立)
   m_breaker.Update();        // 9. BreakerBlock (OB+Structure依存)
   m_confluence.Update();     // 10. Confluence (全モジュール依存)

   if(m_cs != NULL)
      m_cs.Update();          // 11. CurrencyStrength
   if(m_vix != NULL)
      m_vix.Update();         // 12. VIX

   return true;
  }

//+------------------------------------------------------------------+
void CSmcManager::Clean()
  {
   if(m_swing != NULL)      m_swing.Clean();
   if(m_structure != NULL)  m_structure.Clean();
   if(m_ob != NULL)         m_ob.Clean();
   if(m_fvg != NULL)        m_fvg.Clean();
   if(m_liquidity != NULL)  m_liquidity.Clean();
   if(m_pd != NULL)         m_pd.Clean();
   if(m_ote != NULL)        m_ote.Clean();
   if(m_kz != NULL)         m_kz.Clean();
   if(m_breaker != NULL)    m_breaker.Clean();
   if(m_confluence != NULL) m_confluence.Clean();
   if(m_cs != NULL)         m_cs.Clean();
   if(m_vix != NULL)        m_vix.Clean();
  }

//+------------------------------------------------------------------+
ENUM_SMC_TREND CSmcManager::GetTrend() const
  {
   if(m_structure != NULL)
      return m_structure.GetTrend();
   return SMC_TREND_RANGING;
  }

ENUM_ENTRY_SIGNAL CSmcManager::GetSignal() const
  {
   if(m_confluence != NULL)
      return m_confluence.GetEntrySignal();
   return SIGNAL_WAIT;
  }

bool CSmcManager::IsBullish() const
  {
   return GetTrend() == SMC_TREND_BULLISH;
  }

bool CSmcManager::IsBearish() const
  {
   return GetTrend() == SMC_TREND_BEARISH;
  }

#endif // __SMC_MANAGER_MQH__
//+------------------------------------------------------------------+
