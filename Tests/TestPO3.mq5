#include "../Include/SMC/ICT/PowerOfThree.mqh"
#include "TestHarness.mqh"

void PO3Bar(MqlRates &rate,const datetime time,const double open,const double high,
             const double low,const double close)
  {
   ZeroMemory(rate);
   rate.time=time;
   rate.open=open;
   rate.high=high;
   rate.low=low;
   rate.close=close;
  }

void PO3Fixture(MqlRates &rates[],MqlRates &minutes[],const datetime day)
  {
   ArrayResize(rates,5);
   for(int i=0;i<3;i++) PO3Bar(rates[i],day+8*3600-180+i*60,104,107,103,105);
   PO3Bar(rates[3],day+8*3600,105,107,99,106);
   PO3Bar(rates[4],day+8*3600+60,106,113,105,112);
   ArrayResize(minutes,2);
   PO3Bar(minutes[0],day,104,110,100,105);
   PO3Bar(minutes[1],day+8*3600-60,104,109,101,105);
  }

int PO3Stage(const SmcSnapshot &snapshot,const string state)
  {
   for(int i=0;i<ArraySize(snapshot.records);i++)
      if(snapshot.records[i].concept==ICT_PO3 && snapshot.records[i].state==state) return i;
   return -1;
  }

ENUM_SMC_STATUS PO3Status(const SmcSnapshot &snapshot)
  {
   for(int i=0;i<ArraySize(snapshot.modules);i++)
      if(snapshot.modules[i].concept==ICT_PO3) return snapshot.modules[i].status;
   return SMC_STATUS_ERROR;
  }

