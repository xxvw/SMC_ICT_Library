//+------------------------------------------------------------------+
//| KillZone.mqh — session windows in explicit broker or GMT time     |
//| Copyright 2025-2026, ICT_Library_MQ5                              |
//+------------------------------------------------------------------+
#property strict
#ifndef __SMC_KILL_ZONE_MQH__
#define __SMC_KILL_ZONE_MQH__

#include "Core/SmcDrawing.mqh"
#include "Utils/TimeUtils.mqh"

class CSmcKillZone : public CSmcBase
  {
private:
   SmcSessionInfo    m_sessions[4];
   datetime         m_sessionStart[4];
   datetime         m_sessionEnd[4];
   bool             m_available[4];
   int              m_gmtOffset;
   bool             m_brokerTime;
   bool             m_overlapEnabled;
   datetime         m_evaluationTime;
   ENUM_SMC_SESSION m_currentSession;
   bool             m_inKillZone;
   MqlRates         m_minutes[];
   bool             m_sharedMinutes;
   bool             m_minutesValid;
   datetime         m_coverageStart;
   datetime         m_coverageEnd;

public:
                     CSmcKillZone();
                    ~CSmcKillZone() {}
   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false, const int gmtOffset = 2);
   virtual bool      Update();
   virtual void      Clean();

   // Legacy GMT windows: server time minus the explicitly supplied offset.
   void              SetGMTOffset(const int offset) { m_gmtOffset = offset; m_brokerTime = false; ClearRanges(); }
   // New APIs use broker-clock session definitions without timezone inference.
   void              UseBrokerTime(const bool enabled = true) { m_brokerTime = enabled; ClearRanges(); }
   // Typed configuration defines three independent windows; disable the
   // legacy fixed overlap when those windows do not use its default hours.
   void              SetOverlapEnabled(const bool enabled) { m_overlapEnabled = enabled; ClearRanges(); }
   void              SetEvaluationTime(const datetime asOf) { m_evaluationTime = asOf; }
   bool              SetMinuteRates(const MqlRates &rates[], const datetime coverageStart,
                                    const datetime coverageEnd);
   void              SetSessionTime(const ENUM_SMC_SESSION session,
                                    const int startHour, const int startMin,
                                    const int endHour, const int endMin);
   ENUM_SMC_SESSION  GetCurrentSession() const { return m_currentSession; }
   bool              IsInKillZone() const { return m_inKillZone; }
   bool              IsInSession(const ENUM_SMC_SESSION session) const;
   string            GetSessionName(const ENUM_SMC_SESSION session) const;
   bool              GetSessionInfo(const ENUM_SMC_SESSION session, SmcSessionInfo &info) const;
   bool              GetSessionBounds(const ENUM_SMC_SESSION session, datetime &start, datetime &end) const;
   double            GetSessionHigh(const ENUM_SMC_SESSION session) const;
   double            GetSessionLow(const ENUM_SMC_SESSION session) const;
   double            GetSessionOpen(const ENUM_SMC_SESSION session) const;
   double            GetSessionRange(const ENUM_SMC_SESSION session) const;

private:
   void              InitDefaultSessions();
   void              ClearRanges();
   datetime          EvaluationTime() const { return m_evaluationTime > 0 ? m_evaluationTime : TimeCurrent(); }
   int               Offset() const { return m_brokerTime ? 0 : m_gmtOffset; }
   bool              ReadSession(const int index, const datetime until);
   void              DrawKillZones();
  };

CSmcKillZone::CSmcKillZone()
   : m_gmtOffset(2), m_brokerTime(false), m_overlapEnabled(true), m_evaluationTime(0),
     m_currentSession(SESSION_NONE), m_inKillZone(false),
     m_sharedMinutes(false), m_minutesValid(false), m_coverageStart(0), m_coverageEnd(0)
  {
   InitDefaultSessions();
  }

bool CSmcKillZone::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                      const bool enableDraw, const int gmtOffset)
  {
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;
   SetModulePrefix("KZ");
   m_gmtOffset = gmtOffset;
   m_brokerTime = false;
   m_overlapEnabled = true;
   m_evaluationTime = 0;
   m_sharedMinutes = false;
   m_minutesValid = false;
   ArrayResize(m_minutes, 0);
   InitDefaultSessions();
   return true;
  }

void CSmcKillZone::InitDefaultSessions()
  {
   for(int i = 0; i < 4; i++)
      m_sessions[i].Init();
   m_sessions[0].session = SESSION_ASIAN;
   m_sessions[1].session = SESSION_LONDON;
   m_sessions[2].session = SESSION_NEWYORK;
   m_sessions[3].session = SESSION_LDN_NY_OL;
   SetSessionTime(SESSION_ASIAN, 0, 0, 8, 0);
   SetSessionTime(SESSION_LONDON, 7, 0, 16, 0);
   SetSessionTime(SESSION_NEWYORK, 12, 0, 21, 0);
   SetSessionTime(SESSION_LDN_NY_OL, 12, 0, 16, 0);
   ClearRanges();
  }

