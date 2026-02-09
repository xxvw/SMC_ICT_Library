//+------------------------------------------------------------------+
//|                                          ConfluenceDetector.mqh  |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_CONFLUENCE_DETECTOR_MQH__
#define __SMC_CONFLUENCE_DETECTOR_MQH__

#include "OrderBlock.mqh"
#include "FairValueGap.mqh"
#include "Liquidity.mqh"
#include "OptimalTradeEntry.mqh"
#include "KillZone.mqh"
#include "BreakerBlock.mqh"

//+------------------------------------------------------------------+
//| CSmcConfluence - 複合コンフルエンス判定                            |
//|                                                                    |
//| 複数のSMCコンセプトの合流度をスコアリングし、                      |
//| エントリーシグナルを生成する。                                     |
//+------------------------------------------------------------------+
class CSmcConfluence : public CSmcBase
  {
private:
   //--- モジュール参照 (外部所有)
   CSmcMarketStructure *m_structure;
   CSmcOrderBlock      *m_ob;
   CSmcFairValueGap    *m_fvg;
   CSmcLiquidity       *m_liquidity;
   CSmcOptimalTradeEntry *m_ote;
   CSmcKillZone        *m_kz;
   CSmcBreakerBlock    *m_breaker;

   //--- ウェイト設定
   double            m_weightStructure;  // 構造ブレイク
   double            m_weightOB;         // オーダーブロック
   double            m_weightFVG;        // FVG
   double            m_weightLiquidity;  // 流動性
   double            m_weightOTE;        // OTE
   double            m_weightKillZone;   // キルゾーン
   double            m_weightBreaker;    // ブレーカーブロック

   //--- 閾値
   int               m_minConfluence;    // 最小コンフルエンス数
   double            m_minScore;         // 最小スコア

   //--- 結果
   SmcConfluenceZone m_buyZone;
   SmcConfluenceZone m_sellZone;
   ENUM_ENTRY_SIGNAL m_lastSignal;

   //--- 価格許容範囲
   double            m_tolerancePips;

public:
                     CSmcConfluence();
                    ~CSmcConfluence();

   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false);
   virtual bool      Update();
   virtual void      Clean();

   //--- モジュール設定
   void              SetStructure(CSmcMarketStructure *s) { m_structure = s; }
   void              SetOrderBlock(CSmcOrderBlock *ob)    { m_ob = ob; }
   void              SetFVG(CSmcFairValueGap *fvg)        { m_fvg = fvg; }
   void              SetLiquidity(CSmcLiquidity *liq)     { m_liquidity = liq; }
   void              SetOTE(CSmcOptimalTradeEntry *ote)   { m_ote = ote; }
   void              SetKillZone(CSmcKillZone *kz)        { m_kz = kz; }
   void              SetBreaker(CSmcBreakerBlock *brk)    { m_breaker = brk; }

   //--- ウェイト設定
   void              SetWeights(const double structure, const double ob,
                                const double fvg, const double liquidity,
                                const double ote, const double killzone,
                                const double breaker);
   void              SetMinConfluence(const int min) { m_minConfluence = min; }
   void              SetMinScore(const double min)   { m_minScore = min; }

   //--- 結果取得
   bool              GetBuyZone(SmcConfluenceZone &zone) const;
   bool              GetSellZone(SmcConfluenceZone &zone) const;
   ENUM_ENTRY_SIGNAL GetEntrySignal() const { return m_lastSignal; }
   bool              IsBuyAllowed()  const;
   bool              IsSellAllowed() const;

private:
   void              DetectBuyZone();
   void              DetectSellZone();
   void              AddFactor(SmcConfluenceZone &zone, const string name,
                               const double score);
   void              FinalizeZone(SmcConfluenceZone &zone);
   void              DrawConfluence();
  };

//+------------------------------------------------------------------+
CSmcConfluence::CSmcConfluence()
   : m_structure(NULL)
   , m_ob(NULL)
   , m_fvg(NULL)
   , m_liquidity(NULL)
   , m_ote(NULL)
   , m_kz(NULL)
   , m_breaker(NULL)
   , m_weightStructure(0.25)
   , m_weightOB(0.20)
   , m_weightFVG(0.15)
   , m_weightLiquidity(0.10)
   , m_weightOTE(0.10)
   , m_weightKillZone(0.10)
   , m_weightBreaker(0.10)
   , m_minConfluence(3)
   , m_minScore(0.5)
   , m_lastSignal(SIGNAL_WAIT)
   , m_tolerancePips(20.0)
  {
   m_buyZone.Init();
   m_sellZone.Init();
  }

CSmcConfluence::~CSmcConfluence() {}

//+------------------------------------------------------------------+
bool CSmcConfluence::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw)
  {
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;
   m_prefix = "SMC_CONF_";
   return true;
  }

