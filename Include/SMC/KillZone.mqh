//+------------------------------------------------------------------+
//|                                                     KillZone.mqh |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_KILL_ZONE_MQH__
#define __SMC_KILL_ZONE_MQH__

#include "Core/SmcDrawing.mqh"

//+------------------------------------------------------------------+
//| CSmcKillZone - ICT Kill Zone (セッションタイムフィルター)          |
//|                                                                    |
//| Asian:  00:00-08:00 GMT                                            |
//| London: 07:00-16:00 GMT (KZ: 02:00-05:00 NY Time)                |
//| NY:     12:00-21:00 GMT (KZ: 07:00-10:00 NY Time)                |
//| Overlap: 12:00-16:00 GMT                                           |
//+------------------------------------------------------------------+
class CSmcKillZone : public CSmcBase
  {
private:
   //--- セッション定義
   SmcSessionInfo    m_sessions[4];   // Asian, London, NY, Overlap
   int               m_gmtOffset;     // ブローカーGMTオフセット (時間)

   //--- 状態
   ENUM_SMC_SESSION  m_currentSession;
   bool              m_inKillZone;

   //--- 描画色
   color             m_colorAsian;
   color             m_colorLondon;
   color             m_colorNY;
   color             m_colorOverlap;

public:
                     CSmcKillZone();
                    ~CSmcKillZone();

   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false,
                          const int gmtOffset = 2);
   virtual bool      Update();
   virtual void      Clean();

   //--- 設定
   void              SetGMTOffset(const int offset) { m_gmtOffset = offset; }
   void              SetSessionTime(const ENUM_SMC_SESSION session,
                                    const int startHour, const int startMin,
                                    const int endHour, const int endMin);

   //--- 判定
   ENUM_SMC_SESSION  GetCurrentSession() const { return m_currentSession; }
   bool              IsInKillZone()      const { return m_inKillZone; }
   bool              IsInSession(const ENUM_SMC_SESSION session) const;
   string            GetSessionName(const ENUM_SMC_SESSION session) const;

   //--- セッション情報
   bool              GetSessionInfo(const ENUM_SMC_SESSION session, SmcSessionInfo &info) const;
   double            GetSessionHigh(const ENUM_SMC_SESSION session) const;
   double            GetSessionLow(const ENUM_SMC_SESSION session) const;
   double            GetSessionOpen(const ENUM_SMC_SESSION session) const;
   double            GetSessionRange(const ENUM_SMC_SESSION session) const;

private:
   void              InitDefaultSessions();
   void              UpdateCurrentSession();
   void              UpdateSessionHL();
   int               GetCurrentHourGMT() const;
   int               GetCurrentMinuteGMT() const;
   bool              IsTimeInRange(const int hourGMT, const int minGMT,
                                   const int startH, const int startM,
                                   const int endH, const int endM) const;
   void              DrawKillZones();
  };

//+------------------------------------------------------------------+
CSmcKillZone::CSmcKillZone()
   : m_gmtOffset(2)
   , m_currentSession(SESSION_NONE)
   , m_inKillZone(false)
   , m_colorAsian(C'50,50,100')
   , m_colorLondon(C'50,100,50')
   , m_colorNY(C'100,50,50')
   , m_colorOverlap(C'100,100,50')
  {
  }

CSmcKillZone::~CSmcKillZone() {}

//+------------------------------------------------------------------+
bool CSmcKillZone::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                        const bool enableDraw, const int gmtOffset)
  {
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   m_prefix    = "SMC_KZ_";
   m_gmtOffset = gmtOffset;

   InitDefaultSessions();
   return true;
  }

