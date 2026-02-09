//+------------------------------------------------------------------+
//|                                          OptimalTradeEntry.mqh   |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_OPTIMAL_TRADE_ENTRY_MQH__
#define __SMC_OPTIMAL_TRADE_ENTRY_MQH__

#include "SwingPoints.mqh"

//+------------------------------------------------------------------+
//| CSmcOptimalTradeEntry - OTE (Fibonacci ベースエントリー)           |
//|                                                                    |
//| スイングH/L間のFibリトレースメント OTE Zone: 0.618-0.786          |
//+------------------------------------------------------------------+
class CSmcOptimalTradeEntry : public CSmcBase
  {
private:
   CSmcSwingPoints  *m_swingPoints;
   bool              m_ownSwing;

   SmcOTEZone        m_currentOTE;

   color             m_colorOTE;
   color             m_colorFib;

public:
                     CSmcOptimalTradeEntry();
                    ~CSmcOptimalTradeEntry();

   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false,
                          CSmcSwingPoints *swingPoints = NULL);
   virtual bool      Update();
   virtual void      Clean();

   //--- OTEゾーン
   bool              GetOTEZone(SmcOTEZone &ote) const;
   bool              IsInOTEZone() const;
   bool              IsInOTEZone(const double price) const;

   //--- Fibレベル
   double            GetFibLevel(const double level) const;
   double            GetFib236() const { return GetFibLevel(0.236); }
   double            GetFib382() const { return GetFibLevel(0.382); }
   double            GetFib500() const { return GetFibLevel(0.500); }
   double            GetFib618() const { return GetFibLevel(0.618); }
   double            GetFib705() const { return GetFibLevel(0.705); }
   double            GetFib786() const { return GetFibLevel(0.786); }

   CSmcSwingPoints  *SwingPoints() { return m_swingPoints; }

private:
   void              Calculate();
   void              DrawOTE();
  };

//+------------------------------------------------------------------+
CSmcOptimalTradeEntry::CSmcOptimalTradeEntry()
   : m_swingPoints(NULL)
   , m_ownSwing(false)
   , m_colorOTE(C'255,165,0')
   , m_colorFib(clrGray)
  {
   m_currentOTE.Init();
  }

CSmcOptimalTradeEntry::~CSmcOptimalTradeEntry()
  {
   if(m_ownSwing && m_swingPoints != NULL)
      delete m_swingPoints;
  }

//+------------------------------------------------------------------+
bool CSmcOptimalTradeEntry::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                                 const bool enableDraw, CSmcSwingPoints *swingPoints)
  {
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   m_prefix = "SMC_OTE_";

   if(swingPoints != NULL)
     { m_swingPoints = swingPoints; m_ownSwing = false; }
   else
     {
      m_swingPoints = new CSmcSwingPoints();
      if(!m_swingPoints.Init(symbol, timeframe, false))
        { delete m_swingPoints; m_swingPoints = NULL; return false; }
      m_ownSwing = true;
     }
   return true;
  }

//+------------------------------------------------------------------+
bool CSmcOptimalTradeEntry::Update()
  {
   if(!m_initialized || m_swingPoints == NULL)
      return false;

   if(m_ownSwing)
      m_swingPoints.Update();

   Calculate();

   if(m_enableDraw && m_currentOTE.isValid)
      DrawOTE();

   return true;
  }

void CSmcOptimalTradeEntry::Clean()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   CSmcDrawing::Redraw();
  }

//+------------------------------------------------------------------+
bool CSmcOptimalTradeEntry::GetOTEZone(SmcOTEZone &ote) const
  {
   if(!m_currentOTE.isValid)
      return false;
   ote = m_currentOTE;
   return true;
  }

bool CSmcOptimalTradeEntry::IsInOTEZone() const
  {
   return IsInOTEZone(SymbolInfoDouble(m_symbol, SYMBOL_BID));
  }

bool CSmcOptimalTradeEntry::IsInOTEZone(const double price) const
  {
   if(!m_currentOTE.isValid)
      return false;

   double top    = m_currentOTE.GetOTETop();
   double bottom = m_currentOTE.GetOTEBottom();

   // Ensure top > bottom
   if(top < bottom)
     { double tmp = top; top = bottom; bottom = tmp; }

   return (price >= bottom && price <= top);
  }

