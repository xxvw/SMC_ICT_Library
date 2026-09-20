#property strict
#include <SMC/FairValueGap.mqh>
#include <SMC/BreakerBlock.mqh>
#include "TestHarness.mqh"

class FixtureFVG : public CSmcFairValueGap
  {
public:
   void UseFiveDigits()
     { m_point = 0.00001; m_tickSize = 0.00001; m_pipSize = 0.0001; m_digits = 5; }
   void Configure() { m_point = 1; m_tickSize = 1; m_pipSize = 1; m_digits = 1; }
  };
class FixtureOB : public CSmcOrderBlock
  {
public:
   void Configure() { m_point = 1; m_tickSize = 1; m_pipSize = 1; m_digits = 1; }
  };
class FixtureBreaker : public CSmcBreakerBlock
  {
public:
   void Configure() { m_point = 1; m_tickSize = 1; m_pipSize = 1; m_digits = 1; }
  };

void SetCandle(MqlRates &bar, const int index, const double open,
               const double high, const double low, const double close)
  {
   ZeroMemory(bar);
   bar.time = D'2025.01.06 00:00' + index * 60;
   bar.open = open;
   bar.high = high;
   bar.low = low;
   bar.close = close;
   bar.tick_volume = 100;
  }

void AppendClosed(MqlRates &rates[], const double open, const double high,
                  const double low, const double close)
  {
   int index = ArraySize(rates) - 1;
   ArrayResize(rates, index + 2);
   SetCandle(rates[index], index, open, high, low, close);
   SetCandle(rates[index + 1], index + 1, close, close, close, close);
  }

void FVGFixture(MqlRates &rates[])
  {
   ArrayResize(rates, 28);
   for(int i = 0; i < 24; i++)
      SetCandle(rates[i], i, 98, 99, 98, 98.5);
   SetCandle(rates[24], 24, 99, 100, 96, 97);
   SetCandle(rates[25], 25, 100, 105, 99, 104);
   SetCandle(rates[26], 26, 104, 107, 104, 106);
   SetCandle(rates[27], 27, 106, 106, 106, 106);
  }

bool FindFVG(FixtureFVG &fvg, const datetime sourceTime, SmcZone &zone)
  {
   for(int i = 0; i < fvg.GetBullishCount(); i++)
      if(fvg.GetBullishFVG(i, zone) && zone.formationTime == sourceTime)
         return true;
   zone.Init();
   return false;
  }

bool FindOB(FixtureOB &ob, const datetime sourceTime, SmcZone &zone)
  {
   for(int i = 0; i < ob.GetBullishCount(); i++)
      if(ob.GetBullishOB(i, zone) && zone.formationTime == sourceTime)
         return true;
   zone.Init();
   return false;
  }