//+------------------------------------------------------------------+
void CSmcKillZone::InitDefaultSessions()
  {
//--- Asian Session: 00:00-08:00 GMT
   m_sessions[0].session      = SESSION_ASIAN;
   m_sessions[0].startHourGMT = 0;
   m_sessions[0].startMinGMT  = 0;
   m_sessions[0].endHourGMT   = 8;
   m_sessions[0].endMinGMT    = 0;

//--- London Session: 07:00-16:00 GMT
   m_sessions[1].session      = SESSION_LONDON;
   m_sessions[1].startHourGMT = 7;
   m_sessions[1].startMinGMT  = 0;
   m_sessions[1].endHourGMT   = 16;
   m_sessions[1].endMinGMT    = 0;

//--- NY Session: 12:00-21:00 GMT
   m_sessions[2].session      = SESSION_NEWYORK;
   m_sessions[2].startHourGMT = 12;
   m_sessions[2].startMinGMT  = 0;
   m_sessions[2].endHourGMT   = 21;
   m_sessions[2].endMinGMT    = 0;

//--- London-NY Overlap: 12:00-16:00 GMT
   m_sessions[3].session      = SESSION_LDN_NY_OL;
   m_sessions[3].startHourGMT = 12;
   m_sessions[3].startMinGMT  = 0;
   m_sessions[3].endHourGMT   = 16;
   m_sessions[3].endMinGMT    = 0;
  }

//+------------------------------------------------------------------+
bool CSmcKillZone::Update()
  {
   if(!m_initialized)
      return false;

   UpdateCurrentSession();
   UpdateSessionHL();

   if(m_enableDraw)
      DrawKillZones();

   return true;
  }

void CSmcKillZone::Clean()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   CSmcDrawing::Redraw();
  }

//+------------------------------------------------------------------+
void CSmcKillZone::SetSessionTime(const ENUM_SMC_SESSION session,
                                  const int startHour, const int startMin,
                                  const int endHour, const int endMin)
  {
   for(int i = 0; i < 4; i++)
     {
      if(m_sessions[i].session == session)
        {
         m_sessions[i].startHourGMT = startHour;
         m_sessions[i].startMinGMT  = startMin;
         m_sessions[i].endHourGMT   = endHour;
         m_sessions[i].endMinGMT    = endMin;
         break;
        }
     }
  }

//+------------------------------------------------------------------+
bool CSmcKillZone::IsInSession(const ENUM_SMC_SESSION session) const
  {
   int hourGMT = GetCurrentHourGMT();
   int minGMT  = GetCurrentMinuteGMT();

   for(int i = 0; i < 4; i++)
      if(m_sessions[i].session == session)
         return IsTimeInRange(hourGMT, minGMT,
                              m_sessions[i].startHourGMT, m_sessions[i].startMinGMT,
                              m_sessions[i].endHourGMT, m_sessions[i].endMinGMT);
   return false;
  }

string CSmcKillZone::GetSessionName(const ENUM_SMC_SESSION session) const
  {
   switch(session)
     {
      case SESSION_ASIAN:    return "Asian";
      case SESSION_LONDON:   return "London";
      case SESSION_NEWYORK:  return "New York";
      case SESSION_LDN_NY_OL: return "LDN-NY Overlap";
      default:               return "None";
     }
  }

//+------------------------------------------------------------------+
bool CSmcKillZone::GetSessionInfo(const ENUM_SMC_SESSION session, SmcSessionInfo &info) const
  {
   for(int i = 0; i < 4; i++)
      if(m_sessions[i].session == session)
        { info = m_sessions[i]; return true; }
   return false;
  }

double CSmcKillZone::GetSessionHigh(const ENUM_SMC_SESSION session) const
  {
   for(int i = 0; i < 4; i++)
      if(m_sessions[i].session == session)
         return m_sessions[i].sessionHigh;
   return 0;
  }

double CSmcKillZone::GetSessionLow(const ENUM_SMC_SESSION session) const
  {
   for(int i = 0; i < 4; i++)
      if(m_sessions[i].session == session)
         return m_sessions[i].sessionLow;
   return 0;
  }

double CSmcKillZone::GetSessionOpen(const ENUM_SMC_SESSION session) const
  {
   for(int i = 0; i < 4; i++)
      if(m_sessions[i].session == session)
         return m_sessions[i].sessionOpen;
   return 0;
  }

double CSmcKillZone::GetSessionRange(const ENUM_SMC_SESSION session) const
  {
   for(int i = 0; i < 4; i++)
      if(m_sessions[i].session == session)
         return m_sessions[i].GetRange();
   return 0;
  }

