#property strict
#include "TestHarness.mqh"

void OnStart()
{
   TestBegin("runtime-smoke");
   MqlRates bars[];
   ArrayResize(bars, 2);
   ZeroMemory(bars);
   bars[0].time = D'2026.01.05 00:00';
   bars[0].open = 100.0;
   bars[0].high = 103.0;
   bars[0].low = 99.0;
   bars[0].close = 102.0;
   bars[1] = bars[0];
   bars[1].time += 60;
   TestEqual(ArraySize(bars), 2, "synthetic rates execute in the MQL runtime");
   TestNear(bars[0].close - bars[0].open, 2.0, 0.000001, "synthetic candle body");
   TestEqual(bars[1].time - bars[0].time, 60, "broker-clock timestamps");
   TestFinish();
}
