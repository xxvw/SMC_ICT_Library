#property strict
#property script_show_inputs

#include "TestHarness.mqh"
#include "../Include/SMC/ICT/BalancedPriceRange.mqh"

// All fixtures are chronological, CLOSED M1 bars with a one-unit tick/pip.
void BprBar(MqlRates &rates[],const int index,const double open,const double high,
            const double low,const double close)
  {
   rates[index].time=D'2026.01.05 00:00:00'+index*60;
   rates[index].open=open;
   rates[index].high=high;
   rates[index].low=low;
   rates[index].close=close;
   rates[index].tick_volume=1;
   rates[index].spread=0;
   rates[index].real_volume=0;
  }

void BprFixture(MqlRates &rates[])
  {
   ArrayResize(rates,6);
   ArraySetAsSeries(rates,false);
   BprBar(rates,0,98,100,96,99);
   BprBar(rates,1,99,113,98,111);
   BprBar(rates,2,111,114,110,113);
   BprBar(rates,3,113,115,112,114);
   BprBar(rates,4,113,114,102,103);
   BprBar(rates,5,103,104,100,101);
  }

void BprPrefix(const MqlRates &rates[],const int count,MqlRates &prefix[])
  {
   ArrayResize(prefix,count);
   ArraySetAsSeries(prefix,false);
   for(int i=0;i<count;i++) prefix[i]=rates[i];
  }

int BprPair(const SmcSnapshot &snapshot,const string older,const string newer)
  {
   for(int i=0;i<ArraySize(snapshot.records);i++)
      if(snapshot.records[i].concept == ICT_BPR &&
         snapshot.records[i].relatedId == older && snapshot.records[i].secondaryId == newer)
         return i;
   return -1;
  }

int BprPairCount(const SmcSnapshot &snapshot,const string older,const string newer)
  {
   int count=0;
   for(int i=0;i<ArraySize(snapshot.records);i++)
      if(snapshot.records[i].concept == ICT_BPR &&
         snapshot.records[i].relatedId == older && snapshot.records[i].secondaryId == newer)
         count++;
   return count;
  }

void BprStatus(const SmcSnapshot &snapshot,const ENUM_SMC_STATUS expected,const string label)
  {
   int found=-1;
   for(int i=0;i<ArraySize(snapshot.modules);i++)
      if(snapshot.modules[i].concept == ICT_BPR) { found=i; break; }
   TestAssert(found >= 0,label+" module exists");
   if(found >= 0) TestEqual(snapshot.modules[found].status,expected,label+" status");
  }

void BprIdentity(const SmcRecord &actual,const SmcRecord &expected,const string label)
  {
   TestAssert(actual.id == expected.id,label+" stable ID");
   TestEqual(actual.concept,ICT_BPR,label+" concept");
   TestEqual(actual.sourceTime,expected.sourceTime,label+" source time");
   TestEqual(actual.confirmedAt,expected.confirmedAt,label+" confirmation time");
   TestEqual(actual.direction,expected.direction,label+" direction");
   TestNear(actual.lower,expected.lower,1e-10,label+" lower");
   TestNear(actual.upper,expected.upper,1e-10,label+" upper");
   TestAssert(actual.relatedId == expected.relatedId,label+" older ancestor");
   TestAssert(actual.secondaryId == expected.secondaryId,label+" newer ancestor");
  }

