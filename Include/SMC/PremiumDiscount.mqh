//+------------------------------------------------------------------+
//|                                              PremiumDiscount.mqh |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_PREMIUM_DISCOUNT_MQH__
#define __SMC_PREMIUM_DISCOUNT_MQH__

#include "SwingPoints.mqh"

//+------------------------------------------------------------------+
//| CSmcPremiumDiscount - Premium / Discount ゾーン                   |
//|                                                                    |
//| スイングH/Lの50%ラインをEquilibrium(均衡)とし、                    |
//| 上半分をPremium(プレミアム)、下半分をDiscount(ディスカウント)とする。|
//| Premium = 売りに有利、Discount = 買いに有利                        |
//+------------------------------------------------------------------+
class CSmcPremiumDiscount : public CSmcBase
  {
private:
   CSmcSwingPoints  *m_swingPoints;
   bool              m_ownSwing;

   double            m_swingHigh;      // 直近スイングハイ
   double            m_swingLow;       // 直近スイングロー
   double            m_equilibrium;    // 50% ライン
   double            m_currentPrice;   // 現在価格
   bool              m_dataValid;

   color             m_colorPremium;
   color             m_colorDiscount;
   color             m_colorEquilibrium;

public:
                     CSmcPremiumDiscount();
                    ~CSmcPremiumDiscount();

   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false,
                          CSmcSwingPoints *swingPoints = NULL);
   virtual bool      Update();
   virtual void      Clean();

   //--- ゾーン判定
   double            GetEquilibrium()   const { return m_equilibrium; }
   double            GetSwingHigh()     const { return m_swingHigh; }
   double            GetSwingLow()      const { return m_swingLow; }
   bool              IsPremium()        const;
   bool              IsDiscount()       const;
   bool              IsAtEquilibrium(const double tolerancePips = 5.0) const;

   //--- パーセンテージ取得
   double            GetZonePercent()   const;  // 0=SL, 50=EQ, 100=SH
   double            GetZonePercent(const double price) const;

   //--- スイングポイント参照
   CSmcSwingPoints  *SwingPoints()     { return m_swingPoints; }

private:
   void              Calculate();
   void              DrawZones();
  };

//+------------------------------------------------------------------+
CSmcPremiumDiscount::CSmcPremiumDiscount()
   : m_swingPoints(NULL)
   , m_ownSwing(false)
   , m_swingHigh(0)
   , m_swingLow(0)
   , m_equilibrium(0)
   , m_currentPrice(0)
   , m_dataValid(false)
   , m_colorPremium(C'200,50,50')
   , m_colorDiscount(C'50,150,50')
   , m_colorEquilibrium(clrGray)
  {
  }

CSmcPremiumDiscount::~CSmcPremiumDiscount()
  {
   if(m_ownSwing && m_swingPoints != NULL)
      delete m_swingPoints;
  }

//+------------------------------------------------------------------+
bool CSmcPremiumDiscount::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                               const bool enableDraw, CSmcSwingPoints *swingPoints)
  {
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   m_prefix = "SMC_PD_";

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
bool CSmcPremiumDiscount::Update()
  {
   if(!m_initialized || m_swingPoints == NULL)
      return false;

   if(m_ownSwing)
      m_swingPoints.Update();

   Calculate();

   if(m_enableDraw && m_dataValid)
      DrawZones();

   return true;
  }

void CSmcPremiumDiscount::Clean()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   CSmcDrawing::Redraw();
  }

//+------------------------------------------------------------------+
bool CSmcPremiumDiscount::IsPremium() const
  {
   if(!m_dataValid) return false;
   return m_currentPrice > m_equilibrium;
  }

bool CSmcPremiumDiscount::IsDiscount() const
  {
   if(!m_dataValid) return false;
   return m_currentPrice < m_equilibrium;
  }

bool CSmcPremiumDiscount::IsAtEquilibrium(const double tolerancePips) const
  {
   if(!m_dataValid) return false;
   return MathAbs(m_currentPrice - m_equilibrium) <= PipsToPrice(tolerancePips);
  }

double CSmcPremiumDiscount::GetZonePercent() const
  {
   return GetZonePercent(m_currentPrice);
  }

double CSmcPremiumDiscount::GetZonePercent(const double price) const
  {
   if(!m_dataValid || m_swingHigh == m_swingLow)
      return 50.0;
   return ((price - m_swingLow) / (m_swingHigh - m_swingLow)) * 100.0;
  }

//+------------------------------------------------------------------+
void CSmcPremiumDiscount::Calculate()
  {
   m_dataValid = false;

   if(m_swingPoints.GetHighCount() < 1 || m_swingPoints.GetLowCount() < 1)
      return;

   m_swingHigh    = m_swingPoints.GetHighPrice(0);
   m_swingLow     = m_swingPoints.GetLowPrice(0);
   m_equilibrium  = (m_swingHigh + m_swingLow) / 2.0;
   m_currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   m_dataValid    = (m_swingHigh > m_swingLow);
  }

//+------------------------------------------------------------------+
void CSmcPremiumDiscount::DrawZones()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);

   SmcSwingPoint sh, sl;
   m_swingPoints.GetSwingHigh(0, sh);
   m_swingPoints.GetSwingLow(0, sl);
   datetime startTime = MathMin(sh.time, sl.time);

   //--- Premium zone
   CSmcDrawing::DrawZone(m_prefix + "PREM", startTime, m_swingHigh,
                         Time(0), m_equilibrium, m_colorPremium, 15);
   CSmcDrawing::DrawText(m_prefix + "PREM_L", startTime,
                         (m_swingHigh + m_equilibrium) / 2.0,
                         "PREMIUM", m_colorPremium, 8);

   //--- Discount zone
   CSmcDrawing::DrawZone(m_prefix + "DISC", startTime, m_equilibrium,
                         Time(0), m_swingLow, m_colorDiscount, 15);
   CSmcDrawing::DrawText(m_prefix + "DISC_L", startTime,
                         (m_equilibrium + m_swingLow) / 2.0,
                         "DISCOUNT", m_colorDiscount, 8);

   //--- Equilibrium line
   CSmcDrawing::DrawHLine(m_prefix + "EQ", m_equilibrium,
                          m_colorEquilibrium, 1, STYLE_DASH);

   CSmcDrawing::Redraw();
  }

#endif // __SMC_PREMIUM_DISCOUNT_MQH__
//+------------------------------------------------------------------+