//+------------------------------------------------------------------+
bool CSmcConfluence::Update()
  {
   if(!m_initialized)
      return false;

   m_buyZone.Init();
   m_sellZone.Init();
   m_lastSignal = SIGNAL_WAIT;

   DetectBuyZone();
   DetectSellZone();

//--- シグナル決定
   bool buyOK  = IsBuyAllowed();
   bool sellOK = IsSellAllowed();

   if(buyOK && !sellOK)
      m_lastSignal = SIGNAL_BUY;
   else if(sellOK && !buyOK)
      m_lastSignal = SIGNAL_SELL;
   else if(buyOK && sellOK)
      m_lastSignal = (m_buyZone.totalScore > m_sellZone.totalScore) ? SIGNAL_BUY : SIGNAL_SELL;

   if(m_enableDraw)
      DrawConfluence();

   return true;
  }

void CSmcConfluence::Clean()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   CSmcDrawing::Redraw();
  }

//+------------------------------------------------------------------+
void CSmcConfluence::SetWeights(const double structure, const double ob,
                                const double fvg, const double liquidity,
                                const double ote, const double killzone,
                                const double breaker)
  {
   m_weightStructure = structure;
   m_weightOB        = ob;
   m_weightFVG       = fvg;
   m_weightLiquidity = liquidity;
   m_weightOTE       = ote;
   m_weightKillZone  = killzone;
   m_weightBreaker   = breaker;
  }

//+------------------------------------------------------------------+
bool CSmcConfluence::GetBuyZone(SmcConfluenceZone &zone) const
  {
   if(!m_buyZone.isValid) return false;
   zone = m_buyZone;
   return true;
  }

bool CSmcConfluence::GetSellZone(SmcConfluenceZone &zone) const
  {
   if(!m_sellZone.isValid) return false;
   zone = m_sellZone;
   return true;
  }

bool CSmcConfluence::IsBuyAllowed() const
  {
   return m_buyZone.isValid &&
          m_buyZone.factorCount >= m_minConfluence &&
          m_buyZone.totalScore >= m_minScore;
  }

bool CSmcConfluence::IsSellAllowed() const
  {
   return m_sellZone.isValid &&
          m_sellZone.factorCount >= m_minConfluence &&
          m_sellZone.totalScore >= m_minScore;
  }

//+------------------------------------------------------------------+
void CSmcConfluence::DetectBuyZone()
  {
   m_buyZone.isBullish = true;
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double tolerance = PipsToPrice(m_tolerancePips);

//--- 1. 構造 (BOS/CHoCH)
   if(m_structure != NULL)
     {
      if(m_structure.IsBullish())
         AddFactor(m_buyZone, "Bullish Trend", m_weightStructure * 0.5);
      if(m_structure.HasRecentBOS(10))
        {
         SmcStructureBreak bos;
         m_structure.GetLastBOS(bos);
         if(bos.isBullish)
            AddFactor(m_buyZone, "Bullish BOS", m_weightStructure);
        }
      if(m_structure.HasRecentCHoCH(10))
        {
         SmcStructureBreak choch;
         m_structure.GetLastCHoCH(choch);
         if(choch.isBullish)
            AddFactor(m_buyZone, "Bullish CHoCH", m_weightStructure * 1.2);
        }
     }

//--- 2. Order Block
   if(m_ob != NULL)
     {
      SmcZone ob;
      if(m_ob.GetNearestBullishOB(bid, ob))
        {
         if(MathAbs(bid - ob.GetCenter()) <= tolerance)
            AddFactor(m_buyZone, "Bullish OB", m_weightOB * (ob.IsFresh() ? 1.0 : 0.6));
        }
     }

//--- 3. FVG
   if(m_fvg != NULL)
     {
      if(m_fvg.IsPriceInBullishFVG(bid))
         AddFactor(m_buyZone, "Bullish FVG", m_weightFVG);
      else
        {
         SmcZone fvg;
         if(m_fvg.GetNearestBullishFVG(bid, fvg))
            if(MathAbs(bid - fvg.GetCenter()) <= tolerance)
               AddFactor(m_buyZone, "Near Bullish FVG", m_weightFVG * 0.5);
        }
     }

//--- 4. Liquidity sweep
   if(m_liquidity != NULL)
     {
      if(m_liquidity.IsLiquiditySweep(LIQ_SWEEP_LOW))
         AddFactor(m_buyZone, "Low Sweep", m_weightLiquidity);
     }

//--- 5. OTE
   if(m_ote != NULL)
     {
      SmcOTEZone ote;
      if(m_ote.GetOTEZone(ote) && ote.isBullish && m_ote.IsInOTEZone(bid))
         AddFactor(m_buyZone, "In OTE Zone", m_weightOTE);
     }

//--- 6. Kill Zone
   if(m_kz != NULL)
     {
      if(m_kz.IsInKillZone())
         AddFactor(m_buyZone, "Kill Zone Active", m_weightKillZone);
     }

//--- 7. Breaker Block
   if(m_breaker != NULL)
     {
      SmcZone brk;
      if(m_breaker.GetNearestBreaker(bid, true, brk))
         if(MathAbs(bid - brk.GetCenter()) <= tolerance)
            AddFactor(m_buyZone, "Bullish Breaker", m_weightBreaker);
     }

   FinalizeZone(m_buyZone);
  }