void TestBprFormationAndLifecycle(const bool mirror)
  {
   MqlRates rates[];
   BprFixture(rates);
   ArrayResize(rates,9);
   BprBar(rates,6,102,104,100,102); // Exact proximal contact.
   BprBar(rates,7,102,107,100,102); // Exact midpoint.
   BprBar(rates,8,102,111,101,111); // Exactly one tick past distal boundary.
   if(mirror)
      for(int i=0;i<ArraySize(rates);i++)
        {
         double high=rates[i].high;
         rates[i].open=210-rates[i].open;
         rates[i].high=210-rates[i].low;
         rates[i].low=210-high;
         rates[i].close=210-rates[i].close;
        }
   const int direction=mirror ? 1 : -1;
   const string label=mirror ? "bullish BPR" : "bearish BPR";
   const string older=SmcRecordId(ICT_FVG,"TEST",PERIOD_M1,rates[1].time,-direction);
   const string newer=SmcRecordId(ICT_FVG,"TEST",PERIOD_M1,rates[4].time,direction);
   SmcConfig config;
   config.SetDefaults();
   SmcSnapshot snapshot;
   SmcRecord origin;
   origin.Init();
   string states[4]={"FRESH","TESTED","MITIGATED","BROKEN"};
   for(int count=3;count<=9;count++)
     {
      MqlRates prefix[];
      BprPrefix(rates,count,prefix);
      snapshot.Reset();
      TestAssert(SmcDetectBPR(prefix,config,"TEST",PERIOD_M1,1,1,snapshot),label+" replay succeeds");
      const int index=BprPair(snapshot,older,newer);
      if(count < 6)
        {
         TestAssert(index < 0,label+" cannot precede second source confirmation");
         continue;
        }
      TestAssert(index >= 0,label+" pair detected");
      if(index < 0) continue;
      TestEqual(BprPairCount(snapshot,older,newer),1,label+" one record per pair");
      BprStatus(snapshot,SMC_STATUS_READY,label);
      if(count == 6)
        {
         origin=snapshot.records[index];
         TestAssert(origin.id != "",label+" ID exists");
         TestEqual(origin.direction,direction,label+" follows newer source direction");
         TestNear(origin.lower,mirror ? 100 : 104,1e-10,label+" intersection lower");
         TestNear(origin.upper,mirror ? 106 : 110,1e-10,label+" intersection upper");
         TestEqual(origin.sourceTime,rates[4].time,label+" newer middle candle origin");
         TestEqual(origin.confirmedAt,rates[5].time+60,label+" third candle close confirms");
        }
      else BprIdentity(snapshot.records[index],origin,label+" prefix replay");
      TestAssert(snapshot.records[index].state == states[count-6],label+" expected lifecycle state");
      TestAssert(snapshot.records[index].active == (count < 9),label+" expected activity");
      TestEqual(snapshot.records[index].updatedAt,rates[count-1].time+60,label+" lifecycle timestamp");
      TestAssert(snapshot.records[index].reason == (count == 9 ? "close_through" : ""),label+" invalidation reason");
      const int previousCount=ArraySize(snapshot.records);
      TestAssert(SmcDetectBPR(prefix,config,"TEST",PERIOD_M1,1,1,snapshot),label+" repeated replay succeeds");
      TestEqual(ArraySize(snapshot.records),previousCount,label+" repeated replay does not append");
      TestEqual(BprPairCount(snapshot,older,newer),1,label+" repeated pair remains unique");
     }
  }

