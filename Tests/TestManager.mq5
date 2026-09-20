#property strict
#include "TestHarness.mqh"
#include <SMC/SmcManager.mqh>

void ManagerRates(MqlRates &rates[])
  {
   ArrayResize(rates,4320);
   ZeroMemory(rates);
   for(int i=0;i<ArraySize(rates);i++)
     {
      rates[i].time=D'2026.01.05 00:00'+60*i;
      double center=100+5*MathSin(i*0.4)+0.002*i;
      rates[i].open=NormalizeDouble(center,2);
      rates[i].close=NormalizeDouble(center+0.1,2);
      rates[i].high=NormalizeDouble(center+0.5,2);
      rates[i].low=NormalizeDouble(center-0.5,2);
      rates[i].tick_volume=10;
     }
  }

ENUM_SMC_STATUS ManagerConceptStatus(const SmcSnapshot &snapshot,const ENUM_SMC_CONCEPT concept)
  {
   for(int i=0;i<ArraySize(snapshot.modules);i++)
      if(snapshot.modules[i].concept==concept) return snapshot.modules[i].status;
   return SMC_STATUS_ERROR;
  }

bool ManagerSameRecords(const SmcSnapshot &a,const SmcSnapshot &b)
  {
   if(a.status!=b.status || a.asOf!=b.asOf || ArraySize(a.records)!=ArraySize(b.records) ||
      ArraySize(a.modules)!=ArraySize(b.modules)) return false;
   for(int i=0;i<ArraySize(a.records);i++)
      if(a.records[i].id!=b.records[i].id || a.records[i].confirmedAt!=b.records[i].confirmedAt ||
         a.records[i].state!=b.records[i].state || a.records[i].lower!=b.records[i].lower ||
         a.records[i].upper!=b.records[i].upper || a.records[i].active!=b.records[i].active ||
         a.records[i].reason!=b.records[i].reason || a.records[i].relatedId!=b.records[i].relatedId)
         return false;
   for(int i=0;i<ArraySize(a.modules);i++)
      if(a.modules[i].concept!=b.modules[i].concept || a.modules[i].status!=b.modules[i].status ||
         a.modules[i].truncated!=b.modules[i].truncated) return false;
   return true;
  }

