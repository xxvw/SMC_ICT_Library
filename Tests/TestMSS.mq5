#property strict
#include "TestHarness.mqh"
#include "../Include/SMC/ICT/MarketStructureShift.mqh"

void MssFixture(MqlRates &rates[], const int count = 7)
  {
   ArrayResize(rates, count);
   double highs[] = {101,106,104,110,106,109,106,107,106};
   double lows[] = {99,101,100,104,102,105,98,98,98};
   double opens[] = {100,103,102,105,104,107,106,103,106};
   double closes[] = {100.25,103.25,102.25,105.25,104.25,107.25,101,104,101};
   for(int i = 0; i < count; i++)
     {
      ZeroMemory(rates[i]);
      rates[i].time = D'2026.01.05 00:00' + i * 300;
      rates[i].open = opens[i];
      rates[i].close = closes[i];
      rates[i].high = highs[i];
      rates[i].low = lows[i];
     }
  }

void OnStart()
  {
   TestBegin("MSS");
   SmcConfig config;
   config.SetDefaults();
   config.swingStrength = 1;
   config.displacementBaseline = 2;
   MqlRates rates[];
   MssFixture(rates);
   SmcSnapshot snapshot;
   snapshot.Reset();
   snapshot.asOf = rates[6].time + 300;
   SmcDetectMSS(rates, config, "TEST", PERIOD_M5, 1, snapshot);
   TestEqual(ArraySize(snapshot.records), 1, "rising swings followed by bearish displacement");
   string firstId = "";
   if(ArraySize(snapshot.records) == 1)
     {
      TestEqual(snapshot.records[0].direction, -1, "bearish MSS direction");
      TestEqual(snapshot.records[0].sourceTime, rates[4].time, "MSS source is broken swing pivot");
      TestEqual(snapshot.records[0].confirmedAt, snapshot.asOf, "MSS known at breaker close");
      TestNear(snapshot.records[0].referencePrice, 102, 0.000001, "broken confirmed swing level");
      TestAssert(snapshot.records[0].relatedId == SmcRecordId(ICT_SWING_LOW, "TEST", PERIOD_M5,
                                                            rates[4].time, 1), "swing reference ID");
      TestAssert(snapshot.records[0].secondaryId == SmcRecordId(ICT_DISPLACEMENT, "TEST", PERIOD_M5,
                                                              rates[6].time, -1), "displacement reference ID");
      firstId = snapshot.records[0].id;
     }
   SmcDetectMSS(rates, config, "TEST", PERIOD_M5, 1, snapshot);
   TestEqual(ArraySize(snapshot.records), 1, "repeated evaluation does not duplicate");
   MssFixture(rates, 6);
   snapshot.asOf = rates[5].time + 300;
   SmcDetectMSS(rates, config, "TEST", PERIOD_M5, 1, snapshot);
   TestEqual(ArraySize(snapshot.records), 0, "future breaker absent from historical prefix");
   MssFixture(rates, 9);
   snapshot.asOf = rates[8].time + 300;
   SmcDetectMSS(rates, config, "TEST", PERIOD_M5, 1, snapshot);
   TestEqual(ArraySize(snapshot.records), 1, "recross does not notify target twice");
   if(ArraySize(snapshot.records) == 1)
     {
      TestAssert(snapshot.records[0].id == firstId, "future bars preserve confirmed identity");
      TestEqual(snapshot.records[0].confirmedAt, rates[6].time + 300, "future recross preserves confirmation");
     }
   MssFixture(rates);
   rates[6].close = 101.5;
   SmcDetectMSS(rates, config, "TEST", PERIOD_M5, 1, snapshot);
   TestEqual(ArraySize(snapshot.records), 0, "less than one tick beyond pivot rejected");
   rates[6].close = 102;
   SmcDetectMSS(rates, config, "TEST", PERIOD_M5, 1, snapshot);
   TestEqual(ArraySize(snapshot.records), 0, "wick below pivot is not a close break");
   MssFixture(rates);
   rates[3].high = rates[1].high;
   SmcDetectMSS(rates, config, "TEST", PERIOD_M5, 1, snapshot);
   TestEqual(ArraySize(snapshot.records), 0, "equal highs do not establish rising trend");
   MssFixture(rates);
   config.lookbackBars = 3;
   SmcDetectMSS(rates, config, "TEST", PERIOD_M5, 1, snapshot);
   TestEqual(ArraySize(snapshot.records), 0, "stale directional evidence expires");
   config.lookbackBars = 500;
   config.enableDisplacement = false;
   SmcDetectMSS(rates, config, "TEST", PERIOD_M5, 1, snapshot);
   TestEqual(ArraySize(snapshot.records), 1, "MSS works with displacement output disabled");
   for(int i = 0; i < ArraySize(rates); i++)
     {
      rates[i].open = (rates[i].open - 99) / 10;
      rates[i].close = (rates[i].close - 99) / 10;
      rates[i].high = (rates[i].high - 99) / 10;
      rates[i].low = (rates[i].low - 99) / 10;
     }
   SmcDetectMSS(rates, config, "TEST", PERIOD_M5, 0.1, snapshot);
   TestEqual(ArraySize(snapshot.records), 1, "decimal exact one-tick break survives rounding");
   MssFixture(rates);
   // Mirroring around 200 exchanges rising structure for falling structure.
   for(int i = 0; i < ArraySize(rates); i++)
     {
      double oldHigh = rates[i].high;
      rates[i].open = 200 - rates[i].open;
      rates[i].close = 200 - rates[i].close;
      rates[i].high = 200 - rates[i].low;
      rates[i].low = 200 - oldHigh;
     }
   SmcDetectMSS(rates, config, "TEST", PERIOD_M5, 1, snapshot);
   TestEqual(ArraySize(snapshot.records), 1, "falling swings followed by bullish displacement");
   if(ArraySize(snapshot.records) == 1)
      TestEqual(snapshot.records[0].direction, 1, "bullish MSS direction");
   MssFixture(rates);
   datetime months[] = {D'2025.08.01',D'2025.09.01',D'2025.10.01',D'2025.11.01',
                        D'2025.12.01',D'2026.01.01',D'2026.02.01'};
   for(int i = 0; i < ArraySize(rates); i++) rates[i].time = months[i];
   snapshot.asOf = D'2026.03.01';
   SmcDetectMSS(rates, config, "TEST", PERIOD_MN1, 1, snapshot);
   TestEqual(ArraySize(snapshot.records), 1, "monthly MSS detected");
   if(ArraySize(snapshot.records) == 1)
      TestEqual(snapshot.records[0].confirmedAt, D'2026.03.01', "monthly MSS uses actual February close");
   ArrayResize(rates, 2);
   SmcDetectMSS(rates, config, "TEST", PERIOD_M5, 1, snapshot);
   TestEqual(snapshot.modules[0].status, SMC_STATUS_NOT_READY, "insufficient history status");
   TestEqual(ArraySize(snapshot.records), 0, "unavailable refresh clears old MSS");
   config.enableMSS = false;
   SmcDetectMSS(rates, config, "TEST", PERIOD_M5, 1, snapshot);
   TestEqual(snapshot.modules[0].status, SMC_STATUS_DISABLED, "disabled MSS status");
   TestFinish();
  }