void OnStart()
  {
   TestBegin("power-of-three");
   datetime day=D'2026.09.14';
   SmcConfig config;
   config.SetDefaults();
   config.displacementBaseline=3;
   MqlRates rates[],minutes[];
   PO3Fixture(rates,minutes,day);
   SmcSnapshot snapshot;
   snapshot.Reset();
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,1,snapshot,day,day+8*3600+120);
   TestEqual(PO3Status(snapshot),SMC_STATUS_READY,"Covered completed accumulation is ready");
   TestEqual(ArraySize(snapshot.records),3,"A successful cycle preserves all three stages");
   int accumulation=PO3Stage(snapshot,"ACCUMULATION");
   int manipulation=PO3Stage(snapshot,"MANIPULATION");
   int distribution=PO3Stage(snapshot,"DISTRIBUTION");
   TestAssert(accumulation>=0 && manipulation>=0 && distribution>=0,"Expected stage chain exists");
   string manipulationId="";
   datetime manipulationTime=0;
   if(accumulation>=0 && manipulation>=0 && distribution>=0)
     {
      TestEqual(snapshot.records[accumulation].confirmedAt,day+8*3600,"Accumulation is known only at session completion");
      TestEqual(snapshot.records[manipulation].confirmedAt,day+8*3600+60,"Sweep uses the bar closing timestamp");
      TestEqual(snapshot.records[distribution].confirmedAt,day+8*3600+120,"Distribution requires a later closed bar");
      TestAssert(snapshot.records[manipulation].relatedId==snapshot.records[accumulation].id,"Manipulation links accumulation");
      TestAssert(snapshot.records[distribution].relatedId==snapshot.records[manipulation].id,"Distribution links manipulation");
      TestEqual(snapshot.records[distribution].direction,1,"Low sweep produces bullish distribution");
      TestNear(snapshot.records[distribution].referencePrice,99,0,"Sweep extreme retained");
      TestNear(snapshot.records[distribution].comparisonPrice,112,0,"Distribution close retained");
      TestAssert(!snapshot.records[accumulation].active && !snapshot.records[manipulation].active &&
                 !snapshot.records[distribution].active,"Completed stage chain is inactive");
      manipulationId=snapshot.records[manipulation].id;
      manipulationTime=snapshot.records[manipulation].confirmedAt;
     }
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,1,snapshot,day,day+8*3600+120);
   TestEqual(ArraySize(snapshot.records),3,"Same history cannot duplicate stages");

   ArrayResize(rates,4);
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,1,snapshot,day,day+8*3600+120);
   TestEqual(ArraySize(snapshot.records),2,"Prefix exposes only already confirmed stages");
   manipulation=PO3Stage(snapshot,"MANIPULATION");
   if(manipulation>=0)
     {
      TestAssert(snapshot.records[manipulation].active,"Current manipulation is active");
      TestAssert(snapshot.records[manipulation].id==manipulationId,"Future bars cannot change earlier stage identity");
      TestEqual(snapshot.records[manipulation].confirmedAt,manipulationTime,"Future bars cannot alter earlier confirmation");
     }
   TestEqual(PO3Stage(snapshot,"DISTRIBUTION"),-1,"No same-bar distribution");

   PO3Fixture(rates,minutes,day);
   PO3Bar(rates[3],day+8*3600,105,111,99,106);
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,1,snapshot,day,day+9*3600);
   int invalid=PO3Stage(snapshot,"INVALIDATED");
   TestAssert(invalid>=0,"Both-side sweep invalidates ambiguous cycle");
   if(invalid>=0) TestAssert(snapshot.records[invalid].reason=="ambiguous_both_side_sweep","Ambiguous sweep reason reported");
   TestEqual(PO3Stage(snapshot,"DISTRIBUTION"),-1,"Ambiguous cycle cannot later distribute");

   PO3Fixture(rates,minutes,day);
   PO3Bar(rates[4],day+8*3600+60,105,107,98,99);
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,1,snapshot,day,day+9*3600);
   invalid=PO3Stage(snapshot,"INVALIDATED");
   TestAssert(invalid>=0,"Closing through manipulation side invalidates cycle");
   if(invalid>=0) TestAssert(snapshot.records[invalid].reason=="close_through_manipulation_side","Wrong-side close reason reported");

   PO3Fixture(rates,minutes,day);
   PO3Bar(rates[3],day+8*3600,105,111,104,106);
   PO3Bar(rates[4],day+8*3600+60,106,107,97,98);
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,1,snapshot,day,day+9*3600);
   distribution=PO3Stage(snapshot,"DISTRIBUTION");
   TestAssert(distribution>=0,"High sweep permits bearish distribution");
   if(distribution>=0) TestEqual(snapshot.records[distribution].direction,-1,"Bearish direction retained");

   PO3Fixture(rates,minutes,day);
   config.po3ExpiryBars=2;
   ArrayResize(rates,6);
   for(int i=4;i<6;i++) PO3Bar(rates[i],day+8*3600+(i-3)*60,105,107,104,106);
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,1,snapshot,day,day+9*3600);
   int expired=PO3Stage(snapshot,"EXPIRED");
   TestAssert(expired>=0,"Cycle expires after configured subsequent-bar opportunities");
   if(expired>=0)
     {
      TestAssert(snapshot.records[expired].reason=="manipulation_window_elapsed","Bar expiry reason reported");
      TestEqual(snapshot.records[expired].confirmedAt,day+8*3600+180,"Expiry is known at final unsuccessful opportunity close");
     }
   PO3Bar(rates[5],day+8*3600+120,106,113,105,112);
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,1,snapshot,day,day+9*3600);
   TestAssert(PO3Stage(snapshot,"DISTRIBUTION")>=0,"Distribution on final permitted opportunity is accepted");

   PO3Fixture(rates,minutes,day);
   PO3Bar(rates[4],day+86400,105,107,104,106);
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,1,snapshot,day,day+86400+60);
   expired=PO3Stage(snapshot,"EXPIRED");
   TestAssert(expired>=0,"Next accumulation session expires a pending cycle");
   if(expired>=0) TestEqual(snapshot.records[expired].confirmedAt,day+86400,"Expiry timestamp is exact session start");

   PO3Fixture(rates,minutes,day);
   minutes[0].time=day+60;
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,1,snapshot);
   TestEqual(PO3Status(snapshot),SMC_STATUS_NOT_READY,"Unproven M1 coverage cannot create PO3");
   TestEqual(ArraySize(snapshot.records),0,"Missing source history clears stale cycles");
   config.enablePO3=false;
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,1,snapshot);
   TestEqual(PO3Status(snapshot),SMC_STATUS_DISABLED,"PO3 can be disabled explicitly");

   // Literal decimal prices exercise binary round-off on both sweep and
   // closing-break predicates, rather than only testing the helper directly.
   config.SetDefaults();
   config.displacementBaseline=3;
   ArrayResize(rates,5);
   ArrayResize(minutes,2);
   for(int i=0;i<3;i++) PO3Bar(rates[i],day+8*3600-180+i*60,0.14,0.17,0.13,0.15);
   PO3Bar(minutes[0],day,0.14,0.2,0.1,0.15);
   PO3Bar(minutes[1],day+8*3600-60,0.14,0.19,0.11,0.15);
   PO3Bar(rates[3],day+8*3600,0.14,0.17,0.0,0.15);
   PO3Bar(rates[4],day+8*3600+60,0.15,0.32,0.14,0.3);
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,0.1,snapshot,day,day+9*3600);
   distribution=PO3Stage(snapshot,"DISTRIBUTION");
   TestAssert(distribution>=0,"Exact decimal upward closing tick confirms distribution");
   if(distribution>=0) TestEqual(snapshot.records[distribution].direction,1,"Decimal upward distribution is bullish");

   PO3Bar(rates[3],day+8*3600,0.14,0.3,0.12,0.15);
   PO3Bar(rates[4],day+8*3600+60,0.15,0.17,-0.01,0.0);
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,0.1,snapshot,day,day+9*3600);
   TestAssert(PO3Stage(snapshot,"MANIPULATION")>=0,"Exact decimal high sweep is recognized");
   distribution=PO3Stage(snapshot,"DISTRIBUTION");
   TestAssert(distribution>=0,"Decimal high sweep can lead to bearish distribution");
   if(distribution>=0) TestEqual(snapshot.records[distribution].direction,-1,"Decimal high sweep sets bearish direction");
   PO3Bar(rates[4],day+8*3600+60,0.15,0.31,0.14,0.3);
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,0.1,snapshot,day,day+9*3600);
   invalid=PO3Stage(snapshot,"INVALIDATED");
   TestAssert(invalid>=0 && snapshot.records[invalid].reason=="close_through_manipulation_side",
              "Exact upward wrong-side decimal closing tick invalidates cycle");
   ArrayResize(rates,4);
   PO3Bar(rates[3],day+8*3600,0.14,0.2999,0.12,0.15);
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,0.1,snapshot,day,day+9*3600);
   TestEqual(PO3Stage(snapshot,"MANIPULATION"),-1,"Materially sub-tick high sweep remains rejected");

   ArrayResize(rates,5);
   for(int i=0;i<3;i++) PO3Bar(rates[i],day+8*3600-180+i*60,0.34,0.37,0.33,0.35);
   PO3Bar(minutes[0],day,0.34,0.4,0.3,0.35);
   PO3Bar(minutes[1],day+8*3600-60,0.34,0.39,0.31,0.35);
   PO3Bar(rates[3],day+8*3600,0.34,0.37,0.2,0.35);
   PO3Bar(rates[4],day+8*3600+60,0.35,0.37,0.2,0.2);
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,0.1,snapshot,day,day+9*3600);
   TestAssert(PO3Stage(snapshot,"MANIPULATION")>=0,"Exact decimal low sweep is recognized");
   invalid=PO3Stage(snapshot,"INVALIDATED");
   TestAssert(invalid>=0 && snapshot.records[invalid].reason=="close_through_manipulation_side",
              "Exact downward wrong-side decimal closing tick invalidates cycle");
   PO3Bar(rates[3],day+8*3600,0.34,0.5,0.32,0.35);
   PO3Bar(rates[4],day+8*3600+60,0.35,0.37,0.19,0.2);
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,0.1,snapshot,day,day+9*3600);
   TestAssert(PO3Stage(snapshot,"DISTRIBUTION")>=0,"Exact decimal downward closing tick confirms distribution");
   ArrayResize(rates,4);
   PO3Bar(rates[3],day+8*3600,0.34,0.5,0.2,0.35);
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,0.1,snapshot,day,day+9*3600);
   invalid=PO3Stage(snapshot,"INVALIDATED");
   TestAssert(invalid>=0 && snapshot.records[invalid].reason=="ambiguous_both_side_sweep",
              "Two exact decimal sweep thresholds are recognized as ambiguous");
   PO3Bar(rates[3],day+8*3600,0.34,0.37,0.2001,0.35);
   SmcDetectPO3(rates,minutes,config,"TEST",PERIOD_M1,0.1,snapshot,day,day+9*3600);
   TestEqual(PO3Stage(snapshot,"MANIPULATION"),-1,"Materially sub-tick low sweep remains rejected");
   TestFinish();
  }