void CSmcKillZone::ClearRanges()
  {
   m_currentSession = SESSION_NONE;
   m_inKillZone = false;
   for(int i = 0; i < 4; i++)
     {
      m_available[i] = false;
      m_sessionStart[i] = 0;
      m_sessionEnd[i] = 0;
      m_sessions[i].sessionHigh = 0;
      m_sessions[i].sessionLow = 0;
      m_sessions[i].sessionOpen = 0;
      m_sessions[i].isActive = false;
     }
  }

bool CSmcKillZone::SetMinuteRates(const MqlRates &rates[], const datetime coverageStart,
                                const datetime coverageEnd)
  {
   m_sharedMinutes = true;
   m_minutesValid = false;
   ArrayResize(m_minutes, 0);
   ClearRanges();
   if(coverageStart <= 0 || coverageEnd <= coverageStart || ArraySize(rates) == 0)
      return false;
   for(int i = 0; i < ArraySize(rates); i++)
     {
      if(rates[i].time < coverageStart || rates[i].time >= coverageEnd ||
         (i > 0 && rates[i].time <= rates[i-1].time) ||
         !MathIsValidNumber(rates[i].open) || !MathIsValidNumber(rates[i].close) ||
         !MathIsValidNumber(rates[i].high) || !MathIsValidNumber(rates[i].low) ||
         rates[i].high < MathMax(rates[i].open, rates[i].close) ||
         rates[i].low > MathMin(rates[i].open, rates[i].close) ||
         rates[i].high < rates[i].low)
         return false;
     }
   if(ArrayCopy(m_minutes, rates) != ArraySize(rates))
      return false;
   ArraySetAsSeries(m_minutes, false);
   m_coverageStart = coverageStart;
   m_coverageEnd = coverageEnd;
   m_minutesValid = true;
   return true;
  }

void CSmcKillZone::SetSessionTime(const ENUM_SMC_SESSION session,
                                const int startHour, const int startMin,
                                const int endHour, const int endMin)
  {
   if(startHour < 0 || startHour > 23 || endHour < 0 || endHour > 23 ||
      startMin < 0 || startMin > 59 || endMin < 0 || endMin > 59)
      return;
   for(int i = 0; i < 4; i++)
      if(m_sessions[i].session == session)
        {
         m_sessions[i].startHourGMT = startHour;
         m_sessions[i].startMinGMT = startMin;
         m_sessions[i].endHourGMT = endHour;
         m_sessions[i].endMinGMT = endMin;
         ClearRanges();
         return;
        }
  }

bool CSmcKillZone::ReadSession(const int index, const datetime until)
  {
   // Closed M1 observations only: a historical 01:00 candle is not fully
   // known at 01:00:30, even when CopyRates already contains its final OHLC.
   datetime observedUntil = until - (until % 60);
   datetime start = m_sessionStart[index];
   if(observedUntil <= start)
      return true; // A newly opened window has no observations yet.
   MqlRates rates[];
   int count = 0;
   if(m_sharedMinutes)
     {
      if(!m_minutesValid || m_coverageStart > start || m_coverageEnd < observedUntil)
         return false;
      ArrayCopy(rates, m_minutes);
      count = ArraySize(rates);
     }
   else
     {
      ResetLastError();
      count = CopyRates(m_symbol, PERIOD_M1, start, observedUntil - 1, rates);
      if(count <= 0 || !SeriesInfoInteger(m_symbol, PERIOD_M1, SERIES_SYNCHRONIZED) ||
         (datetime)SeriesInfoInteger(m_symbol, PERIOD_M1, SERIES_FIRSTDATE) > start)
         return false;
     }
   ArraySetAsSeries(rates, false);
   bool found = false;
   for(int i = 0; i < count; i++)
     {
      if(rates[i].time < start || rates[i].time + 60 > observedUntil)
         continue;
      if(!found)
        {
         m_sessions[index].sessionOpen = rates[i].open;
         m_sessions[index].sessionHigh = rates[i].high;
         m_sessions[index].sessionLow = rates[i].low;
         found = true;
        }
      else
        {
         m_sessions[index].sessionHigh = MathMax(m_sessions[index].sessionHigh, rates[i].high);
         m_sessions[index].sessionLow = MathMin(m_sessions[index].sessionLow, rates[i].low);
        }
     }
   m_available[index] = found;
   return found;
  }

