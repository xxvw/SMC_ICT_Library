#include "../Include/SMC/ICT/SessionRanges.mqh"
#include "TestHarness.mqh"

void SessionBar(MqlRates &rate,const datetime time,const double high,const double low)
  {
   ZeroMemory(rate);
   rate.time=time;
   rate.high=high;
   rate.low=low;
   rate.open=(high+low)/2;
   rate.close=rate.open;
  }

int FindSession(const SmcSnapshot &snapshot,const string name,const ENUM_SMC_CONCEPT concept)
  {
   for(int i=0;i<ArraySize(snapshot.records);i++)
      if(snapshot.records[i].concept==concept && snapshot.records[i].reason==name) return i;
   return -1;
  }

ENUM_SMC_STATUS SessionStatus(const SmcSnapshot &snapshot)
  {
   for(int i=0;i<ArraySize(snapshot.modules);i++)
      if(snapshot.modules[i].concept==ICT_SESSION_HIGH) return snapshot.modules[i].status;
   return SMC_STATUS_ERROR;
  }

void OnStart()
  {
   TestBegin("sessions");
   datetime day=D'2026.09.14';
   SmcConfig config;
   config.SetDefaults();
   MqlRates primary[],minutes[];
   ArrayResize(primary,1);
   SessionBar(primary[0],day+21*3600,110,90);
   ArrayResize(minutes,7);
   SessionBar(minutes[0],day,105,95);
   SessionBar(minutes[1],day+7*3600,107,96);
   SessionBar(minutes[2],day+8*3600,999,94);
   SessionBar(minutes[3],day+12*3600,120,92);
   SessionBar(minutes[4],day+16*3600,777,91);
   SessionBar(minutes[5],day+21*3600-60,130,90);
   SessionBar(minutes[6],day+21*3600,12345,1);
   SmcSnapshot snapshot;
   snapshot.Reset();
   SmcDetectSessions(primary,minutes,config,"TEST",PERIOD_M1,snapshot,day,day+21*3600+60);
   TestEqual(SessionStatus(snapshot),SMC_STATUS_READY,"Sparse synchronized session history is complete");
   TestEqual(ArraySize(snapshot.records),6,"Three completed ranges expose two levels each");
   int asian=FindSession(snapshot,"Asian",ICT_SESSION_HIGH);
   TestAssert(asian>=0,"Asian range present");
   if(asian>=0)
     {
      TestNear(snapshot.records[asian].upper,107,0,"Session end minute excluded");
      TestEqual(snapshot.records[asian].confirmedAt,day+8*3600,"Session confirms at broker end");
      TestAssert(snapshot.records[asian].state=="COMPLETE","Only completed session levels are published");
     }
   int london=FindSession(snapshot,"London",ICT_SESSION_HIGH);
   int ny=FindSession(snapshot,"NewYork",ICT_SESSION_HIGH);
   if(london>=0) TestNear(snapshot.records[london].upper,999,0,"London includes start and excludes end");
   if(ny>=0) TestNear(snapshot.records[ny].upper,777,0,"New York excludes after-session spike");
   string oldId=asian>=0 ? snapshot.records[asian].id : "";
   SmcDetectSessions(primary,minutes,config,"TEST",PERIOD_M1,snapshot,day,day+21*3600+60);
   TestEqual(ArraySize(snapshot.records),6,"Repeated evaluation has no duplicate records");
   asian=FindSession(snapshot,"Asian",ICT_SESSION_HIGH);
   if(asian>=0) TestAssert(snapshot.records[asian].id==oldId,"Session identity is stable");

   // An explicit coverage attestation is necessary if the array starts after
   // a session boundary. Missing minutes may be inactivity but are not guessed.
   minutes[0].time=day+60;
   SmcDetectSessions(primary,minutes,config,"TEST",PERIOD_M1,snapshot);
   TestEqual(SessionStatus(snapshot),SMC_STATUS_PARTIAL,"Unknown session start coverage is not ready");
   TestEqual(FindSession(snapshot,"Asian",ICT_SESSION_HIGH),-1,"Incomplete prior range is never published");

   config.sessions[0].startMinute=22*60;
   config.sessions[0].endMinute=2*60;
   ArrayResize(minutes,5);
   SessionBar(minutes[0],day+22*3600,110,95);
   SessionBar(minutes[1],day+24*3600-60,120,94);
   SessionBar(minutes[2],day+24*3600,115,80);
   SessionBar(minutes[3],day+26*3600-60,130,93);
   SessionBar(minutes[4],day+26*3600,999,1);
   SessionBar(primary[0],day+26*3600,110,90);
   SmcDetectSessions(primary,minutes,config,"TEST",PERIOD_M1,snapshot,day,day+26*3600+60);
   asian=FindSession(snapshot,"Asian",ICT_SESSION_HIGH);
   TestAssert(asian>=0,"Cross-midnight range completes on next day");
   if(asian>=0)
     {
      TestNear(snapshot.records[asian].upper,130,0,"Cross-midnight end exclusion");
      TestEqual(snapshot.records[asian].periodStart,day+22*3600,"Range belongs to its starting broker date");
      TestEqual(snapshot.records[asian].periodEnd,day+26*3600,"Cross-midnight end advances one day");
     }
   int low=FindSession(snapshot,"Asian",ICT_SESSION_LOW);
   if(low>=0) TestNear(snapshot.records[low].lower,80,0,"Midnight prices remain in previous day's session");
   // A later candle must not repair an earlier coverage failure implicitly.
   config.SetDefaults();
   SessionBar(primary[0],day+8*3600-60,110,90);
   ArrayResize(minutes,2);
   SessionBar(minutes[0],day,110,100);
   SessionBar(minutes[1],day+7*3600,109,101);
   SmcDetectSessions(primary,minutes,config,"TEST",PERIOD_M1,snapshot);
   TestEqual(FindSession(snapshot,"Asian",ICT_SESSION_HIGH),-1,"Incomplete implicit end coverage excludes range");
   ArrayResize(minutes,3);
   SessionBar(minutes[2],day+8*3600+30*60,999,1);
   SmcDetectSessions(primary,minutes,config,"TEST",PERIOD_M1,snapshot);
   TestEqual(FindSession(snapshot,"Asian",ICT_SESSION_HIGH),-1,"Future M1 candle cannot certify earlier coverage");
   ArrayResize(minutes,0);
   SmcDetectSessions(primary,minutes,config,"TEST",PERIOD_M1,snapshot,day,day+26*3600+60);
   TestEqual(SessionStatus(snapshot),SMC_STATUS_NOT_READY,"Covered but empty sessions are unavailable");
   TestEqual(ArraySize(snapshot.records),0,"History failure clears stale levels");
   config.enableCalendar=false;
   SmcDetectSessions(primary,minutes,config,"TEST",PERIOD_M1,snapshot);
   TestEqual(SessionStatus(snapshot),SMC_STATUS_DISABLED,"Calendar disable is explicit");
   TestFinish();
  }