void TestBprOverlapAndGapThresholds()
  {
   MqlRates rates[];
   BprFixture(rates);
   SmcConfig config;
   config.SetDefaults();
   SmcSnapshot snapshot;
   const string older=SmcRecordId(ICT_FVG,"TEST",PERIOD_M1,rates[1].time,1);
   const string newer=SmcRecordId(ICT_FVG,"TEST",PERIOD_M1,rates[4].time,-1);
   rates[5].high=109;
   snapshot.Reset();
   TestAssert(SmcDetectBPR(rates,config,"TEST",PERIOD_M1,1,1,snapshot),"one-tick overlap replay");
   int index=BprPair(snapshot,older,newer);
   TestAssert(index >= 0,"exactly one-tick overlap accepted");
   if(index >= 0)
     {
      TestNear(snapshot.records[index].lower,109,1e-10,"one-tick overlap lower");
      TestNear(snapshot.records[index].upper,110,1e-10,"one-tick overlap upper");
     }
   rates[5].high=110;
   snapshot.Reset();
   TestAssert(SmcDetectBPR(rates,config,"TEST",PERIOD_M1,1,1,snapshot),"touch-only overlap replay");
   TestAssert(BprPair(snapshot,older,newer) < 0,"zero-width overlap rejected");
   rates[5].high=109.5;
   snapshot.Reset();
   TestAssert(SmcDetectBPR(rates,config,"TEST",PERIOD_M1,1,1,snapshot),"sub-tick overlap replay");
   TestAssert(BprPair(snapshot,older,newer) < 0,"positive but sub-tick overlap rejected");

   BprFixture(rates);
   config.minFvgPips=4;
   snapshot.Reset();
   TestAssert(SmcDetectBPR(rates,config,"TEST",PERIOD_M1,1,2,snapshot),"minimum gap inclusive replay");
   TestAssert(BprPair(snapshot,older,newer) >= 0,"eight-unit source accepted at four two-unit pips");
   config.minFvgPips=4.1;
   snapshot.Reset();
   TestAssert(SmcDetectBPR(rates,config,"TEST",PERIOD_M1,1,2,snapshot),"minimum gap rejection replay");
   TestAssert(BprPair(snapshot,older,newer) < 0,"source below configured minimum excludes pair");

   BprFixture(rates);
   rates[5].high=109;
   for(int i=0;i<ArraySize(rates);i++)
     {
      rates[i].open*=0.1;
      rates[i].high*=0.1;
      rates[i].low*=0.1;
      rates[i].close*=0.1;
     }
   config.SetDefaults();
   snapshot.Reset();
   TestAssert(SmcDetectBPR(rates,config,"TEST",PERIOD_M1,0.1,0.1,snapshot),"decimal tick replay");
   TestAssert(BprPair(snapshot,older,newer) >= 0,"decimal exact tick survives floating-point representation");
  }

void TestBprSeparationAndAncestors()
  {
   SmcConfig config;
   config.SetDefaults();
   config.lookbackBars=1;
   config.maxRecordsPerConcept=1;
   for(int separation=50;separation<=51;separation++)
     {
      MqlRates rates[];
      BprFixture(rates);
      const int last=2+separation;
      ArrayResize(rates,last+1);
      for(int i=3;i<last-1;i++) BprBar(rates,i,113,115,112,114);
      BprBar(rates,last-1,113,114,102,103);
      BprBar(rates,last,103,109,100,101);
      const string older=SmcRecordId(ICT_FVG,"TEST",PERIOD_M1,rates[1].time,1);
      const string newer=SmcRecordId(ICT_FVG,"TEST",PERIOD_M1,rates[last-1].time,-1);
      SmcSnapshot snapshot;
      snapshot.Reset();
      TestAssert(SmcDetectBPR(rates,config,"TEST",PERIOD_M1,1,1,snapshot),"separation boundary replay");
      const int index=BprPair(snapshot,older,newer);
      TestAssert((index >= 0) == (separation == 50),"separation 50 inclusive, 51 excluded despite old source");
      if(index >= 0) TestEqual(snapshot.records[index].confirmedAt,rates[last].time+60,"old ancestor confirms only with new source");
     }

   MqlRates rates[];
   BprFixture(rates);
   ArrayResize(rates,7);
   BprBar(rates,6,102,111,98,99); // Breaks old bullish FVG, not bearish BPR.
   SmcSnapshot snapshot;
   snapshot.Reset();
   TestAssert(SmcDetectBPR(rates,config,"TEST",PERIOD_M1,1,1,snapshot),"broken ancestor replay");
   const string older=SmcRecordId(ICT_FVG,"TEST",PERIOD_M1,rates[1].time,1);
   const string newer=SmcRecordId(ICT_FVG,"TEST",PERIOD_M1,rates[4].time,-1);
   const int index=BprPair(snapshot,older,newer);
   TestAssert(index >= 0,"broken old source must not erase historical pair");
   if(index >= 0)
     {
      TestAssert(snapshot.records[index].state == "MITIGATED","BPR lifecycle independent of broken ancestor");
      TestAssert(snapshot.records[index].active,"BPR remains active with broken ancestor");
     }
  }