void TestFVGLifecycle()
  {
   FixtureFVG fvg;
   TestAssert(fvg.Init("EURUSD", PERIOD_M1), "FVG initialization");
   fvg.Configure();
   MqlRates rates[];
   FVGFixture(rates);
   datetime source = rates[25].time;
   datetime confirmation = rates[26].time;
   SmcZone zone;
   fvg.SetRates(rates);
   TestAssert(fvg.Update(), "FVG initial replay");
   TestAssert(FindFVG(fvg, source, zone), "FVG detected after third candle closes");
   TestEqual(zone.state, ZONE_FRESH, "formation pattern cannot self-touch");
   TestEqual(zone.confirmedTime, confirmation, "FVG confirmation distinct from source");
   TestNear(zone.bottomPrice, 100, 0.001, "FVG lower boundary");
   TestNear(zone.topPrice, 104, 0.001, "FVG upper boundary");
   ENUM_ZONE_PROBABILITY originalProbability = zone.probability;
   SetCandle(rates[27], 27, 106, 10000, 1, 2);
   fvg.SetRates(rates);
   TestAssert(fvg.Update(), "forming-candle change replay");
   TestAssert(FindFVG(fvg, source, zone), "forming-candle change preserves FVG");
   TestEqual(zone.state, ZONE_FRESH, "forming-candle extremes are ignored");
   AppendClosed(rates, 106, 107, 103, 106);
   fvg.SetRates(rates); fvg.Update(); FindFVG(fvg, source, zone);
   TestEqual(zone.state, ZONE_TESTED, "first contact tests FVG");
   AppendClosed(rates, 106, 107, 102, 105);
   fvg.SetRates(rates); fvg.Update(); FindFVG(fvg, source, zone);
   TestEqual(zone.state, ZONE_MITIGATED, "midpoint mitigates FVG");
   AppendClosed(rates, 105, 107, 99, 105);
   fvg.SetRates(rates); fvg.Update(); FindFVG(fvg, source, zone);
   TestEqual(zone.state, ZONE_MITIGATED, "wick-through cannot break FVG");
   AppendClosed(rates, 101, 102, 98, 99);
   fvg.SetRates(rates); fvg.Update(); FindFVG(fvg, source, zone);
   TestEqual(zone.state, ZONE_BROKEN, "one-tick close-through breaks FVG");
   TestAssert(!zone.IsActive(), "broken FVG remains historical but inactive");
   datetime broken = zone.brokenTime;
   fvg.Update(); FindFVG(fvg, source, zone);
   TestEqual(zone.brokenTime, broken, "same input preserves first broken time");
   for(int i = 0; i < 25; i++)
      AppendClosed(rates, 105, 10000, 1, 9000);
   fvg.SetRates(rates); fvg.Update();
   TestAssert(FindFVG(fvg, source, zone), "future large candles preserve historical FVG");
   TestEqual(zone.probability, originalProbability, "future candles cannot change probability");
   TestEqual(zone.confirmedTime, confirmation, "future candles preserve confirmation");
   TestEqual(zone.brokenTime, broken, "future candles preserve first break");
   ArrayResize(rates, 3);
   fvg.SetRates(rates);
   TestAssert(!fvg.Update(), "insufficient history is failure, not empty success");
   TestEqual(fvg.GetBullishCount(), 0, "failed update clears published FVGs");
  }

void TestExpiry()
  {
   FixtureFVG fvg;
   TestAssert(fvg.Init("EURUSD", PERIOD_M1, false, 2, 2), "expiry FVG initialization");
   fvg.Configure();
   MqlRates rates[];
   FVGFixture(rates);
   datetime source = rates[25].time;
   SmcZone zone;
   for(int age = 0; age <= 3; age++)
     {
      fvg.SetRates(rates);
      TestAssert(fvg.Update(), "expiry replay");
      TestAssert(FindFVG(fvg, source, zone), "expired zone remains retrievable");
      TestEqual(zone.age, age, "age starts at confirmation");
      TestEqual(zone.isExpired, age > 2, "expiry occurs strictly after maximum age");
      TestEqual(zone.state, ZONE_FRESH, "expiry is separate from price state");
      TestEqual(zone.IsActive(), age <= 2, "expiry deactivates zone");
      TestEqual(fvg.GetFreshBullishCount(), age <= 2 ? 1 : 0, "fresh counts exclude expiry");
      AppendClosed(rates, 106, 108, 105, 107);
     }
  }

