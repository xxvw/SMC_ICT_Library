#property strict
#include <SMC/ICT/ReferenceLevels.mqh>
#include "TestHarness.mqh"

void ReferenceBar(MqlRates &bar, const datetime time,
                  const double high, const double low)
  {
   ZeroMemory(bar);
   bar.time = time;
   bar.high = high;
   bar.low = low;
   bar.open = (high + low) / 2.0;
   bar.close = bar.open;
  }

int ReferenceRecord(const SmcSnapshot &snapshot, const ENUM_SMC_CONCEPT concept)
  {
   for(int i = 0; i < ArraySize(snapshot.records); i++)
      if(snapshot.records[i].concept == concept) return i;
   return -1;
  }

ENUM_SMC_STATUS ReferenceStatus(const SmcSnapshot &snapshot,
                               const ENUM_SMC_CONCEPT concept)
  {
   for(int i = 0; i < ArraySize(snapshot.modules); i++)
      if(snapshot.modules[i].concept == concept) return snapshot.modules[i].status;
   return SMC_STATUS_ERROR;
  }

void OnStart()
  {
   TestBegin("reference-levels");
   SmcConfig config;
   config.SetDefaults();
   SmcSnapshot snapshot;
   snapshot.Reset();
   MqlRates rates[], daily[], weekly[];
   ArrayResize(rates, 1);
   ArrayResize(daily, 4);
   ArrayResize(weekly, 4);
   ReferenceBar(rates[0], D'2026.01.09 10:00', 125, 120);
   ReferenceBar(daily[0], D'2026.01.07', 120, 100);
   ReferenceBar(daily[1], D'2026.01.08', 130, 110);
   ReferenceBar(daily[2], D'2026.01.09', 999, 1);
   ReferenceBar(daily[3], D'2026.01.10', 888, 2);
   ReferenceBar(weekly[0], D'2025.12.22', 140, 80);
   ReferenceBar(weekly[1], D'2025.12.29', 150, 90);
   ReferenceBar(weekly[2], D'2026.01.05', 900, 5);
   ReferenceBar(weekly[3], D'2026.01.12', 800, 6);

   SmcDetectReferenceLevels(rates, daily, weekly, config, "TEST", PERIOD_M15, 0.01, snapshot);
   TestEqual(ArraySize(snapshot.records), 4, "one high and low per completed period");
   int dayHigh = ReferenceRecord(snapshot, ICT_PREVIOUS_DAY_HIGH);
   int dayLow = ReferenceRecord(snapshot, ICT_PREVIOUS_DAY_LOW);
   int weekHigh = ReferenceRecord(snapshot, ICT_PREVIOUS_WEEK_HIGH);
   int weekLow = ReferenceRecord(snapshot, ICT_PREVIOUS_WEEK_LOW);
   TestAssert(dayHigh >= 0 && dayLow >= 0 && weekHigh >= 0 && weekLow >= 0,
              "all reference concepts exist");
   string originalId = "";
   if(dayHigh >= 0 && dayLow >= 0 && weekHigh >= 0 && weekLow >= 0)
     {
      TestNear(snapshot.records[dayHigh].upper, 130, 0.00001, "previous daily high");
      TestNear(snapshot.records[dayLow].lower, 110, 0.00001, "previous daily low");
      TestNear(snapshot.records[weekHigh].upper, 150, 0.00001, "previous weekly high");
      TestNear(snapshot.records[weekLow].lower, 90, 0.00001, "previous weekly low");
      TestEqual(snapshot.records[dayHigh].sourceTime, D'2026.01.08', "daily source period");
      TestEqual(snapshot.records[dayHigh].confirmedAt, D'2026.01.09', "available at successor open");
      TestEqual(snapshot.records[dayHigh].periodEnd, D'2026.01.09', "daily period boundary");
      TestEqual(snapshot.records[weekHigh].periodStart, D'2025.12.29', "weekly source survives year change");
      TestEqual(snapshot.records[weekHigh].confirmedAt, D'2026.01.05', "weekly confirmation boundary");
      TestEqual(snapshot.records[dayHigh].direction, 0, "reference prices are neutral");
      TestAssert(snapshot.records[dayHigh].state == "COMPLETED", "only completed period ranges");
      originalId = snapshot.records[dayHigh].id;
     }

   daily[2].high = 2000;
   daily[2].low = -100;
   weekly[2].high = 3000;
   SmcDetectReferenceLevels(rates, daily, weekly, config, "TEST", PERIOD_M15, 0.01, snapshot);
   TestEqual(ArraySize(snapshot.records), 4, "repeated update never duplicates levels");
   dayHigh = ReferenceRecord(snapshot, ICT_PREVIOUS_DAY_HIGH);
   if(dayHigh >= 0)
     {
      TestNear(snapshot.records[dayHigh].upper, 130, 0.00001, "forming prices cannot repaint prior levels");
      TestAssert(snapshot.records[dayHigh].id == originalId, "ID is independent of forming prices");
     }

   rates[0].time = D'2026.01.09 23:45';
   SmcDetectReferenceLevels(rates, daily, weekly, config, "TEST", PERIOD_M15, 0.01, snapshot);
   dayHigh = ReferenceRecord(snapshot, ICT_PREVIOUS_DAY_HIGH);
   if(dayHigh >= 0)
     {
      TestNear(snapshot.records[dayHigh].upper, 2000, 0.00001, "new prior day becomes available exactly at its close");
      TestEqual(snapshot.records[dayHigh].confirmedAt, D'2026.01.10', "equal asOf boundary is included");
      TestAssert(snapshot.records[dayHigh].id != originalId, "a new source period has a different ID");
     }

   // A historical pair alone does not establish that the period feed is current.
   rates[0].time = D'2026.01.09 10:00';
   ArrayResize(daily, 2);
   SmcDetectReferenceLevels(rates, daily, weekly, config, "TEST", PERIOD_M15, 0.01, snapshot);
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_DAY_HIGH), SMC_STATUS_NOT_READY, "stale D1 pair cannot publish old prior levels");
   TestEqual(ReferenceRecord(snapshot, ICT_PREVIOUS_DAY_HIGH), -1, "stale D1 clears previous successful levels");
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_WEEK_HIGH), SMC_STATUS_READY, "stale D1 does not suppress current W1");
   ArrayResize(daily, 3);
   ReferenceBar(daily[2], D'2026.01.10', 2000, -100);
   SmcDetectReferenceLevels(rates, daily, weekly, config, "TEST", PERIOD_M15, 0.01, snapshot);
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_DAY_HIGH), SMC_STATUS_NOT_READY, "future D1 opening cannot certify missing current history");
   TestEqual(ReferenceRecord(snapshot, ICT_PREVIOUS_DAY_HIGH), -1, "future D1 prices do not expose stale levels");
   ReferenceBar(daily[2], D'2026.01.09', 2000, -100);
   ArrayResize(weekly, 2);
   SmcDetectReferenceLevels(rates, daily, weekly, config, "TEST", PERIOD_M15, 0.01, snapshot);
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_WEEK_HIGH), SMC_STATUS_NOT_READY, "stale W1 pair cannot publish old prior levels");
   TestEqual(ReferenceRecord(snapshot, ICT_PREVIOUS_WEEK_HIGH), -1, "stale W1 clears previous successful levels");
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_DAY_HIGH), SMC_STATUS_READY, "current D1 remains available with stale W1");

   // Friday's final primary bar closes on Saturday, but does not require a
   // Saturday broker daily candle: coverage includes the Friday period's end.
   rates[0].time = D'2026.01.09 23:45';
   ArrayResize(weekly, 3);
   ReferenceBar(weekly[2], D'2026.01.05', 900, 5);
   SmcDetectReferenceLevels(rates, daily, weekly, config, "TEST", PERIOD_M15, 0.01, snapshot);
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_DAY_HIGH), SMC_STATUS_READY, "Friday close does not require nonexistent Saturday D1");
   dayHigh = ReferenceRecord(snapshot, ICT_PREVIOUS_DAY_HIGH);
   if(dayHigh >= 0)
      TestEqual(snapshot.records[dayHigh].sourceTime, D'2026.01.08', "weekend keeps latest confirmed prior daily period");

   // Broker holidays may leave gaps between valid period openings.
   rates[0].time = D'2026.01.13 10:00';
   ArrayResize(daily, 2);
   ReferenceBar(daily[0], D'2026.01.09', 150, 100);
   ReferenceBar(daily[1], D'2026.01.13', 999, 1);
   ArrayResize(weekly, 2);
   ReferenceBar(weekly[0], D'2025.12.29', 180, 80);
   ReferenceBar(weekly[1], D'2026.01.12', 900, 5);
   SmcDetectReferenceLevels(rates, daily, weekly, config, "TEST", PERIOD_M15, 0.01, snapshot);
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_DAY_HIGH), SMC_STATUS_READY, "holiday gaps do not require every daily candle");
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_WEEK_HIGH), SMC_STATUS_READY, "holiday gaps do not require every weekly candle");
   dayHigh = ReferenceRecord(snapshot, ICT_PREVIOUS_DAY_HIGH);
   if(dayHigh >= 0)
     {
      TestNear(snapshot.records[dayHigh].upper, 150, 0, "holiday successor confirms the last actual daily range");
      TestEqual(snapshot.records[dayHigh].confirmedAt, D'2026.01.13', "holiday confirmation uses actual successor open");
     }

   // A coarse primary candle needs calendar data through its closing boundary,
   // even when its opening was covered by a formerly current daily period.
   rates[0].time = D'2026.01.05';
   ArrayResize(daily, 3);
   ReferenceBar(daily[0], D'2026.01.02', 130, 100);
   ReferenceBar(daily[1], D'2026.01.05', 140, 110);
   ReferenceBar(daily[2], D'2026.01.06', 150, 120);
   SmcDetectReferenceLevels(rates, daily, weekly, config, "TEST", PERIOD_W1, 0.01, snapshot);
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_DAY_HIGH), SMC_STATUS_NOT_READY, "weekly primary close rejects stale early-week D1 history");
   TestEqual(ReferenceRecord(snapshot, ICT_PREVIOUS_DAY_HIGH), -1, "coarse stale history clears earlier reference records");
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_WEEK_HIGH), SMC_STATUS_READY, "weekly feed covers the coarse primary closing boundary");

   // Restore a current weekly feed for the independent missing-history tests.
   rates[0].time = D'2026.01.09 23:45';
   ReferenceBar(weekly[0], D'2025.12.29', 150, 90);
   ReferenceBar(weekly[1], D'2026.01.05', 900, 5);
   // Missing one period's history does not suppress the other period.
   ArrayResize(daily, 1);
   SmcDetectReferenceLevels(rates, daily, weekly, config, "TEST", PERIOD_M15, 0.01, snapshot);
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_DAY_HIGH), SMC_STATUS_NOT_READY, "daily missing history is explicit");
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_DAY_LOW), SMC_STATUS_NOT_READY, "both daily statuses fail together");
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_WEEK_HIGH), SMC_STATUS_READY, "weekly data remains available");
   TestEqual(ReferenceRecord(snapshot, ICT_PREVIOUS_DAY_HIGH), -1, "missing history clears stale daily levels");
   TestEqual(ArraySize(snapshot.records), 2, "only available weekly records remain");

   ArrayResize(daily, 2);
   ReferenceBar(daily[0], D'2026.01.10', 10, 1);
   ReferenceBar(daily[1], D'2026.01.11', 20, 2);
   rates[0].time = D'2026.01.09 10:00';
   SmcDetectReferenceLevels(rates, daily, weekly, config, "TEST", PERIOD_M15, 0.01, snapshot);
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_DAY_HIGH), SMC_STATUS_NOT_READY, "future periods cannot provide completed ranges");

   ReferenceBar(daily[0], D'2026.01.08', 10, 1);
   ReferenceBar(daily[1], D'2026.01.08', 20, 2);
   SmcDetectReferenceLevels(rates, daily, weekly, config, "TEST", PERIOD_M15, 0.01, snapshot);
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_DAY_HIGH), SMC_STATUS_ERROR, "duplicate period starts are invalid");

   ReferenceBar(daily[1], D'2026.01.09', 20, 2);
   daily[0].high = 0;
   SmcDetectReferenceLevels(rates, daily, weekly, config, "TEST", PERIOD_M15, 0.01, snapshot);
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_DAY_HIGH), SMC_STATUS_ERROR, "inverted completed range is invalid");

   SmcRecord unrelated;
   unrelated.Init();
   unrelated.concept = ICT_FVG;
   unrelated.id = "unrelated";
   SmcAppendRecord(snapshot, unrelated);
   config.enableCalendar = false;
   SmcDetectReferenceLevels(rates, daily, weekly, config, "TEST", PERIOD_M15, 0.01, snapshot);
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_DAY_HIGH), SMC_STATUS_DISABLED, "disabled calendar is explicit");
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_WEEK_LOW), SMC_STATUS_DISABLED, "all period levels disabled");
   TestEqual(ArraySize(snapshot.records), 1, "disabled detector removes only its own records");
   TestEqual(ReferenceRecord(snapshot, ICT_FVG), 0, "other detector output is preserved");

   config.enableCalendar = true;
   ArrayResize(rates, 0);
   SmcDetectReferenceLevels(rates, daily, weekly, config, "TEST", PERIOD_M15, 0.01, snapshot);
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_DAY_HIGH), SMC_STATUS_NOT_READY, "empty primary history is not ready");
   TestEqual(ReferenceStatus(snapshot, ICT_PREVIOUS_WEEK_HIGH), SMC_STATUS_NOT_READY, "empty primary history affects both periods");
   ArrayResize(rates,1);
   ReferenceBar(rates[0],D'2026.02.01',120,90);
   ArrayResize(daily,3);
   ReferenceBar(daily[0],D'2026.02.28',110,100);
   ReferenceBar(daily[1],D'2026.03.01',999,1);
   ReferenceBar(daily[2],D'2026.03.02',888,2);
   SmcDetectReferenceLevels(rates,daily,weekly,config,"TEST",PERIOD_MN1,0.01,snapshot);
   dayHigh=ReferenceRecord(snapshot,ICT_PREVIOUS_DAY_HIGH);
   TestAssert(dayHigh>=0,"February monthly close can expose completed February day");
   if(dayHigh>=0)
     {
      TestNear(snapshot.records[dayHigh].upper,110,0,"February asOf excludes March future daily ranges");
      TestEqual(snapshot.records[dayHigh].confirmedAt,D'2026.03.01',"Monthly asOf uses next calendar boundary");
     }
   TestFinish();
  }