void TestBprStrongestStateAndExpiry()
  {
   MqlRates rates[];
   BprFixture(rates);
   ArrayResize(rates,7);
   BprBar(rates,6,102,111,101,111);
   const string older=SmcRecordId(ICT_FVG,"TEST",PERIOD_M1,rates[1].time,1);
   const string newer=SmcRecordId(ICT_FVG,"TEST",PERIOD_M1,rates[4].time,-1);
   SmcConfig config;
   config.SetDefaults();
   SmcSnapshot snapshot;
   snapshot.Reset();
   TestAssert(SmcDetectBPR(rates,config,"TEST",PERIOD_M1,1,1,snapshot),"direct break replay");
   int index=BprPair(snapshot,older,newer);
   TestAssert(index >= 0,"direct break retains record");
   if(index >= 0)
     {
      TestAssert(snapshot.records[index].state == "BROKEN","close-through wins over same-bar touch and midpoint");
      TestAssert(snapshot.records[index].reason == "close_through","direct break reason");
     }

   BprFixture(rates);
   ArrayResize(rates,9);
   for(int i=6;i<=8;i++) BprBar(rates,i,102,103,100,102);
   config.maxZoneAge=2;
   for(int count=6;count<=9;count++)
     {
      MqlRates prefix[];
      BprPrefix(rates,count,prefix);
      snapshot.Reset();
      TestAssert(SmcDetectBPR(prefix,config,"TEST",PERIOD_M1,1,1,snapshot),"expiry prefix replay");
      index=BprPair(snapshot,older,newer);
      TestAssert(index >= 0,"expiry retains pair history");
      if(index < 0) continue;
      TestAssert(snapshot.records[index].state == "FRESH","expiry preserves strongest pre-expiry state");
      TestAssert(snapshot.records[index].active == (count < 9),"age equal to maximum active; greater age expires");
      TestAssert(snapshot.records[index].reason == (count == 9 ? "expired" : ""),"separate expiry reason");
     }
  }

void TestBprInputAndStatus()
  {
   SmcConfig config;
   config.SetDefaults();
   MqlRates rates[];
   BprFixture(rates);
   SmcSnapshot snapshot;
   snapshot.Reset();
   config.enableBPR=false;
   TestAssert(SmcDetectBPR(rates,config,"TEST",PERIOD_M1,1,1,snapshot),"disabled detector succeeds");
   BprStatus(snapshot,SMC_STATUS_DISABLED,"disabled");
   TestEqual(ArraySize(snapshot.records),0,"disabled detector emits no records");
   config.enableBPR=true;
   for(int count=0;count<=2;count++)
     {
      MqlRates prefix[];
      BprPrefix(rates,count,prefix);
      snapshot.Reset();
      TestAssert(SmcDetectBPR(prefix,config,"TEST",PERIOD_M1,1,1,snapshot),"missing history is handled");
      BprStatus(snapshot,SMC_STATUS_NOT_READY,"missing history");
      TestEqual(ArraySize(snapshot.records),0,"missing history emits no records");
     }
   rates[2].close=rates[2].high+1;
   snapshot.Reset();
   TestAssert(!SmcDetectBPR(rates,config,"TEST",PERIOD_M1,1,1,snapshot),"invalid OHLC rejected");
   BprStatus(snapshot,SMC_STATUS_ERROR,"invalid OHLC");
   TestEqual(ArraySize(snapshot.records),0,"invalid input emits no partial records");
   BprFixture(rates);
   rates[2].time=rates[1].time;
   snapshot.Reset();
   TestAssert(!SmcDetectBPR(rates,config,"TEST",PERIOD_M1,1,1,snapshot),"duplicate timestamps rejected");
   BprStatus(snapshot,SMC_STATUS_ERROR,"invalid timestamp");
  }

void OnStart()
  {
   TestBegin("BPR");
   TestBprFormationAndLifecycle(false);
   TestBprFormationAndLifecycle(true);
   TestBprOverlapAndGapThresholds();
   TestBprSeparationAndAncestors();
   TestBprStrongestStateAndExpiry();
   TestBprInputAndStatus();
   TestFinish();
  }
