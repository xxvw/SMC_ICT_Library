//+------------------------------------------------------------------+
//|                                              MarketStructure.mqh |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_MARKET_STRUCTURE_MQH__
#define __SMC_MARKET_STRUCTURE_MQH__

#include "SwingPoints.mqh"

//+------------------------------------------------------------------+
//| CSmcMarketStructure - マーケット構造分析                           |
//|                                                                    |
//| BOS (Break of Structure) / CHoCH (Change of Character) 検出       |
//| トレンド判定、レンジ検出を行う。                                   |
//+------------------------------------------------------------------+
class CSmcMarketStructure : public CSmcBase
  {
private:
   //--- モジュール参照
   CSmcSwingPoints  *m_swingPoints;    // スイングポイントモジュール
   bool              m_ownSwing;       // 自前のSwingPointsか

   //--- 設定
   int               m_minRangeBars;   // レンジ判定最小バー数
   int               m_maxBreaks;      // 保持する構造ブレイク数

   //--- 状態
   ENUM_SMC_TREND    m_currentTrend;   // 現在のトレンド
   ENUM_SMC_TREND    m_previousTrend;  // 前回のトレンド
   SmcStructureBreak m_lastBOS;        // 直近BOS
   SmcStructureBreak m_lastCHoCH;      // 直近CHoCH
   SmcStructureBreak m_breakHistory[]; // ブレイク履歴
   int               m_breakCount;     // 履歴数
   SmcRangeInfo      m_currentRange;   // 現在のレンジ情報

   //--- 描画色
   color             m_colorBOSBull;
   color             m_colorBOSBear;
   color             m_colorCHoCH;
   color             m_colorRange;

public:
                     CSmcMarketStructure();
                    ~CSmcMarketStructure();

   //--- 初期化
   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false,
                          CSmcSwingPoints *swingPoints = NULL);
   virtual bool      Update();
   virtual void      Clean();

   //--- SwingPoints参照
   CSmcSwingPoints  *SwingPoints() { return m_swingPoints; }

   //--- トレンド
   ENUM_SMC_TREND    GetTrend()         const { return m_currentTrend; }
   ENUM_SMC_TREND    GetPreviousTrend() const { return m_previousTrend; }
   bool              IsBullish()        const { return m_currentTrend == SMC_TREND_BULLISH; }
   bool              IsBearish()        const { return m_currentTrend == SMC_TREND_BEARISH; }
   bool              IsRanging()        const { return m_currentTrend == SMC_TREND_RANGING; }

   //--- 構造ブレイク
   bool              GetLastBOS(SmcStructureBreak &brk) const;
   bool              GetLastCHoCH(SmcStructureBreak &brk) const;
   bool              HasRecentBOS(const int withinBars = 10) const;
   bool              HasRecentCHoCH(const int withinBars = 10) const;

   //--- レンジ
   bool              GetCurrentRange(SmcRangeInfo &range) const;
   bool              IsInRange() const;

   //--- エントリー方向
   ENUM_ENTRY_SIGNAL GetEntryDirection() const;

private:
   void              AnalyzeStructure();
   void              DetectStructureBreaks();
   void              DetectTrend();
   void              DetectRange();
   void              AddBreakToHistory(const SmcStructureBreak &brk);
   void              DrawStructure();
  };

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
CSmcMarketStructure::CSmcMarketStructure()
   : m_swingPoints(NULL)
   , m_ownSwing(false)
   , m_minRangeBars(10)
   , m_maxBreaks(20)
   , m_currentTrend(SMC_TREND_RANGING)
   , m_previousTrend(SMC_TREND_RANGING)
   , m_breakCount(0)
   , m_colorBOSBull(clrLime)
   , m_colorBOSBear(clrRed)
   , m_colorCHoCH(clrGold)
   , m_colorRange(clrGray)
  {
   m_lastBOS.Init();
   m_lastCHoCH.Init();
   m_currentRange.Init();
  }

//+------------------------------------------------------------------+
//| Destructor                                                         |
//+------------------------------------------------------------------+
CSmcMarketStructure::~CSmcMarketStructure()
  {
   if(m_ownSwing && m_swingPoints != NULL)
     {
      delete m_swingPoints;
      m_swingPoints = NULL;
     }
   ArrayFree(m_breakHistory);
  }

