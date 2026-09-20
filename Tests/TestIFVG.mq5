#property strict
#include <SMC/ICT/InverseFVG.mqh>
#include "TestHarness.mqh"

void IfvgBar(MqlRates &bar,const int index,const double o,const double h,
             const double l,const double c)
  {
   ZeroMemory(bar);
   bar.time=D'2026.01.05 00:00:00'+index*60;
   bar.open=o; bar.high=h; bar.low=l; bar.close=c;
  }

void IfvgFixture(MqlRates &bars[],const bool mirror=false)
  {
   ArrayResize(bars,9);
   IfvgBar(bars[0],0,100,102,98,101);
   IfvgBar(bars[1],1,101,111,100,110);
   IfvgBar(bars[2],2,110,113,108,112);
   IfvgBar(bars[3],3,110,112,100,104);
   IfvgBar(bars[4],4,104,108,101,102);
   IfvgBar(bars[5],5,102,104,100,101);
   IfvgBar(bars[6],6,101,102,99,100);
   IfvgBar(bars[7],7,100,105,99,101);
   IfvgBar(bars[8],8,101,109,100,109);
   if(mirror)
      for(int i=0;i<ArraySize(bars);i++)
        {
         double high=bars[i].high;
         bars[i].open=210-bars[i].open;
         bars[i].close=210-bars[i].close;
         bars[i].high=210-bars[i].low;
         bars[i].low=210-high;
        }
  }

void IfvgRun(const MqlRates &full[],const int length,const SmcConfig &config,
             SmcSnapshot &snapshot)
  {
   MqlRates prefix[];
   ArrayCopy(prefix,full,0,0,length);
   snapshot.Reset();
   TestAssert(SmcDetectIFVG(prefix,config,"TEST",PERIOD_M1,1.0,1.0,snapshot),"IFVG replay succeeds");
  }

void IfvgLifecycle(const bool mirror)
  {
   MqlRates full[];
   IfvgFixture(full,mirror);
   SmcConfig config;
   config.SetDefaults();
   SmcSnapshot snapshot;
   string stableId="";
   const int direction=mirror ? 1 : -1;
   for(int length=3;length<=9;length++)
     {
      IfvgRun(full,length,config,snapshot);
      if(length < 6)
        {
         TestEqual(ArraySize(snapshot.records),0,"wick or boundary close cannot invert");
         continue;
        }
      TestEqual(ArraySize(snapshot.records),1,"one original gap produces one inverse");
      if(ArraySize(snapshot.records) != 1) continue;
      SmcRecord record=snapshot.records[0];
      if(stableId == "") stableId=record.id;
      TestAssert(record.id == stableId,"future bars preserve inverse identity");
      TestAssert(record.relatedId == SmcRecordId(ICT_FVG,"TEST",PERIOD_M1,full[1].time,-direction),"inverse keeps original FVG identity");
      TestEqual(record.direction,direction,"direction reverses original gap");
      TestEqual(record.sourceTime,full[5].time,"inverse source is breaking bar");
      TestEqual(record.confirmedAt,full[5].time+60,"inverse confirms at close");
      TestNear(record.lower,102,1e-9,"inverse lower boundary");
      TestNear(record.upper,108,1e-9,"inverse upper boundary");
      string expected=length == 6 ? "FRESH" : length == 7 ? "TESTED" : length == 8 ? "MITIGATED" : "BROKEN";
      TestAssert(record.state == expected,"future bars advance expected lifecycle");
      TestAssert(record.active == (length < 9),"only broken inverse is inactive");
     }
   TestAssert(SmcDetectIFVG(full,config,"TEST",PERIOD_M1,1,1,snapshot),"repeated evaluation succeeds");
   TestEqual(ArraySize(snapshot.records),1,"repeated updates never duplicate");
  }

void OnStart()
  {
   TestBegin("IFVG");
   IfvgLifecycle(false);
   IfvgLifecycle(true);
   SmcConfig config;
   config.SetDefaults();
   MqlRates bars[];
   IfvgFixture(bars);
   SmcSnapshot snapshot;

   // Inversion eligibility includes the source's last live bar, age 3 here.
   config.maxZoneAge=3;
   ArrayResize(bars,10);
   for(int i=6;i<10;i++) IfvgBar(bars[i],i,100,101,99,100);
   IfvgRun(bars,9,config,snapshot);
   TestEqual(ArraySize(snapshot.records),1,"source can invert on last eligible bar");
   if(ArraySize(snapshot.records) == 1)
      TestAssert(snapshot.records[0].active,"inverse active through maximum age");
   IfvgRun(bars,10,config,snapshot);
   if(ArraySize(snapshot.records) == 1)
     {
      TestAssert(!snapshot.records[0].active,"inverse expires after maximum age");
      TestAssert(snapshot.records[0].reason == "expired","expiry has a separate reason");
      TestAssert(snapshot.records[0].state == "FRESH","expiry preserves lifecycle state");
     }
   config.maxZoneAge=2;
   IfvgRun(bars,10,config,snapshot);
   TestEqual(ArraySize(snapshot.records),0,"expired source never produces an inverse");

   config.SetDefaults();
   config.lookbackBars=1;
   IfvgFixture(bars);
   IfvgRun(bars,6,config,snapshot);
   TestEqual(ArraySize(snapshot.records),1,"ancestor before reporting horizon remains available");
   IfvgBar(bars[6],6,101,109,99,109);
   IfvgRun(bars,7,config,snapshot);
   if(ArraySize(snapshot.records) == 1)
      TestAssert(snapshot.records[0].state == "BROKEN","same bar break outranks contact and mitigation");

   config.minFvgPips=6;
   IfvgRun(bars,6,config,snapshot);
   TestEqual(ArraySize(snapshot.records),1,"exact minimum source gap is accepted");
   config.minFvgPips=6.1;
   IfvgRun(bars,6,config,snapshot);
   TestEqual(ArraySize(snapshot.records),0,"subminimum source gap is excluded");

   config.SetDefaults();
   config.enableIFVG=false;
   IfvgRun(bars,6,config,snapshot);
   TestEqual(snapshot.modules[0].status,SMC_STATUS_DISABLED,"disabled IFVG is distinguishable");
   config.enableIFVG=true;
   IfvgRun(bars,2,config,snapshot);
   TestEqual(snapshot.modules[0].status,SMC_STATUS_NOT_READY,"missing history is not ready");
   bars[1].time=bars[0].time;
   snapshot.Reset();
   TestAssert(!SmcDetectIFVG(bars,config,"TEST",PERIOD_M1,1,1,snapshot),"unordered input fails");
   TestEqual(snapshot.modules[0].status,SMC_STATUS_ERROR,"invalid history is an error");
   TestAssert(SmcImbalanceAtLeast(1.10000-1.09999,0.00001,0.00001),"decimal exact tick tolerates roundoff");
   TestAssert(!SmcImbalanceAtLeast(0.9999,1,1),"sub-tick move remains below threshold");
   TestFinish();
  }