//+------------------------------------------------------------------+
void CSmcConfluence::DetectSellZone()
  {
   m_sellZone.isBullish = false;
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double tolerance = PipsToPrice(m_tolerancePips);

   if(m_structure != NULL)
     {
      if(m_structure.IsBearish())
         AddFactor(m_sellZone, "Bearish Trend", m_weightStructure * 0.5);
      if(m_structure.HasRecentBOS(10))
        {
         SmcStructureBreak bos;
         m_structure.GetLastBOS(bos);
         if(!bos.isBullish)
            AddFactor(m_sellZone, "Bearish BOS", m_weightStructure);
        }
      if(m_structure.HasRecentCHoCH(10))
        {
         SmcStructureBreak choch;
         m_structure.GetLastCHoCH(choch);
         if(!choch.isBullish)
            AddFactor(m_sellZone, "Bearish CHoCH", m_weightStructure * 1.2);
        }
     }

   if(m_ob != NULL)
     {
      SmcZone ob;
      if(m_ob.GetNearestBearishOB(bid, ob))
         if(MathAbs(bid - ob.GetCenter()) <= tolerance)
            AddFactor(m_sellZone, "Bearish OB", m_weightOB * (ob.IsFresh() ? 1.0 : 0.6));
     }

   if(m_fvg != NULL)
     {
      if(m_fvg.IsPriceInBearishFVG(bid))
         AddFactor(m_sellZone, "Bearish FVG", m_weightFVG);
      else
        {
         SmcZone fvg;
         if(m_fvg.GetNearestBearishFVG(bid, fvg))
            if(MathAbs(bid - fvg.GetCenter()) <= tolerance)
               AddFactor(m_sellZone, "Near Bearish FVG", m_weightFVG * 0.5);
        }
     }

   if(m_liquidity != NULL)
      if(m_liquidity.IsLiquiditySweep(LIQ_SWEEP_HIGH))
         AddFactor(m_sellZone, "High Sweep", m_weightLiquidity);

   if(m_ote != NULL)
     {
      SmcOTEZone ote;
      if(m_ote.GetOTEZone(ote) && !ote.isBullish && m_ote.IsInOTEZone(bid))
         AddFactor(m_sellZone, "In OTE Zone", m_weightOTE);
     }

   if(m_kz != NULL && m_kz.IsInKillZone())
      AddFactor(m_sellZone, "Kill Zone Active", m_weightKillZone);

   if(m_breaker != NULL)
     {
      SmcZone brk;
      if(m_breaker.GetNearestBreaker(bid, false, brk))
         if(MathAbs(bid - brk.GetCenter()) <= tolerance)
            AddFactor(m_sellZone, "Bearish Breaker", m_weightBreaker);
     }

   FinalizeZone(m_sellZone);
  }

//+------------------------------------------------------------------+
void CSmcConfluence::AddFactor(SmcConfluenceZone &zone, const string name,
                               const double score)
  {
   int idx = zone.factorCount;
   ArrayResize(zone.factors, idx + 1);
   ArrayResize(zone.factorScores, idx + 1);
   zone.factors[idx]      = name;
   zone.factorScores[idx] = score;
   zone.factorCount       = idx + 1;
  }

void CSmcConfluence::FinalizeZone(SmcConfluenceZone &zone)
  {
   if(zone.factorCount == 0)
      return;

   double total = 0;
   for(int i = 0; i < zone.factorCount; i++)
      total += zone.factorScores[i];

   zone.totalScore  = MathMin(1.0, total);
   zone.centerPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   zone.topPrice    = zone.centerPrice + PipsToPrice(m_tolerancePips / 2);
   zone.bottomPrice = zone.centerPrice - PipsToPrice(m_tolerancePips / 2);
   zone.isValid     = (zone.factorCount >= 1);
  }

//+------------------------------------------------------------------+
void CSmcConfluence::DrawConfluence()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);

   int y = 20;

   if(m_lastSignal == SIGNAL_BUY)
     {
      CSmcDrawing::DrawLabel(m_prefix + "SIG", 10, y, "SIGNAL: BUY", clrLime, 12);
      y += 20;
      CSmcDrawing::DrawLabel(m_prefix + "SCORE", 10, y,
                             "Score: " + DoubleToString(m_buyZone.totalScore, 2) +
                             " (" + IntegerToString(m_buyZone.factorCount) + " factors)",
                             clrLime, 10);
     }
   else if(m_lastSignal == SIGNAL_SELL)
     {
      CSmcDrawing::DrawLabel(m_prefix + "SIG", 10, y, "SIGNAL: SELL", clrRed, 12);
      y += 20;
      CSmcDrawing::DrawLabel(m_prefix + "SCORE", 10, y,
                             "Score: " + DoubleToString(m_sellZone.totalScore, 2) +
                             " (" + IntegerToString(m_sellZone.factorCount) + " factors)",
                             clrRed, 10);
     }
   else
     {
      CSmcDrawing::DrawLabel(m_prefix + "SIG", 10, y, "SIGNAL: WAIT", clrGray, 12);
     }

   CSmcDrawing::Redraw();
  }

#endif // __SMC_CONFLUENCE_DETECTOR_MQH__
//+------------------------------------------------------------------+