//+------------------------------------------------------------------+
//| 初期化                                                             |
//+------------------------------------------------------------------+
bool CSmcMarketStructure::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                               const bool enableDraw, CSmcSwingPoints *swingPoints)
  {
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   m_prefix = "SMC_STR_";

//--- SwingPoints設定
   if(swingPoints != NULL)
     {
      m_swingPoints = swingPoints;
      m_ownSwing    = false;
     }
   else
     {
      m_swingPoints = new CSmcSwingPoints();
      if(!m_swingPoints.Init(symbol, timeframe, enableDraw))
        {
         delete m_swingPoints;
         m_swingPoints = NULL;
         return false;
        }
      m_ownSwing = true;
     }

   ArrayResize(m_breakHistory, m_maxBreaks);
   m_breakCount = 0;

   return true;
  }

//+------------------------------------------------------------------+
//| 更新                                                               |
//+------------------------------------------------------------------+
bool CSmcMarketStructure::Update()
  {
   if(!m_initialized || m_swingPoints == NULL)
      return false;

//--- SwingPointsが自前の場合は更新
   if(m_ownSwing)
     {
      if(!m_swingPoints.Update())
         return false;
     }

   AnalyzeStructure();

   if(m_enableDraw)
      DrawStructure();

   return true;
  }

//+------------------------------------------------------------------+
//| クリーンアップ                                                     |
//+------------------------------------------------------------------+
void CSmcMarketStructure::Clean()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   if(m_ownSwing && m_swingPoints != NULL)
      m_swingPoints.Clean();
   CSmcDrawing::Redraw();
  }

//+------------------------------------------------------------------+
//| 直近BOS取得                                                        |
//+------------------------------------------------------------------+
bool CSmcMarketStructure::GetLastBOS(SmcStructureBreak &brk) const
  {
   if(!m_lastBOS.isValid)
      return false;
   brk = m_lastBOS;
   return true;
  }

//+------------------------------------------------------------------+
//| 直近CHoCH取得                                                      |
//+------------------------------------------------------------------+
bool CSmcMarketStructure::GetLastCHoCH(SmcStructureBreak &brk) const
  {
   if(!m_lastCHoCH.isValid)
      return false;
   brk = m_lastCHoCH;
   return true;
  }

//+------------------------------------------------------------------+
//| 直近でBOSがあったか                                                |
//+------------------------------------------------------------------+
bool CSmcMarketStructure::HasRecentBOS(const int withinBars) const
  {
   return m_lastBOS.isValid && m_lastBOS.barIndex <= withinBars;
  }

//+------------------------------------------------------------------+
//| 直近でCHoCHがあったか                                              |
//+------------------------------------------------------------------+
bool CSmcMarketStructure::HasRecentCHoCH(const int withinBars) const
  {
   return m_lastCHoCH.isValid && m_lastCHoCH.barIndex <= withinBars;
  }

//+------------------------------------------------------------------+
//| レンジ取得                                                         |
//+------------------------------------------------------------------+
bool CSmcMarketStructure::GetCurrentRange(SmcRangeInfo &range) const
  {
   if(!m_currentRange.isValid)
      return false;
   range = m_currentRange;
   return true;
  }

bool CSmcMarketStructure::IsInRange() const
  {
   return m_currentRange.isValid && !m_currentRange.isBroken;
  }

//+------------------------------------------------------------------+
//| エントリー方向取得                                                 |
//+------------------------------------------------------------------+
ENUM_ENTRY_SIGNAL CSmcMarketStructure::GetEntryDirection() const
  {
   if(m_lastCHoCH.isValid && m_lastCHoCH.barIndex <= 10)
      return m_lastCHoCH.isBullish ? SIGNAL_BUY : SIGNAL_SELL;

   if(m_lastBOS.isValid && m_lastBOS.barIndex <= 10)
      return m_lastBOS.isBullish ? SIGNAL_BUY : SIGNAL_SELL;

   if(m_currentTrend == SMC_TREND_BULLISH)
      return SIGNAL_BUY;
   if(m_currentTrend == SMC_TREND_BEARISH)
      return SIGNAL_SELL;

   return SIGNAL_WAIT;
  }