void OnStart()
  {
   TestBegin("manager-integration");
   CSmcManager manager;
   SmcSnapshot snapshot,previous;
   TestAssert(!manager.GetSnapshot(snapshot),"no snapshot before first update");
   TestEqual(manager.GetSignal(),SIGNAL_WAIT,"uninitialized signal waits");
   TestAssert(!manager.Update(),"uninitialized update fails");
   TestAssert(manager.GetSnapshot(snapshot),"failed attempt is observable");
   TestEqual(snapshot.status,SMC_STATUS_ERROR,"uninitialized state is ERROR");

   SmcConfig config;
   config.SetDefaults();
   config.lookbackBars=0;
   TestAssert(!manager.Init("EURUSD",PERIOD_M1,config),"invalid config cannot initialize");
   TestEqual(manager.GetStatus(),SMC_STATUS_ERROR,"invalid config is diagnosed");
   TestAssert(!manager.GetSnapshot(snapshot),"reinitialization resets snapshot watermark");

   string symbol="SMC_MANAGER_FIXTURE";
   TestAssert(CustomSymbolCreate(symbol,"SMCTests","EURUSD"),"create isolated custom symbol");
   TestAssert(CustomSymbolSetDouble(symbol,SYMBOL_POINT,0.01),"custom point metadata");
   TestAssert(CustomSymbolSetDouble(symbol,SYMBOL_TRADE_TICK_SIZE,0.01),"custom tick metadata");
   TestAssert(CustomSymbolSetInteger(symbol,SYMBOL_DIGITS,2),"custom digit metadata");
   TestAssert(SymbolSelect(symbol,true),"select fixture symbol");
   config.SetDefaults();
   config.enableCalendar=false;
   config.enablePO3=false;
   config.maxRecordsPerConcept=3;
   TestAssert(manager.Init(symbol,PERIOD_M1,config),"new typed configuration initializes");
   TestAssert(!manager.Update(),"missing primary history fails");
   TestAssert(manager.GetSnapshot(snapshot),"unavailable snapshot is returned");
   TestEqual(snapshot.status,SMC_STATUS_NOT_READY,"missing primary is NOT_READY");
   TestEqual(ArraySize(snapshot.records),0,"unavailable snapshot has no old records");

   MqlRates rates[];
   ManagerRates(rates);
   TestEqual(CustomRatesUpdate(symbol,rates),ArraySize(rates),"install synthetic M1 history");
   bool ready=false;
   // Custom series building is asynchronous; these bounded retries do not
   // change the fixture or permit unavailable histories to count as passing.
   for(int attempt=0;attempt<20 && !ready;attempt++)
     {
      ready=manager.Update();
      if(!ready) Sleep(50);
     }
   TestAssert(ready,"complete primary and M1 history reach READY");
   TestAssert(manager.GetSnapshot(snapshot),"ready snapshot retrievable");
   TestEqual(snapshot.status,SMC_STATUS_READY,"ready aggregate");
   TestEqual(snapshot.asOf,rates[ArraySize(rates)-1].time,"asOf excludes forming bar");
   TestEqual(ArraySize(snapshot.modules),SMC_CONCEPT_COUNT,"every concept status exposed");
   TestEqual(ManagerConceptStatus(snapshot,ICT_DAILY_GAP),SMC_STATUS_DISABLED,"calendar disabled explicitly");
   TestAssert(ArraySize(snapshot.records)>0,"legacy adapter emits detections");
   int counts[SMC_CONCEPT_COUNT];
   ArrayInitialize(counts,0);
   bool truncated=false;
   for(int i=0;i<ArraySize(snapshot.records);i++)
     {
      counts[(int)snapshot.records[i].concept]++;
      TestAssert(snapshot.records[i].confirmedAt<=snapshot.asOf,"records confirmed by snapshot watermark");
      if(snapshot.records[i].concept==ICT_SWING_HIGH || snapshot.records[i].concept==ICT_SWING_LOW)
         TestAssert(snapshot.records[i].confirmedAt>=snapshot.records[i].sourceTime+(config.swingStrength+1)*60,
                    "swing confirmation timestamp includes right-hand closed candles");
     }
   for(int i=0;i<SMC_CONCEPT_COUNT;i++) TestAssert(counts[i]<=3,"per-concept output cap");
   for(int i=0;i<ArraySize(snapshot.modules);i++) truncated=truncated || snapshot.modules[i].truncated;
   TestAssert(truncated,"capped legacy records identify truncation");
   previous=snapshot;
   TestAssert(manager.Update(),"same history updates successfully again");
   manager.GetSnapshot(snapshot);
   TestAssert(ManagerSameRecords(previous,snapshot),"repeated evaluation does not change detections");
   manager.Clean();
   manager.GetSnapshot(snapshot);
   TestAssert(ManagerSameRecords(previous,snapshot),"Clean preserves analysis snapshot");

   MqlRates forming[];
   ArrayResize(forming,1);
   forming[0]=rates[ArraySize(rates)-1];
   forming[0].high=999;
   forming[0].low=1;
   forming[0].close=888;
   TestEqual(CustomRatesUpdate(symbol,forming),1,"mutate forming candle only");
   TestAssert(manager.Update(),"forming-price update still succeeds");
   manager.GetSnapshot(snapshot);
   TestAssert(ManagerSameRecords(previous,snapshot),"forming candle cannot alter confirmed snapshot");

   config.smtSymbol="SMC_MISSING_COMPARISON";
   TestAssert(manager.Init(symbol,PERIOD_M1,config),"comparison symbol acquisition is deferred");
   TestAssert(!manager.Update(),"unavailable comparison prevents full readiness");
   manager.GetSnapshot(snapshot);
   TestEqual(snapshot.status,SMC_STATUS_PARTIAL,"available primary plus absent comparison is PARTIAL");
   TestEqual(ManagerConceptStatus(snapshot,ICT_SMT),SMC_STATUS_NOT_READY,"SMT absence is distinct from no divergence");
   TestEqual(manager.GetSignal(),SIGNAL_WAIT,"partial snapshot gates old trading signal");

   TestAssert(manager.Init(symbol,PERIOD_M1,false,false,false),"legacy Init overload preserved");
   TestAssert(manager.Update(),"legacy enabled modules can still update");
   manager.GetSnapshot(snapshot);
   TestEqual(ManagerConceptStatus(snapshot,ICT_DISPLACEMENT),SMC_STATUS_DISABLED,"old overload does not enable new detectors");
   TestEqual(ManagerConceptStatus(snapshot,ICT_SMT),SMC_STATUS_DISABLED,"old overload clears previous comparison config");
   manager.Confluence().SetMinConfluence(0);
   manager.Confluence().SetMinScore(0);
   TestAssert(manager.Update(),"ready confluence fixture updates");
   TestAssert(manager.GetSignal()!=SIGNAL_WAIT,"fixture produces a signal before history is lost");
   TestAssert(CustomRatesDelete(symbol,0,D'2030.01.01')>0,"remove primary fixture history");
   TestAssert(!manager.Update(),"primary loss fails after prior success");
   manager.GetSnapshot(snapshot);
   TestEqual(snapshot.status,SMC_STATUS_NOT_READY,"lost history returns NOT_READY");
   TestEqual(ArraySize(snapshot.records),0,"lost history clears previous detections");
   TestEqual(manager.GetSignal(),SIGNAL_WAIT,"lost history gates stale signal");
   TestEqual(manager.Confluence().GetEntrySignal(),SIGNAL_WAIT,"direct confluence signal invalidated on history loss");
   TestAssert(!manager.Confluence().IsBuyAllowed(),"direct buy permission invalidated on history loss");
   TestAssert(!manager.Confluence().IsSellAllowed(),"direct sell permission invalidated on history loss");
   SmcConfluenceZone unavailableZone;
   unavailableZone.Init();
   unavailableZone.isValid=true;
   unavailableZone.centerPrice=999;
   TestAssert(!manager.Confluence().GetBuyZone(unavailableZone),"direct buy-zone getter rejects stale result");
   TestAssert(!unavailableZone.isValid && unavailableZone.centerPrice==0,"failed buy-zone getter clears caller output");
   unavailableZone.isValid=true;
   unavailableZone.centerPrice=999;
   TestAssert(!manager.Confluence().GetSellZone(unavailableZone),"direct sell-zone getter rejects stale result");
   TestAssert(!unavailableZone.isValid && unavailableZone.centerPrice==0,"failed sell-zone getter clears caller output");
   // Match the legacy pip convention on one-digit index-like symbols:
   // point=0.1, pip=1.0. A 0.8-price FVG is below the configured 2-pip limit.
   string indexSymbol="EURUSD.smcindex";
   TestAssert(CustomSymbolCreate(indexSymbol,"SMCTests","EURUSD"),"create one-digit fixture");
   TestAssert(CustomSymbolSetDouble(indexSymbol,SYMBOL_POINT,0.1),"one-digit point");
   TestAssert(CustomSymbolSetDouble(indexSymbol,SYMBOL_TRADE_TICK_SIZE,0.1),"one-digit tick");
   TestAssert(CustomSymbolSetInteger(indexSymbol,SYMBOL_DIGITS,1),"one-digit metadata");
   TestAssert(SymbolSelect(indexSymbol,true),"select one-digit fixture");
   for(int i=0;i<ArraySize(rates);i++)
     {
      rates[i].open=100; rates[i].close=100;
      rates[i].high=100.1; rates[i].low=99.9;
     }
   double centers[]={100.6,101,99,99.5,100,100};
   for(int i=0;i<6;i++)
     {
      int bar=ArraySize(rates)-7+i;
      rates[bar].open=centers[i]; rates[bar].close=centers[i];
      rates[bar].high=centers[i]+0.1; rates[bar].low=centers[i]-0.1;
     }
   TestEqual(CustomRatesUpdate(indexSymbol,rates),ArraySize(rates),"install one-digit history");
   config.SetDefaults(); config.enableCalendar=false; config.enablePO3=false;
   TestAssert(manager.Init(indexSymbol,PERIOD_M1,config),"one-digit manager initializes");
   for(int attempt=0;attempt<20;attempt++)
     {
      manager.Update(); manager.GetSnapshot(snapshot);
      if(ManagerConceptStatus(snapshot,ICT_IFVG)==SMC_STATUS_READY) break;
      Sleep(50);
     }
   TestEqual(ManagerConceptStatus(snapshot,ICT_IFVG),SMC_STATUS_READY,"one-digit imbalance evaluates");
   int imbalanceCount=0;
   for(int i=0;i<ArraySize(snapshot.records);i++)
      if(snapshot.records[i].concept==ICT_FVG || snapshot.records[i].concept==ICT_IFVG ||
         snapshot.records[i].concept==ICT_BPR) imbalanceCount++;
   TestEqual(imbalanceCount,0,"legacy FVG and derived imbalances use identical pip thresholds");
   config.lookbackBars=1;
   config.swingStrength=1;
   config.displacementBaseline=1;
   config.maxZoneAge=1;
   config.bprMaxSeparation=1;
   config.po3ExpiryBars=1;
   config.smtRadius=0;
   TestAssert(manager.Init(indexSymbol,PERIOD_M1,config),"small valid settings initialize");
   TestAssert(manager.Update(),"small configured warmup still fetches fixed legacy baselines");
   manager.GetSnapshot(snapshot);
   TestEqual(snapshot.status,SMC_STATUS_READY,"small lookback can reach READY");
   config.enableVIX=true;
   TestAssert(manager.Init(indexSymbol,PERIOD_M1,config),"optional VIX initializes without assuming history ready");
   TestAssert(!manager.Update(),"missing daily VIX history prevents full readiness");
   manager.GetSnapshot(snapshot);
   TestEqual(snapshot.status,SMC_STATUS_PARTIAL,"missing optional analysis yields PARTIAL");
   TestAssert(StringFind(snapshot.message,"VIX")>=0,"optional failure has explicit diagnostic");
   TestEqual(manager.GetSignal(),SIGNAL_WAIT,"optional analysis failure gates trading signal");
   TestEqual(manager.Confluence().GetEntrySignal(),SIGNAL_WAIT,"optional analysis failure invalidates direct signal");
   TestAssert(!manager.Confluence().IsBuyAllowed() && !manager.Confluence().IsSellAllowed(),
              "optional analysis failure invalidates direct permissions");
   config.enableVIX=false;
   config.enableCS=true;
   TestAssert(manager.Init(indexSymbol,PERIOD_M1,config),"optional currency strength initializes");
   TestAssert(!manager.Update(),"unavailable comparison pairs cannot produce currency ranks");
   manager.GetSnapshot(snapshot);
   TestEqual(snapshot.status,SMC_STATUS_PARTIAL,"currency strength absence yields PARTIAL");
   TestAssert(StringFind(snapshot.message,"Currency strength")>=0,"currency failure has explicit diagnostic");
   TestEqual(manager.GetSignal(),SIGNAL_WAIT,"currency analysis failure gates trading signal");

   // At 13:01 broker time, all custom sessions are in the future. The old
   // built-in 12-16 overlap must not create a fourth phantom configured window.
   config.enableCS=false;
   for(int i=0;i<3;i++)
     { config.sessions[i].startMinute=20*60; config.sessions[i].endMinute=21*60; }
   datetime cutoff=D'2026.01.07 13:02';
   TestAssert(CustomRatesDelete(indexSymbol,cutoff,D'2030.01.01')>0,"truncate fixture at custom session evaluation");
   TestAssert(manager.Init(indexSymbol,PERIOD_M1,config),"custom broker sessions initialize");
   manager.Update(); manager.GetSnapshot(snapshot);
   TestEqual(snapshot.asOf,D'2026.01.07 13:01',"custom session evaluation cutoff");
   TestEqual(ManagerConceptStatus(snapshot,ICT_KILL_ZONE),SMC_STATUS_READY,"configured session module is available");
   TestAssert(!manager.KZ().IsInKillZone(),"no fixed overlap outside configured sessions");
   TestFinish();
  }