//+------------------------------------------------------------------+
double CSmcOptimalTradeEntry::GetFibLevel(const double level) const
  {
   if(!m_currentOTE.isValid)
      return 0;

   double range = m_currentOTE.swingHigh - m_currentOTE.swingLow;

   if(m_currentOTE.isBullish)
      return m_currentOTE.swingHigh - range * level;
   else
      return m_currentOTE.swingLow + range * level;
  }

//+------------------------------------------------------------------+
void CSmcOptimalTradeEntry::Calculate()
  {
   m_currentOTE.Init();

   if(m_swingPoints.GetHighCount() < 1 || m_swingPoints.GetLowCount() < 1)
      return;

   SmcSwingPoint sh, sl;
   m_swingPoints.GetSwingHigh(0, sh);
   m_swingPoints.GetSwingLow(0, sl);

   m_currentOTE.swingHigh = sh.price;
   m_currentOTE.swingLow  = sl.price;

//--- 方向: 最新のスイングがハイならBearishリトレース、ローならBullishリトレース
   m_currentOTE.isBullish = (sl.barIndex < sh.barIndex);

   double range = sh.price - sl.price;
   if(range <= 0)
      return;

   if(m_currentOTE.isBullish)
     {
      //--- 上昇 -> 押し目 (高値から下へリトレース)
      m_currentOTE.fibLevel618 = sh.price - range * 0.618;
      m_currentOTE.fibLevel705 = sh.price - range * 0.705;
      m_currentOTE.fibLevel786 = sh.price - range * 0.786;
      m_currentOTE.fibLevel50  = sh.price - range * 0.500;
     }
   else
     {
      //--- 下降 -> 戻り (安値から上へリトレース)
      m_currentOTE.fibLevel618 = sl.price + range * 0.618;
      m_currentOTE.fibLevel705 = sl.price + range * 0.705;
      m_currentOTE.fibLevel786 = sl.price + range * 0.786;
      m_currentOTE.fibLevel50  = sl.price + range * 0.500;
     }

   m_currentOTE.isValid = true;
  }

//+------------------------------------------------------------------+
void CSmcOptimalTradeEntry::DrawOTE()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);

   SmcSwingPoint sh, sl;
   m_swingPoints.GetSwingHigh(0, sh);
   m_swingPoints.GetSwingLow(0, sl);
   datetime startTime = MathMin(sh.time, sl.time);

   //--- OTE Zone (0.618 - 0.786)
   double oteTop    = MathMax(m_currentOTE.fibLevel618, m_currentOTE.fibLevel786);
   double oteBottom = MathMin(m_currentOTE.fibLevel618, m_currentOTE.fibLevel786);

   CSmcDrawing::DrawZone(m_prefix + "ZONE", startTime, oteTop,
                         Time(0), oteBottom, m_colorOTE, 20);
   CSmcDrawing::DrawText(m_prefix + "ZONE_L", startTime,
                         m_currentOTE.fibLevel705,
                         "OTE", m_colorOTE, 9);

   //--- Fib levels
   double fibLevels[] = {0.236, 0.382, 0.500, 0.618, 0.705, 0.786};
   string fibNames[]  = {"23.6", "38.2", "50.0", "61.8", "70.5", "78.6"};

   for(int i = 0; i < ArraySize(fibLevels); i++)
     {
      double price = GetFibLevel(fibLevels[i]);
      string name  = m_prefix + "FIB_" + IntegerToString(i);
      CSmcDrawing::DrawHLine(name, price, m_colorFib, 1, STYLE_DOT);

      string label = m_prefix + "FIB_L_" + IntegerToString(i);
      CSmcDrawing::DrawText(label, startTime, price, fibNames[i] + "%", m_colorFib, 7);
     }

   CSmcDrawing::Redraw();
  }

#endif // __SMC_OPTIMAL_TRADE_ENTRY_MQH__
//+------------------------------------------------------------------+
