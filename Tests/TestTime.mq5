#property strict
#include "TestHarness.mqh"
#include <SMC/KillZone.mqh>

class CTestKillZone : public CSmcKillZone
  {
public:
   void Activate()
     {
      m_initialized = true;
      SetModulePrefix("TIME_TEST");
      SetSessionTime(SESSION_ASIAN, 22, 0, 2, 0);
      SetSessionTime(SESSION_LONDON, 22, 0, 2, 0);
      SetSessionTime(SESSION_NEWYORK, 22, 0, 2, 0);
      SetSessionTime(SESSION_LDN_NY_OL, 22, 0, 2, 0);
     }
  };

void OnStart()
  {
   TestBegin("time-and-sessions");
   datetime start, end;
   TestAssert(CSmcTimeUtils::SessionBounds(D'2026.01.06 01:00', 22, 0, 2, 0, 0, start, end), "overnight window resolves");
   TestEqual(start, D'2026.01.05 22:00', "overnight belongs to prior trading date");
   TestEqual(end, D'2026.01.06 02:00', "overnight end crosses date");
   TestAssert(CSmcTimeUtils::IsInSessionAt(D'2026.01.05 22:00', 22, 0, 2, 0), "start is inclusive");
   TestAssert(!CSmcTimeUtils::IsInSessionAt(D'2026.01.06 02:00', 22, 0, 2, 0), "end is exclusive");
   TestAssert(!CSmcTimeUtils::IsInSessionAt(D'2026.01.06 15:00', 22, 0, 2, 0), "afternoon is outside overnight session");
   TestAssert(CSmcTimeUtils::SessionBounds(D'2026.01.06 02:00', 23, 30, 0, 45, 2, start, end), "GMT offset and minute boundaries resolve");
   TestEqual(start, D'2026.01.06 01:30', "GMT start converted to broker next date");
   TestEqual(end, D'2026.01.06 02:45', "GMT end converted to broker date");
   TestAssert(CSmcTimeUtils::SessionBounds(D'2026.01.05 20:00', 0, 0, 8, 0, -5, start, end), "negative offset resolves");
   TestEqual(start, D'2026.01.05 19:00', "negative offset shifts server date backward");
   TestAssert(CSmcTimeUtils::IsInSessionAt(D'2026.01.06 15:00', 7, 0, 7, 0), "equal boundaries preserve full-day convention");
   TestAssert(!CSmcTimeUtils::SessionBounds(D'2026.01.06 01:00', 24, 0, 2, 0, 0, start, end), "invalid hour rejected");
   TestEqual(start, 0, "invalid result clears start");
   TestEqual(end, 0, "invalid result clears end");
   TestEqual(CSmcTimeUtils::ToGMT(D'2026.01.06 01:00', 2), D'2026.01.05 23:00', "legacy server-minus-offset conversion");
   TestEqual(CSmcTimeUtils::FromGMT(D'2026.01.05 23:00', 2), D'2026.01.06 01:00', "inverse offset crosses midnight");
   TestAssert(CSmcTimeUtils::IsDST(2, 3), "explicit broker DST adjustment");
   TestAssert(!CSmcTimeUtils::IsDST(2, 2), "no DST inferred from workstation timezone");

   MqlRates minutes[];
   ArrayResize(minutes, 360);
   ZeroMemory(minutes);
   datetime first = D'2026.01.05 21:00';
   for(int i = 0; i < ArraySize(minutes); i++)
     {
      minutes[i].time = first + i * 60;
      minutes[i].open = 100;
      minutes[i].close = 100;
      minutes[i].high = 101;
      minutes[i].low = 99;
     }
   minutes[30].high = 999;  // Prior to session start.
   minutes[61].high = 110;
   minutes[239].low = 90;
   minutes[240].high = 111; // Unknown until the 01:00 minute closes.
   minutes[300].high = 888; // Exact end is excluded.
   CTestKillZone zone;
   zone.Activate();
   zone.UseBrokerTime();
   zone.SetEvaluationTime(D'2026.01.06 01:00');
   TestAssert(zone.SetMinuteRates(minutes, first, first + 360 * 60), "shared chronological M1 context accepted");
   zone.SetEvaluationTime(D'2026.01.05 22:00');
   TestAssert(zone.Update(), "exact session opening has no missing observations yet");
   TestAssert(zone.IsInSession(SESSION_ASIAN), "module start boundary is inclusive before first closed minute");
   TestNear(zone.GetSessionHigh(SESSION_ASIAN), 0, 0, "opening has no fabricated price range");
   zone.SetEvaluationTime(D'2026.01.06 01:00:30');
   TestAssert(zone.Update(), "partial active overnight window evaluates");
   TestNear(zone.GetSessionHigh(SESSION_ASIAN), 110, 0, "all closed session minutes beyond 100 bars included without mid-minute lookahead");
   TestNear(zone.GetSessionLow(SESSION_ASIAN), 90, 0, "session low uses complete M1 range");
   TestNear(zone.GetSessionOpen(SESSION_ASIAN), 100, 0, "open from first session minute");
   TestAssert(zone.IsInSession(SESSION_ASIAN), "active session available");
   TestAssert(zone.GetSessionBounds(SESSION_ASIAN, start, end), "public bounds available");
   TestEqual(start, D'2026.01.05 22:00', "public session broker start");
   TestAssert(zone.Update(), "repeated evaluation succeeds");
   TestNear(zone.GetSessionHigh(SESSION_ASIAN), 110, 0, "repeated evaluation is deterministic");
   zone.SetGMTOffset(2);
   TestAssert(zone.Update(), "legacy explicit offset can be restored");
   TestNear(zone.GetSessionHigh(SESSION_ASIAN), 101, 0, "legacy GMT window starts at server midnight");
   zone.UseBrokerTime();
   zone.SetEvaluationTime(D'2026.01.06 03:00');
   TestAssert(zone.Update(), "completed overnight window retained on ending date");
   TestNear(zone.GetSessionHigh(SESSION_ASIAN), 111, 0, "later closed minute included and exact ending minute excluded");
   TestAssert(!zone.IsInSession(SESSION_ASIAN), "completed window inactive");
   minutes[1].time = minutes[0].time;
   TestAssert(!zone.SetMinuteRates(minutes, first, first + 360 * 60), "duplicate M1 timestamp rejected");
   TestAssert(!zone.Update(), "invalid injected context cannot fall back to old data");
   TestNear(zone.GetSessionHigh(SESSION_ASIAN), 0, 0, "failed update clears previous prices");
   TestAssert(!zone.IsInKillZone(), "missing data cannot enable trading filter");
   SmcSessionInfo info;
   info.sessionHigh = 999;
   TestAssert(!zone.GetSessionInfo(SESSION_ASIAN, info), "missing session reports unavailable");
   TestNear(info.sessionHigh, 0, 0, "failed getter clears output struct");
   minutes[1].time = minutes[0].time + 60;
   MqlRates partial[];
   ArrayResize(partial, 120);
   ArrayCopy(partial, minutes, 0, 0, 120);
   TestAssert(zone.SetMinuteRates(partial, first, first + 120 * 60), "valid but incomplete M1 coverage accepted as input");
   TestAssert(!zone.Update(), "required unobserved session tail fails instead of returning partial completed range");
   TestNear(zone.GetSessionLow(SESSION_ASIAN), 0, 0, "incomplete history clears all prior results");
   zone.SetSessionTime(SESSION_ASIAN, 7, 0, 16, 0);
   zone.SetSessionTime(SESSION_LONDON, 7, 0, 16, 0);
   zone.SetSessionTime(SESSION_NEWYORK, 7, 0, 16, 0);
   zone.SetSessionTime(SESSION_LDN_NY_OL, 7, 0, 16, 0);
   zone.SetEvaluationTime(D'2026.01.07 06:00');
   TestAssert(zone.Update(), "yesterday completed sessions are not required for current-day filter");
   TestNear(zone.GetSessionHigh(SESSION_ASIAN), 0, 0, "previous trading date never leaks into current results");
   TestFinish();
  }
