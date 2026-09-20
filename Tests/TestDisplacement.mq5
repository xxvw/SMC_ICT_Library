#property strict
#include "TestHarness.mqh"
#include "../Include/SMC/ICT/Displacement.mqh"

void DisplacementFixture(MqlRates &rates[], const int count)
  {
   ArrayResize(rates, count);
   for(int i = 0; i < count; i++)
     {
      ZeroMemory(rates[i]);
      rates[i].time = D'2026.01.05 00:00' + i * 300;
      rates[i].open = 100;
      rates[i].close = 102;
      rates[i].high = 103;
      rates[i].low = 99;
     }
  }

void OnStart()
  {
   TestBegin("Displacement");
   SmcConfig config;
   config.SetDefaults();
   MqlRates rates[];
   DisplacementFixture(rates, 21);
   rates[20].close = 103;
   rates[20].high = 104; // body 3 / range 5 = 60%, mean body 2 * 1.5 = 3
   TestAssert(SmcIsDisplacement(rates, 20, config), "both inclusive threshold boundaries");
   MqlRates decimals[];
   DisplacementFixture(decimals, 21);
   for(int i = 0; i < 21; i++)
     {
      decimals[i].open = 1.00000;
      decimals[i].close = 1.00002;
      decimals[i].high = 1.00004;
      decimals[i].low = 0.99999;
     }
   decimals[20].close = 1.00003;
   TestAssert(SmcIsDisplacement(decimals, 20, config), "decimal 60 percent boundary survives rounding");
   decimals[20].close = 1.0000299;
   TestAssert(!SmcIsDisplacement(decimals, 20, config), "meaningfully below decimal body threshold rejected");
   decimals[20].close = 1.00003;
   decimals[20].high = 1.0000401;
   TestAssert(!SmcIsDisplacement(decimals, 20, config), "meaningfully below decimal fraction threshold rejected");
   for(int i = 0; i < 21; i++)
     {
      decimals[i].open = 1.00003;
      decimals[i].close = 1.00005;
      decimals[i].high = 1.000065;
      decimals[i].low = 1.000025;
     }
   decimals[20].close = 1.00006;
   TestAssert(SmcIsDisplacement(decimals, 20, config), "decimal 1.5 factor boundary survives rounding");
   TestAssert(!SmcIsDisplacement(rates, 19, config), "twenty prior bars required");
   rates[20].close = 102.99;
   TestAssert(!SmcIsDisplacement(rates, 20, config), "body below factor threshold rejected");
   rates[20].close = 103;
   rates[20].high = 105;
   TestAssert(!SmcIsDisplacement(rates, 20, config), "wick-heavy candle rejected");
   rates[20].high = 104;
   SmcSnapshot snapshot;
   snapshot.Reset();
   snapshot.asOf = rates[20].time + 300;
   SmcDetectDisplacement(rates, config, "TEST", PERIOD_M5, 0.01, snapshot);
   TestEqual(ArraySize(snapshot.records), 1, "one displacement emitted");
   if(ArraySize(snapshot.records) == 1)
     {
      TestEqual(snapshot.records[0].direction, 1, "bullish direction");
      TestEqual(snapshot.records[0].sourceTime, rates[20].time, "source is candidate open");
      TestEqual(snapshot.records[0].confirmedAt, snapshot.asOf, "confirmation uses closed bar time");
      TestNear(snapshot.records[0].strength, 0.6, 0.000001, "record body fraction");
      string stable = snapshot.records[0].id;
      SmcDetectDisplacement(rates, config, "TEST", PERIOD_M5, 0.01, snapshot);
      TestEqual(ArraySize(snapshot.records), 1, "repeated evaluation does not duplicate");
      TestAssert(snapshot.records[0].id == stable, "stable ID across evaluations");
     }
   rates[20].open = 103;
   rates[20].close = 100;
   SmcDetectDisplacement(rates, config, "TEST", PERIOD_M5, 0.01, snapshot);
   TestEqual(snapshot.records[0].direction, -1, "bearish direction");
   for(int i = 0; i < 20; i++) rates[i].close = rates[i].open;
   TestAssert(!SmcIsDisplacement(rates, 20, config), "zero mean body rejected");
   rates[20].open = 100;
   rates[20].high = 100;
   rates[20].low = 100;
   TestAssert(!SmcIsDisplacement(rates, 20, config), "zero range rejected");
   DisplacementFixture(rates, 25);
   rates[20].close = 103;
   rates[20].high = 104;
   rates[24].close = 104;
   rates[24].high = 104;
   config.lookbackBars = 2;
   snapshot.asOf = rates[24].time + 300;
   SmcDetectDisplacement(rates, config, "TEST", PERIOD_M5, 0.01, snapshot);
   TestEqual(ArraySize(snapshot.records), 1, "report horizon retains latest candidate only");
   if(ArraySize(snapshot.records) == 1)
      TestEqual(snapshot.records[0].sourceTime, rates[24].time, "baseline outside horizon still used");
   ArrayResize(rates, 20);
   SmcDetectDisplacement(rates, config, "TEST", PERIOD_M5, 0.01, snapshot);
   TestEqual(snapshot.modules[0].status, SMC_STATUS_NOT_READY, "missing history has explicit status");
   TestEqual(ArraySize(snapshot.records), 0, "failed refresh clears earlier concept records");
   config.enableDisplacement = false;
   SmcDetectDisplacement(rates, config, "TEST", PERIOD_M5, 0.01, snapshot);
   TestEqual(snapshot.modules[0].status, SMC_STATUS_DISABLED, "disabled status explicit");
   config.enableDisplacement = true;
   config.displacementMultiplier = 0;
   SmcDetectDisplacement(rates, config, "TEST", PERIOD_M5, 0.01, snapshot);
   TestEqual(snapshot.modules[0].status, SMC_STATUS_ERROR, "invalid threshold fails closed");
   config.SetDefaults();
   config.displacementBaseline = 2;
   DisplacementFixture(rates, 3);
   rates[0].time = D'2025.12.01';
   rates[1].time = D'2026.01.01';
   rates[2].time = D'2026.02.01';
   rates[2].close = 103;
   rates[2].high = 104;
   snapshot.asOf = D'2026.03.01';
   SmcDetectDisplacement(rates, config, "TEST", PERIOD_MN1, 0.01, snapshot);
   TestEqual(ArraySize(snapshot.records), 1, "monthly displacement detected");
   if(ArraySize(snapshot.records) == 1)
      TestEqual(snapshot.records[0].confirmedAt, D'2026.03.01', "February confirms at March first");
   rates[0].time = D'2026.01.01';
   rates[1].time = D'2026.02.01';
   rates[2].time = D'2026.03.01';
   snapshot.asOf = D'2026.04.01';
   SmcDetectDisplacement(rates, config, "TEST", PERIOD_MN1, 0.01, snapshot);
   TestEqual(ArraySize(snapshot.records), 1, "March displacement detected");
   if(ArraySize(snapshot.records) == 1)
      TestEqual(snapshot.records[0].confirmedAt, D'2026.04.01', "March confirms at April first");
   TestFinish();
  }
