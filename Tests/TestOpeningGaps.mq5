#property strict
#include "TestHarness.mqh"
#include "../Include/SMC/ICT/OpeningGaps.mqh"

void GapBar(MqlRates &bar, const datetime time, const double open,
            const double high, const double low, const double close)
  {
   ZeroMemory(bar);
   bar.time = time;
   bar.open = open;
   bar.high = high;
   bar.low = low;
   bar.close = close;
  }

void GapFixture(MqlRates &rates[], MqlRates &daily[], MqlRates &weekly[])
  {
   ArrayResize(rates, 1);
   ArrayResize(daily, 2);
   ArrayResize(weekly, 2);
   GapBar(rates[0], D'2026.01.05 00:00', 102, 104, 101, 103);
   GapBar(daily[0], D'2026.01.02 00:00', 99, 101, 98, 100);
   GapBar(daily[1], D'2026.01.05 00:00', 102, 1000, 1, 3);
   GapBar(weekly[0], D'2025.12.29 00:00', 99, 101, 98, 100);
   GapBar(weekly[1], D'2026.01.05 00:00', 102, 1000, 1, 3);
  }

int GapRecord(const SmcSnapshot &snapshot, const ENUM_SMC_CONCEPT concept,
               const datetime source = 0)
  {
   for(int i = 0; i < ArraySize(snapshot.records); i++)
      if(snapshot.records[i].concept == concept &&
         (source == 0 || snapshot.records[i].sourceTime == source)) return i;
   return -1;
  }

ENUM_SMC_STATUS GapStatus(const SmcSnapshot &snapshot, const ENUM_SMC_CONCEPT concept)
  {
   for(int i = 0; i < ArraySize(snapshot.modules); i++)
      if(snapshot.modules[i].concept == concept) return snapshot.modules[i].status;
   return SMC_STATUS_ERROR;
  }