//+------------------------------------------------------------------+
void CSmcKillZone::UpdateCurrentSession()
  {
   int hourGMT = GetCurrentHourGMT();
   int minGMT  = GetCurrentMinuteGMT();

   m_currentSession = SESSION_NONE;
   m_inKillZone     = false;

   for(int i = 0; i < 4; i++)
     {
      bool active = IsTimeInRange(hourGMT, minGMT,
                                  m_sessions[i].startHourGMT, m_sessions[i].startMinGMT,
                                  m_sessions[i].endHourGMT, m_sessions[i].endMinGMT);
      m_sessions[i].isActive = active;
      if(active && m_sessions[i].session != SESSION_LDN_NY_OL)
         m_currentSession = m_sessions[i].session;
      if(active)
         m_inKillZone = true;
     }
  }

//+------------------------------------------------------------------+
void CSmcKillZone::UpdateSessionHL()
  {
   for(int s = 0; s < 4; s++)
     {
      if(!m_sessions[s].isActive)
         continue;

      m_sessions[s].sessionHigh = 0;
      m_sessions[s].sessionLow  = DBL_MAX;
      m_sessions[s].sessionOpen = Open(0);

      //--- 現在のセッション内のバーを遡って H/L を計算
      for(int i = 0; i < 100; i++)
        {
         datetime barTime = Time(i);
         MqlDateTime dt;
         TimeToStruct(barTime, dt);
         int barHourGMT = dt.hour - m_gmtOffset;
         if(barHourGMT < 0) barHourGMT += 24;
         int barMinGMT = dt.min;

         if(!IsTimeInRange(barHourGMT, barMinGMT,
                           m_sessions[s].startHourGMT, m_sessions[s].startMinGMT,
                           m_sessions[s].endHourGMT, m_sessions[s].endMinGMT))
            break;

         if(High(i) > m_sessions[s].sessionHigh)
            m_sessions[s].sessionHigh = High(i);
         if(Low(i) < m_sessions[s].sessionLow)
            m_sessions[s].sessionLow = Low(i);

         m_sessions[s].sessionOpen = Open(i);
        }

      if(m_sessions[s].sessionLow == DBL_MAX)
         m_sessions[s].sessionLow = 0;
     }
  }

//+------------------------------------------------------------------+
int CSmcKillZone::GetCurrentHourGMT() const
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hourGMT = dt.hour - m_gmtOffset;
   if(hourGMT < 0) hourGMT += 24;
   if(hourGMT >= 24) hourGMT -= 24;
   return hourGMT;
  }

int CSmcKillZone::GetCurrentMinuteGMT() const
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.min;
  }

bool CSmcKillZone::IsTimeInRange(const int hourGMT, const int minGMT,
                                 const int startH, const int startM,
                                 const int endH, const int endM) const
  {
   int current = hourGMT * 60 + minGMT;
   int start   = startH * 60 + startM;
   int end     = endH * 60 + endM;

   if(start < end)
      return (current >= start && current < end);
   else
      return (current >= start || current < end);
  }

//+------------------------------------------------------------------+
void CSmcKillZone::DrawKillZones()
  {
   // Session boxes are drawn only for active sessions on the current day
   for(int s = 0; s < 4; s++)
     {
      if(!m_sessions[s].isActive)
         continue;

      string name = m_prefix + GetSessionName(m_sessions[s].session);
      color clr;
      switch(m_sessions[s].session)
        {
         case SESSION_ASIAN:    clr = m_colorAsian; break;
         case SESSION_LONDON:   clr = m_colorLondon; break;
         case SESSION_NEWYORK:  clr = m_colorNY; break;
         case SESSION_LDN_NY_OL: clr = m_colorOverlap; break;
         default: clr = clrGray;
        }

      if(m_sessions[s].sessionHigh > 0 && m_sessions[s].sessionLow > 0)
        {
         CSmcDrawing::DrawZone(name,
                               m_sessions[s].sessionOpen > 0 ? Time(50) : Time(20),
                               m_sessions[s].sessionHigh, Time(0),
                               m_sessions[s].sessionLow, clr, 10);

         string label = m_prefix + "L_" + GetSessionName(m_sessions[s].session);
         CSmcDrawing::DrawText(label, Time(0), m_sessions[s].sessionHigh,
                               GetSessionName(m_sessions[s].session), clr, 8);
        }
     }

   CSmcDrawing::Redraw();
  }

#endif // __SMC_KILL_ZONE_MQH__
//+------------------------------------------------------------------+