bool CSmcKillZone::Update()
  {
   ClearRanges();
   if(!m_initialized || EvaluationTime() <= 0)
      return false;
   datetime now = EvaluationTime();
   MqlDateTime day;
   TimeToStruct(CSmcTimeUtils::ToGMT(now, Offset()), day);
   day.hour = 0; day.min = 0; day.sec = 0;
   datetime dayStart = CSmcTimeUtils::FromGMT(StructToTime(day), Offset());
   for(int i = 0; i < 4; i++)
     {
      if(m_sessions[i].session == SESSION_LDN_NY_OL && !m_overlapEnabled)
         continue;
      if(!CSmcTimeUtils::SessionBounds(now,
          m_sessions[i].startHourGMT, m_sessions[i].startMinGMT,
          m_sessions[i].endHourGMT, m_sessions[i].endMinGMT, Offset(),
          m_sessionStart[i], m_sessionEnd[i]))
         return false;
      // Discard prior-day sessions; retain overnight windows ending today.
      if(m_sessionEnd[i] <= dayStart)
         continue;
      datetime until = now < m_sessionEnd[i] ? now : m_sessionEnd[i];
      if(!ReadSession(i, until))
        {
         ClearRanges();
         if(m_enableDraw) Clean();
         return false;
        }
      m_sessions[i].isActive = now >= m_sessionStart[i] && now < m_sessionEnd[i];
      if(m_sessions[i].isActive)
        {
         m_inKillZone = true;
         if(m_sessions[i].session != SESSION_LDN_NY_OL)
            m_currentSession = m_sessions[i].session;
        }
     }
   if(m_enableDraw)
      DrawKillZones();
   return true;
  }

void CSmcKillZone::Clean()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   CSmcDrawing::Redraw();
  }

bool CSmcKillZone::IsInSession(const ENUM_SMC_SESSION session) const
  {
   for(int i = 0; i < 4; i++)
      if(m_sessions[i].session == session)
         return m_sessions[i].isActive;
   return false;
  }

string CSmcKillZone::GetSessionName(const ENUM_SMC_SESSION session) const
  {
   switch(session)
     {
      case SESSION_ASIAN: return "Asian";
      case SESSION_LONDON: return "London";
      case SESSION_NEWYORK: return "New York";
      case SESSION_LDN_NY_OL: return "LDN-NY Overlap";
      default: return "None";
     }
  }

bool CSmcKillZone::GetSessionInfo(const ENUM_SMC_SESSION session, SmcSessionInfo &info) const
  {
   info.Init();
   for(int i = 0; i < 4; i++)
      if(m_sessions[i].session == session && m_available[i])
        { info = m_sessions[i]; return true; }
   return false;
  }

bool CSmcKillZone::GetSessionBounds(const ENUM_SMC_SESSION session, datetime &start, datetime &end) const
  {
   start = 0; end = 0;
   for(int i = 0; i < 4; i++)
      if(m_sessions[i].session == session && m_available[i])
        { start = m_sessionStart[i]; end = m_sessionEnd[i]; return true; }
   return false;
  }

double CSmcKillZone::GetSessionHigh(const ENUM_SMC_SESSION session) const
  {
   SmcSessionInfo info;
   return GetSessionInfo(session, info) ? info.sessionHigh : 0;
  }
double CSmcKillZone::GetSessionLow(const ENUM_SMC_SESSION session) const
  {
   SmcSessionInfo info;
   return GetSessionInfo(session, info) ? info.sessionLow : 0;
  }
double CSmcKillZone::GetSessionOpen(const ENUM_SMC_SESSION session) const
  {
   SmcSessionInfo info;
   return GetSessionInfo(session, info) ? info.sessionOpen : 0;
  }
double CSmcKillZone::GetSessionRange(const ENUM_SMC_SESSION session) const
  {
   SmcSessionInfo info;
   return GetSessionInfo(session, info) ? info.GetRange() : 0;
  }

void CSmcKillZone::DrawKillZones()
  {
   Clean();
   for(int i = 0; i < 4; i++)
     {
      if(!m_available[i]) continue;
      color colours[4] = {C'50,50,100', C'50,100,50', C'100,50,50', C'100,100,50'};
      string name = m_prefix + GetSessionName(m_sessions[i].session);
      datetime until = EvaluationTime() < m_sessionEnd[i] ? EvaluationTime() : m_sessionEnd[i];
      CSmcDrawing::DrawZone(name, m_sessionStart[i], m_sessions[i].sessionHigh,
                           until, m_sessions[i].sessionLow, colours[i], 10);
      CSmcDrawing::DrawText(name + "_L", until, m_sessions[i].sessionHigh,
                           GetSessionName(m_sessions[i].session), colours[i], 8);
     }
   CSmcDrawing::Redraw();
  }

#endif