//+------------------------------------------------------------------+
//| 構造分析メイン                                                     |
//+------------------------------------------------------------------+
void CSmcMarketStructure::AnalyzeStructure()
  {
   DetectTrend();
   DetectStructureBreaks();
   DetectRange();
  }

//+------------------------------------------------------------------+
//| トレンド検出                                                       |
//+------------------------------------------------------------------+
void CSmcMarketStructure::DetectTrend()
  {
   m_previousTrend = m_currentTrend;
   m_currentTrend  = m_swingPoints.GetTrendDirection();
  }

//+------------------------------------------------------------------+
//| 構造ブレイク検出 (BOS / CHoCH)                                    |
//+------------------------------------------------------------------+
void CSmcMarketStructure::DetectStructureBreaks()
  {
   m_lastBOS.Init();
   m_lastCHoCH.Init();

   if(m_swingPoints.GetHighCount() < 2 || m_swingPoints.GetLowCount() < 2)
      return;

   SmcSwingPoint lastHigh, prevHigh, lastLow, prevLow;
   m_swingPoints.GetSwingHigh(0, lastHigh);
   m_swingPoints.GetSwingHigh(1, prevHigh);
   m_swingPoints.GetSwingLow(0, lastLow);
   m_swingPoints.GetSwingLow(1, prevLow);

//--- 直近数バーでのブレイクをチェック
   for(int i = 1; i <= 10; i++)
     {
      double high  = High(i);
      double low   = Low(i);
      datetime time = Time(i);

      //--- 上方ブレイク
      if(high > lastHigh.price && i < lastHigh.barIndex)
        {
         if(m_previousTrend == SMC_TREND_BULLISH || m_currentTrend == SMC_TREND_BULLISH)
           {
            //--- BOS (上昇トレンド継続)
            if(!m_lastBOS.isValid || time > m_lastBOS.time)
              {
               m_lastBOS.type       = STRUCT_BOS;
               m_lastBOS.breakPrice = high;
               m_lastBOS.swingPrice = lastHigh.price;
               m_lastBOS.time       = time;
               m_lastBOS.barIndex   = i;
               m_lastBOS.isBullish  = true;
               m_lastBOS.isValid    = true;
              }
           }
         else if(m_previousTrend == SMC_TREND_BEARISH)
           {
            //--- CHoCH (下降→上昇転換)
            if(!m_lastCHoCH.isValid || time > m_lastCHoCH.time)
              {
               m_lastCHoCH.type       = STRUCT_CHOCH;
               m_lastCHoCH.breakPrice = high;
               m_lastCHoCH.swingPrice = lastHigh.price;
               m_lastCHoCH.time       = time;
               m_lastCHoCH.barIndex   = i;
               m_lastCHoCH.isBullish  = true;
               m_lastCHoCH.isValid    = true;
              }
           }
        }

      //--- 下方ブレイク
      if(low < lastLow.price && i < lastLow.barIndex)
        {
         if(m_previousTrend == SMC_TREND_BEARISH || m_currentTrend == SMC_TREND_BEARISH)
           {
            //--- BOS (下降トレンド継続)
            if(!m_lastBOS.isValid || time > m_lastBOS.time)
              {
               m_lastBOS.type       = STRUCT_BOS;
               m_lastBOS.breakPrice = low;
               m_lastBOS.swingPrice = lastLow.price;
               m_lastBOS.time       = time;
               m_lastBOS.barIndex   = i;
               m_lastBOS.isBullish  = false;
               m_lastBOS.isValid    = true;
              }
           }
         else if(m_previousTrend == SMC_TREND_BULLISH)
           {
            //--- CHoCH (上昇→下降転換)
            if(!m_lastCHoCH.isValid || time > m_lastCHoCH.time)
              {
               m_lastCHoCH.type       = STRUCT_CHOCH;
               m_lastCHoCH.breakPrice = low;
               m_lastCHoCH.swingPrice = lastLow.price;
               m_lastCHoCH.time       = time;
               m_lastCHoCH.barIndex   = i;
               m_lastCHoCH.isBullish  = false;
               m_lastCHoCH.isValid    = true;
              }
           }
        }
     }

//--- 履歴に追加
   if(m_lastBOS.isValid)
      AddBreakToHistory(m_lastBOS);
   if(m_lastCHoCH.isValid)
      AddBreakToHistory(m_lastCHoCH);
  }