void OnStart()
  {
   TestBegin("opening-gaps");
   MqlRates rates[], daily[], weekly[];
   SmcConfig config;
   config.SetDefaults();
   SmcSnapshot snapshot;
   snapshot.Reset();
   GapFixture(rates, daily, weekly);
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 1, snapshot);
   TestEqual(ArraySize(snapshot.records), 2, "daily and weekly gaps are distinct");
   TestEqual(GapStatus(snapshot, ICT_DAILY_GAP), SMC_STATUS_READY, "daily history ready");
   TestEqual(GapStatus(snapshot, ICT_WEEKLY_GAP), SMC_STATUS_READY, "weekly history ready");
   int day = GapRecord(snapshot, ICT_DAILY_GAP);
   TestAssert(day >= 0, "daily gap exists");
   string stableId = "";
   if(day >= 0)
     {
      stableId = snapshot.records[day].id;
      TestEqual(snapshot.records[day].direction, 1, "upward gap direction");
      TestNear(snapshot.records[day].lower, 100, 0, "gap lower is previous close");
      TestNear(snapshot.records[day].upper, 102, 0, "gap upper is period opening");
      TestEqual(snapshot.records[day].sourceTime, rates[0].time, "gap source is broker open");
      TestEqual(snapshot.records[day].confirmedAt, rates[0].time + 60, "confirmation uses closed primary end");
      TestAssert(snapshot.records[day].state == "ACTIVE" && snapshot.records[day].active,
                  "forming aggregate range cannot fill a gap");
      TestAssert(snapshot.records[day].relatedId != "", "gap references preceding broker period");
     }

   // Duplicate updates never duplicate IDs, even before the caller resets.
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 1, snapshot);
   TestEqual(ArraySize(snapshot.records), 2, "duplicate update is idempotent");

   // The first later CLOSED candle that reaches the previous close fills it.
   ArrayResize(rates, 3);
   GapBar(rates[1], D'2026.01.05 00:01', 103, 105, 100, 104);
   GapBar(rates[2], D'2026.01.05 00:02', 104, 106, 99, 105);
   snapshot.Reset();
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 1, snapshot);
   day = GapRecord(snapshot, ICT_DAILY_GAP);
   if(day >= 0)
     {
      TestAssert(snapshot.records[day].id == stableId, "fill preserves stable gap identity");
      TestAssert(snapshot.records[day].state == "FILLED" && !snapshot.records[day].active,
                  "closed price touch fills bullish gap");
      TestEqual(snapshot.records[day].updatedAt, rates[1].time + 60, "earliest fill time is preserved");
      TestEqual(snapshot.records[day].confirmedAt, rates[0].time + 60, "fill preserves confirmation");
     }
   else TestAssert(false, "filled daily gap retained in history");

   // Full aggregate candles / later periods must not leak into a prefix run.
   ArrayResize(rates, 1);
   ArrayResize(daily, 3);
   GapBar(daily[2], D'2026.01.06 00:00', 10000, 20000, 0, 17000);
   daily[1].low = -999;
   daily[1].high = 99999;
   daily[1].close = -123;
   weekly[1].low = -999;
   weekly[1].high = 99999;
   weekly[1].close = -123;
   snapshot.Reset();
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 1, snapshot);
   TestEqual(ArraySize(snapshot.records), 2, "future period is not confirmed early");
   day = GapRecord(snapshot, ICT_DAILY_GAP);
   TestAssert(day >= 0 && snapshot.records[day].id == stableId &&
               snapshot.records[day].state == "ACTIVE", "prefix ignores future aggregates and fills");

   // A later broker day/week uses the now-completed preceding close, while
   // identities of already confirmed gaps remain unchanged.
   GapFixture(rates, daily, weekly);
   ArrayResize(rates, 2);
   ArrayResize(daily, 3);
   ArrayResize(weekly, 3);
   daily[1].close = 103;
   weekly[1].close = 103;
   GapBar(rates[1], D'2026.01.12 00:00', 104, 106, 104, 105);
   GapBar(daily[2], D'2026.01.12 00:00', 104, 1000, 1, -999);
   GapBar(weekly[2], D'2026.01.12 00:00', 104, 1000, 1, -999);
   snapshot.Reset();
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 1, snapshot);
   TestEqual(ArraySize(snapshot.records), 4, "later broker period adds daily and weekly gaps");
   day = GapRecord(snapshot, ICT_DAILY_GAP, D'2026.01.05 00:00');
   TestAssert(day >= 0 && snapshot.records[day].id == stableId,
               "next period preserves prior gap identity");
   int nextDay = GapRecord(snapshot, ICT_DAILY_GAP, D'2026.01.12 00:00');
   int nextWeek = GapRecord(snapshot, ICT_WEEKLY_GAP, D'2026.01.12 00:00');
   TestAssert(nextDay >= 0 && nextWeek >= 0, "new day/week are individually addressable");
   if(nextDay >= 0 && nextWeek >= 0)
     {
      TestNear(snapshot.records[nextDay].referencePrice, 103, 0,
                "next daily gap uses completed predecessor close");
      TestNear(snapshot.records[nextWeek].referencePrice, 103, 0,
                "next weekly gap uses completed predecessor close");
      TestEqual(snapshot.records[nextWeek].confirmedAt, rates[1].time + 60,
                 "new weekly gap waits for new week's first closed primary bar");
      TestAssert(snapshot.records[nextDay].id != snapshot.records[nextWeek].id,
                  "same boundary still yields distinct daily and weekly IDs");
     }

   // A confirming candle may already fill the opening gap.
   GapFixture(rates, daily, weekly);
   rates[0].low = 100;
   snapshot.Reset();
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 1, snapshot);
   day = GapRecord(snapshot, ICT_DAILY_GAP);
   TestAssert(day >= 0 && snapshot.records[day].state == "FILLED" &&
               snapshot.records[day].confirmedAt == snapshot.records[day].updatedAt,
               "confirmation candle may causally fill the gap");

   // Bearish gap uses the preceding close as its upper fill target.
   GapFixture(rates, daily, weekly);
   daily[1].open = 98;
   weekly[1].open = 98;
   GapBar(rates[0], D'2026.01.05 00:00', 98, 99, 97, 98);
   snapshot.Reset();
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 1, snapshot);
   day = GapRecord(snapshot, ICT_DAILY_GAP);
   TestAssert(day >= 0 && snapshot.records[day].direction == -1 &&
               snapshot.records[day].state == "ACTIVE", "bearish gap remains active below target");
   rates[0].high = 100;
   snapshot.Reset();
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 1, snapshot);
   day = GapRecord(snapshot, ICT_DAILY_GAP);
   TestAssert(day >= 0 && snapshot.records[day].state == "FILLED", "bearish gap filled by high touch");

   // At least one tick, inclusive; round-off is tolerated, sub-tick is not.
   GapFixture(rates, daily, weekly);
   daily[1].open = 100.1;
   weekly[1].open = 100.1;
   snapshot.Reset();
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 0.1, snapshot);
   TestEqual(ArraySize(snapshot.records), 2, "exact decimal tick boundary is inclusive");
   daily[1].open = 100.05;
   weekly[1].open = 100;
   snapshot.Reset();
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 0.1, snapshot);
   TestEqual(ArraySize(snapshot.records), 0, "sub-tick and zero differences are not gaps");
   TestEqual(GapStatus(snapshot, ICT_DAILY_GAP), SMC_STATUS_READY, "valid empty detection is ready");

   // Missing history is distinguishable from an empty successful detection.
   GapFixture(rates, daily, weekly);
   snapshot.Reset();
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 1, snapshot);
   SmcRecord unrelated;
   unrelated.Init();
   unrelated.id = "other-module-result";
   unrelated.concept = ICT_DISPLACEMENT;
   SmcAppendRecord(snapshot, unrelated);
   ArrayResize(daily, 1);
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 1, snapshot);
   TestEqual(GapStatus(snapshot, ICT_DAILY_GAP), SMC_STATUS_NOT_READY, "missing predecessor not ready");
   TestEqual(GapStatus(snapshot, ICT_WEEKLY_GAP), SMC_STATUS_READY, "missing daily does not poison weekly");
   TestEqual(GapRecord(snapshot, ICT_DAILY_GAP), -1, "failed reuse clears stale daily record");
   TestAssert(GapRecord(snapshot, ICT_DISPLACEMENT) >= 0, "reuse preserves other modules' records");
   GapFixture(rates, daily, weekly);
   ArrayResize(rates, 2);
   GapBar(rates[1], D'2026.01.06 00:00', 104, 106, 103, 105);
   snapshot.Reset();
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 1, snapshot);
   TestEqual(GapStatus(snapshot, ICT_DAILY_GAP), SMC_STATUS_NOT_READY, "stale current daily period not ready");
   TestEqual(GapStatus(snapshot, ICT_WEEKLY_GAP), SMC_STATUS_READY, "current weekly history remains usable");
   ArrayResize(rates, 0);
   snapshot.Reset();
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 1, snapshot);
   TestEqual(GapStatus(snapshot, ICT_DAILY_GAP), SMC_STATUS_NOT_READY, "no closed primary bars not ready");

   // Calendar disabling and malformed source order must remain explicit.
   GapFixture(rates, daily, weekly);
   snapshot.Reset();
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 1, snapshot);
   config.enableCalendar = false;
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 1, snapshot);
   TestEqual(ArraySize(snapshot.records), 0, "disabled reuse clears stale gap records");
   TestEqual(GapStatus(snapshot, ICT_DAILY_GAP), SMC_STATUS_DISABLED, "disabled daily status explicit");
   TestEqual(GapStatus(snapshot, ICT_WEEKLY_GAP), SMC_STATUS_DISABLED, "disabled weekly status explicit");
   config.enableCalendar = true;
   daily[1].time = daily[0].time;
   snapshot.Reset();
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 1, snapshot);
   TestEqual(GapStatus(snapshot, ICT_DAILY_GAP), SMC_STATUS_NOT_READY, "duplicate period timestamp rejected");
   GapFixture(rates, daily, weekly);
   snapshot.Reset();
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_M1, 0, snapshot);
   TestEqual(GapStatus(snapshot, ICT_DAILY_GAP), SMC_STATUS_ERROR, "invalid tick is an error");

   // No confirmation from an overlapping older bar on a coarser timeframe.
   GapFixture(rates, daily, weekly);
   GapBar(rates[0], D'2026.01.04 23:30', 100, 120, 90, 110);
   ArrayResize(daily, 3);
   GapBar(daily[1], D'2026.01.04 00:00', 100, 120, 90, 100);
   GapBar(daily[2], D'2026.01.05 00:00', 102, 1000, 1, 3);
   snapshot.Reset();
   SmcDetectOpeningGaps(rates, daily, weekly, config, "TEST", PERIOD_H1, 1, snapshot);
   TestEqual(GapRecord(snapshot, ICT_DAILY_GAP, D'2026.01.05 00:00'), -1,
              "older overlapping candle does not confirm new daily opening");

   // Weekly primary candles must not hide Tuesday-Friday daily gaps. D1
   // prices order confirmation/fill events without using a later daily range.
   ArrayResize(rates,1);
   GapBar(rates[0],D'2026.01.05',100,106,99,105);
   ArrayResize(daily,7);
   GapBar(daily[0],D'2026.01.02',99,101,98,100);
   GapBar(daily[1],D'2026.01.05',100,101,99,100);
   GapBar(daily[2],D'2026.01.06',102,104,101,103);
   GapBar(daily[3],D'2026.01.07',103,104,100,102);
   GapBar(daily[4],D'2026.01.08',102,103,101,102);
   GapBar(daily[5],D'2026.01.09',105,106,104,105);
   GapBar(daily[6],D'2026.01.12',106,1000,1,3);
   ArrayResize(weekly,3);
   GapBar(weekly[0],D'2025.12.29',99,101,98,100);
   GapBar(weekly[1],D'2026.01.05',100,106,99,105);
   GapBar(weekly[2],D'2026.01.12',106,1000,1,3);
   SmcDetectOpeningGaps(rates,daily,weekly,config,"TEST",PERIOD_W1,1,snapshot);
   TestEqual(GapStatus(snapshot,ICT_DAILY_GAP),SMC_STATUS_READY,"Weekly primary replays available closed D1 candles");
   day=GapRecord(snapshot,ICT_DAILY_GAP,D'2026.01.06');
   TestAssert(day>=0,"Daily gap inside a weekly primary candle is retained");
   if(day>=0)
     {
      TestEqual(snapshot.records[day].confirmedAt,D'2026.01.07',"Coarse daily gap confirms at first D1 close");
      TestEqual(snapshot.records[day].updatedAt,D'2026.01.08',"Coarse fill time follows earliest closed D1 touch");
      TestAssert(snapshot.records[day].state=="FILLED","Coarse daily replay preserves filled state");
      TestAssert(snapshot.records[day].id==SmcRecordId(ICT_DAILY_GAP,"TEST",PERIOD_W1,D'2026.01.06',1),
                 "Coarse replay retains requested timeframe in record identity");
     }
   day=GapRecord(snapshot,ICT_DAILY_GAP,D'2026.01.09');
   TestAssert(day>=0 && snapshot.records[day].state=="ACTIVE","Forming boundary D1 range cannot fill a coarse gap");
   TestEqual(GapRecord(snapshot,ICT_DAILY_GAP,D'2026.01.12'),-1,"Boundary D1 opening waits for a closed D1 candle");

   ArrayResize(daily,5);
   SmcDetectOpeningGaps(rates,daily,weekly,config,"TEST",PERIOD_W1,1,snapshot);
   TestEqual(GapStatus(snapshot,ICT_DAILY_GAP),SMC_STATUS_NOT_READY,"Early-week D1 data cannot certify a whole closed week");
   TestEqual(GapRecord(snapshot,ICT_DAILY_GAP),-1,"Missing coarse replay history clears stale gaps");
   ArrayResize(daily,6);
   GapBar(daily[5],D'2026.01.13',110,111,109,110);
   SmcDetectOpeningGaps(rates,daily,weekly,config,"TEST",PERIOD_W1,1,snapshot);
   TestEqual(GapStatus(snapshot,ICT_DAILY_GAP),SMC_STATUS_NOT_READY,"Future D1 timestamp cannot conceal missing evaluation coverage");

   // Monthly evaluation needs D1 replay for weekly gaps too: the final week
   // can still be forming at month end, so its aggregate OHLC is unavailable.
   GapBar(rates[0],D'2026.01.01',100,111,99,110);
   ArrayResize(daily,33);
   GapBar(daily[0],D'2025.12.31',100,101,99,100);
   for(int d=1;d<=31;d++)
     {
      double price=d>=26 ? 110 : (d>=5 ? 105 : 100);
      double low=d==7 ? 100 : price-1;
      GapBar(daily[d],D'2026.01.01'+(d-1)*86400,price,price+1,low,price);
     }
   GapBar(daily[32],D'2026.02.01',110,1000,1,3);
   ArrayResize(weekly,7);
   GapBar(weekly[0],D'2025.12.22',100,101,99,100);
   GapBar(weekly[1],D'2025.12.29',100,101,99,100);
   GapBar(weekly[2],D'2026.01.05',105,106,100,105);
   GapBar(weekly[3],D'2026.01.12',105,106,104,105);
   GapBar(weekly[4],D'2026.01.19',105,106,104,105);
   GapBar(weekly[5],D'2026.01.26',110,1000,1,3);
   GapBar(weekly[6],D'2026.02.02',999,2000,0,1);
   SmcDetectOpeningGaps(rates,daily,weekly,config,"TEST",PERIOD_MN1,1,snapshot);
   TestEqual(GapStatus(snapshot,ICT_DAILY_GAP),SMC_STATUS_READY,"Monthly primary exposes internal daily gaps");
   TestEqual(GapStatus(snapshot,ICT_WEEKLY_GAP),SMC_STATUS_READY,"Monthly primary exposes internal weekly gaps");
   int week=GapRecord(snapshot,ICT_WEEKLY_GAP,D'2026.01.05');
   TestAssert(week>=0,"Completed weekly gap inside a month is retained");
   if(week>=0)
     {
      TestEqual(snapshot.records[week].confirmedAt,D'2026.01.06',"Monthly weekly gap confirms from first closed D1");
      TestEqual(snapshot.records[week].updatedAt,D'2026.01.08',"Monthly weekly gap fills from chronological D1");
      TestAssert(snapshot.records[week].state=="FILLED","Monthly weekly gap keeps filled lifecycle");
     }
   week=GapRecord(snapshot,ICT_WEEKLY_GAP,D'2026.01.26');
   TestAssert(week>=0,"Week overlapping month end is reconstructed from closed D1 candles");
   if(week>=0)
     {
      TestEqual(snapshot.records[week].confirmedAt,D'2026.01.27',"Overlapping weekly gap has a causal D1 confirmation");
      TestAssert(snapshot.records[week].state=="ACTIVE","Forming W1 and next-month D1 prices cannot fill gap");
     }
   TestEqual(GapRecord(snapshot,ICT_WEEKLY_GAP,D'2026.02.02'),-1,"Next month's weekly opening remains unavailable");
   for(int i=0;i<ArraySize(snapshot.modules);i++)
      if(snapshot.modules[i].concept==ICT_DAILY_GAP || snapshot.modules[i].concept==ICT_WEEKLY_GAP)
         TestEqual(snapshot.modules[i].asOf,D'2026.02.01',"Coarse replay retains primary evaluation timestamp");
   TestFinish();
  }