void TestOrderBlockAndBreaker()
  {
   CSmcMarketStructure structure;
   FixtureOB ob;
   TestAssert(ob.Init("EURUSD", PERIOD_M1, false, GetPointer(structure)), "OB initialization");
   ob.Configure();
   FixtureBreaker breaker;
   TestAssert(breaker.Init("EURUSD", PERIOD_M1, false, GetPointer(ob)), "breaker initialization");
   breaker.Configure();
   MqlRates rates[];
   ArrayResize(rates, 27);
   for(int i = 0; i < 24; i++)
      SetCandle(rates[i], i, 101, 103, 100, 102);
   SetCandle(rates[24], 24, 103, 104, 100, 101);
   SetCandle(rates[25], 25, 101, 108, 101, 107);
   SetCandle(rates[26], 26, 107, 107, 107, 107);
   datetime source = rates[24].time;
   datetime confirmed = rates[25].time;
   ob.SetRates(rates);
   TestAssert(ob.Update(), "OB initial replay");
   SmcZone zone;
   TestAssert(FindOB(ob, source, zone), "impulse confirms bullish OB");
   TestEqual(zone.state, ZONE_FRESH, "impulse cannot self-mitigate source OB");
   TestEqual(zone.confirmedTime, confirmed, "OB earliest confirmation recorded");
   AppendClosed(rates, 98, 99, 96, 97);
   datetime activation = rates[ArraySize(rates) - 2].time;
   ob.SetRates(rates); ob.Update(); FindOB(ob, source, zone);
   TestEqual(zone.state, ZONE_BROKEN, "untouched OB can break directly");
   TestAssert(!zone.isValid, "broken source is inactive");
   breaker.SetRates(rates);
   TestAssert(breaker.Update(), "breaker replay");
   TestEqual(breaker.GetBreakerCount(), 1, "invalid broken OB produces one breaker");
   TestAssert(breaker.GetBreakerBlock(0, zone), "breaker retrievable");
   TestAssert(!zone.isBullish && zone.IsActive(), "breaker reverses direction and restores validity");
   TestEqual(zone.state, ZONE_FRESH, "break candle cannot self-touch breaker");
   TestEqual(zone.confirmedTime, activation, "breaker activates on first break");
   TestEqual(zone.age, 0, "breaker age restarts at activation");
   AppendClosed(rates, 99, 101, 98, 99);
   ob.SetRates(rates); ob.Update(); breaker.SetRates(rates); breaker.Update();
   breaker.GetBreakerBlock(0, zone);
   TestEqual(zone.state, ZONE_TESTED, "breaker retest is replayed after activation");
   AppendClosed(rates, 100, 103, 99, 101);
   ob.SetRates(rates); ob.Update(); breaker.SetRates(rates); breaker.Update();
   breaker.GetBreakerBlock(0, zone);
   TestEqual(zone.state, ZONE_MITIGATED, "breaker midpoint mitigation");
   AppendClosed(rates, 104, 107, 103, 105);
   ob.SetRates(rates); ob.Update(); breaker.SetRates(rates); breaker.Update();
   breaker.GetBreakerBlock(0, zone);
   TestEqual(zone.state, ZONE_BROKEN, "breaker close-through invalidates");
   TestAssert(!zone.IsActive(), "broken breaker inactive");
  }

void TestFVGExactMinimum()
  {
   FixtureFVG fvg;
   TestAssert(fvg.Init("EURUSD", PERIOD_M1, false, 0.2), "five-digit FVG initialization");
   fvg.UseFiveDigits();
   MqlRates rates[];
   ArrayResize(rates, 24);
   for(int i = 0; i < 20; i++)
      SetCandle(rates[i], i, 0.99999, 1.00000, 0.99998, 0.99999);
   SetCandle(rates[20], 20, 0.99999, 1.00001, 0.99997, 0.99999);
   SetCandle(rates[21], 21, 1.00000, 1.00005, 0.99999, 1.00004);
   SetCandle(rates[22], 22, 1.00004, 1.00006, 1.00003, 1.00005);
   SetCandle(rates[23], 23, 1.00005, 1.00005, 1.00005, 1.00005);
   fvg.SetRates(rates);
   TestAssert(fvg.Update(), "exact-minimum FVG replay");
   SmcZone zone;
   TestAssert(FindFVG(fvg, rates[21].time, zone), "decimal two-tick gap meets two-tick minimum");
   TestNear(zone.GetSize(), 0.00002, 0.000000001, "two-tick FVG boundaries");
   // A fractional tick in the requested minimum must not be rounded down.
   fvg.SetMinSizePips(0.21);
   TestAssert(fvg.Update(), "fractional-minimum FVG replay");
   TestAssert(!FindFVG(fvg, rates[21].time, zone), "fractional minimum remains strict beyond tolerance");
   // Increase the configured minimum by one actual tick, beyond epsilon.
   fvg.SetMinSizePips(0.3);
   TestAssert(fvg.Update(), "larger-minimum FVG replay");
   TestAssert(!FindFVG(fvg, rates[21].time, zone), "genuinely undersized FVG remains excluded");
  }

void OnStart()
  {
   TestBegin("legacy-zones");
   TestFVGLifecycle();
   TestExpiry();
   TestOrderBlockAndBreaker();
   TestFVGExactMinimum();
   TestFinish();
  }