//+------------------------------------------------------------------+
//| レンジ検出                                                         |
//+------------------------------------------------------------------+
void CSmcMarketStructure::DetectRange()
  {
   m_currentRange.Init();

   if(m_swingPoints.GetHighCount() < 2 || m_swingPoints.GetLowCount() < 2)
      return;

//--- HH/LLが長期間更新されない場合はレンジ
   SmcSwingPoint sh0, sh1, sl0, sl1;
   m_swingPoints.GetSwingHigh(0, sh0);
   m_swingPoints.GetSwingHigh(1, sh1);
   m_swingPoints.GetSwingLow(0, sl0);
   m_swingPoints.GetSwingLow(1, sl1);

   bool noHH = sh0.price <= sh1.price;
   bool noLL = sl0.price >= sl1.price;

   if(noHH && noLL)
     {
      m_currentRange.highPrice = MathMax(sh0.price, sh1.price);
      m_currentRange.lowPrice  = MathMin(sl0.price, sl1.price);
      m_currentRange.startTime = MathMin(sh1.time, sl1.time);
      m_currentRange.startBar  = MathMax(sh1.barIndex, sl1.barIndex);
      m_currentRange.duration  = m_currentRange.startBar;
      m_currentRange.isValid   = m_currentRange.duration >= m_minRangeBars;

      //--- レンジブレイクチェック
      double currentClose = Close(0);
      if(currentClose > m_currentRange.highPrice)
        {
         m_currentRange.isBroken       = true;
         m_currentRange.isBullishBreak = true;
         m_currentRange.breakTime      = Time(0);
        }
      else if(currentClose < m_currentRange.lowPrice)
        {
         m_currentRange.isBroken       = true;
         m_currentRange.isBullishBreak = false;
         m_currentRange.breakTime      = Time(0);
        }
     }
  }

//+------------------------------------------------------------------+
//| ブレイク履歴追加                                                   |
//+------------------------------------------------------------------+
void CSmcMarketStructure::AddBreakToHistory(const SmcStructureBreak &brk)
  {
   if(m_breakCount >= m_maxBreaks)
     {
      //--- 最古のものを削除してシフト
      for(int i = 0; i < m_maxBreaks - 1; i++)
         m_breakHistory[i] = m_breakHistory[i + 1];
      m_breakCount = m_maxBreaks - 1;
     }
   m_breakHistory[m_breakCount] = brk;
   m_breakCount++;
  }

//+------------------------------------------------------------------+
//| 構造ブレイク描画                                                   |
//+------------------------------------------------------------------+
void CSmcMarketStructure::DrawStructure()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);

//--- BOS描画
   if(m_lastBOS.isValid)
     {
      string name = m_prefix + "BOS";
      color clr   = m_lastBOS.isBullish ? m_colorBOSBull : m_colorBOSBear;
      CSmcDrawing::DrawTrendLine(name, m_lastBOS.time, m_lastBOS.swingPrice,
                                 Time(0), m_lastBOS.swingPrice, clr, 2, STYLE_DASH);

      string label = m_prefix + "BOS_LBL";
      CSmcDrawing::DrawText(label, m_lastBOS.time, m_lastBOS.swingPrice,
                            "BOS", clr, 9);
     }

//--- CHoCH描画
   if(m_lastCHoCH.isValid)
     {
      string name = m_prefix + "CHOCH";
      CSmcDrawing::DrawTrendLine(name, m_lastCHoCH.time, m_lastCHoCH.swingPrice,
                                 Time(0), m_lastCHoCH.swingPrice, m_colorCHoCH, 2, STYLE_DOT);

      string label = m_prefix + "CHOCH_LBL";
      CSmcDrawing::DrawText(label, m_lastCHoCH.time, m_lastCHoCH.swingPrice,
                            "CHoCH", m_colorCHoCH, 9);
     }

//--- レンジ描画
   if(m_currentRange.isValid && !m_currentRange.isBroken)
     {
      string name = m_prefix + "RANGE";
      CSmcDrawing::DrawZone(name, m_currentRange.startTime, m_currentRange.highPrice,
                            Time(0), m_currentRange.lowPrice, m_colorRange, 20);
     }

   CSmcDrawing::Redraw();
  }

#endif // __SMC_MARKET_STRUCTURE_MQH__
//+------------------------------------------------------------------+
