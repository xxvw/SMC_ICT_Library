#property strict
#include <SMC/Liquidity.mqh>
#include <SMC/MarketStructure.mqh>
#include <SMC/PremiumDiscount.mqh>
#include "TestHarness.mqh"

class LegacyRatesProbe : public CSmcBase
  {
public:
   void Start() { m_initialized = true; }
   virtual bool Update() { return PrepareRates(); }
   double Value(const int shift) const { return Close(shift); }
   string Prefix() const { return m_prefix; }
   bool HasCapturedContext() const { return m_ratesContextAttempted; }
  };

class LegacySwingFixture : public CSmcSwingPoints
  {
public:
   void UseFiveDigits()
     { m_point = 0.00001; m_tickSize = 0.00001; m_pipSize = 0.0001; m_digits = 5; }
   void Start()
     {
      m_initialized = true; m_enableDraw = false;
      m_point = 0.1; m_tickSize = 0.1; m_pipSize = 0.1; m_digits = 1;
      SetSwingPeriod(1);
     }
  };

class LegacyStructureFixture : public CSmcMarketStructure
  {
public:
   void UseFixturePrices()
     { m_point = 0.1; m_tickSize = 0.1; m_pipSize = 0.1; m_digits = 1; }
  };

class LegacyLiquidityFixture : public CSmcLiquidity
  {
public:
   void UseFiveDigits()
     { m_point = 0.00001; m_tickSize = 0.00001; m_pipSize = 0.0001; m_digits = 5; }
   void UseFixturePrices()
     { m_point = 0.1; m_tickSize = 0.1; m_pipSize = 0.1; m_digits = 1; }
  };

void LegacyCandle(MqlRates &bar, const int index, const double center)
  {
   ZeroMemory(bar);
   bar.time = D'2025.01.06 00:00:00' + index * 60;
   bar.open = center; bar.close = center;
   bar.high = center + 0.1; bar.low = center - 0.1;
   bar.tick_volume = 10;
  }

void TestSharedContext()
  {
   LegacyRatesProbe first, second;
   first.Start(); second.Start();
   TestAssert(!first.HasCapturedContext(), "legacy fallback only before first capture attempt");
   TestAssert(first.Prefix() != second.Prefix(), "drawing prefixes isolate instances");
   MqlRates rates[];
   ArrayResize(rates, 3);
   LegacyCandle(rates[0], 0, 10); LegacyCandle(rates[1], 1, 20);
   LegacyCandle(rates[2], 2, 999);
   first.SetRates(rates);
   TestAssert(first.Update(), "valid shared history needs no terminal request");
   TestEqual(first.RatesCount(), 3, "all supplied bars retained");
   TestNear(first.Value(1), 20, 0.0001, "shift one is last closed candle");
   rates[1].close = 777;
   TestNear(first.Value(1), 20, 0.0001, "context is copied instead of aliased");
   rates[1].time = rates[0].time;
   first.SetRates(rates);
   TestAssert(!first.Update(), "unordered or malformed rates rejected");
   ArrayResize(rates, 0);
   first.SetRates(rates);
   TestAssert(!first.Update(), "missing history rejected");
   TestAssert(first.HasCapturedContext(), "failed capture keeps explicit context active");
   TestNear(first.Value(1), 0, 0, "failed injection cannot fall back to terminal prices");
  }

void TestSwingConfirmation()
  {
   LegacySwingFixture swings;
   swings.Start();
   MqlRates rates[];
   ArrayResize(rates, 4);
   LegacyCandle(rates[0], 0, 10); LegacyCandle(rates[1], 1, 12);
   LegacyCandle(rates[2], 2, 11); LegacyCandle(rates[3], 3, 999);
   swings.SetRates(rates);
   TestAssert(swings.Update(), "swing replay available with exact confirmation history");
   TestEqual(swings.GetHighCount(), 1, "one confirmed swing high");
   SmcSwingPoint high;
   TestAssert(swings.GetSwingHigh(0, high), "retrieve confirmed high");
   TestEqual(high.time, rates[1].time, "swing source timestamp");
   TestEqual(high.confirmedTime, rates[2].time, "right-side confirmation timestamp");
   TestAssert(!high.isBroken, "forming spike cannot break confirmed swing");
   LegacyCandle(rates[3], 3, 1);
   swings.SetRates(rates);
   TestAssert(swings.Update(), "repeat replay succeeds");
   TestEqual(swings.GetHighCount(), 1, "forming mutations do not create pivots");
   ArrayResize(rates, 3);
   swings.SetRates(rates);
   TestAssert(!swings.Update(), "unclosed right side is insufficient history");
   TestEqual(swings.GetHighCount(), 0, "failure clears stale swings");
  }

void TestStructureReplay()
  {
   LegacySwingFixture swings;
   swings.Start();
   LegacyStructureFixture structure;
   if(!structure.Init("EURUSD", PERIOD_M1, false, GetPointer(swings)))
     { TestAssert(false, "fixture symbol metadata available for structure initialization"); return; }
   structure.UseFixturePrices();
   double centers[] = {10,12,11,14,13,15,14,16,12,11,13,10};
   MqlRates rates[];
   ArrayResize(rates, ArraySize(centers));
   for(int i = 0; i < ArraySize(centers); i++) LegacyCandle(rates[i], i, centers[i]);
   swings.SetRates(rates); TestAssert(swings.Update(), "shared swings ready");
   structure.SetRates(rates); TestAssert(structure.Update(), "structure replay succeeds");
   SmcStructureBreak bos, choch;
   TestAssert(structure.GetLastBOS(bos), "bullish BOS found");
   TestEqual(bos.time, rates[7].time, "latest BOS retains first crossing time");
   TestAssert(bos.isBullish, "BOS direction");
   TestAssert(structure.GetLastCHoCH(choch), "bearish CHoCH found");
   TestEqual(choch.time, rates[8].time, "CHoCH uses closed reversal candle");
   TestAssert(!choch.isBullish, "CHoCH direction");
   TestAssert(structure.Update(), "repeat same input succeeds");
   SmcStructureBreak repeated;
   TestAssert(structure.GetLastCHoCH(repeated), "repeated CHoCH retained");
   TestEqual(repeated.time, choch.time, "repeat evaluation does not move event");
   LegacyCandle(rates[11], 11, 999);
   structure.SetRates(rates); TestAssert(structure.Update(), "forming mutation replay succeeds");
   TestAssert(structure.GetLastCHoCH(repeated), "forming mutation retains CHoCH");
   TestEqual(repeated.time, choch.time, "forming bar does not rewrite structure");
   ArrayResize(rates, 0); structure.SetRates(rates);
   TestAssert(!structure.Update(), "failed context rejected");
   TestEqual(structure.GetEntryDirection(), SIGNAL_WAIT, "failed update returns WAIT");
   TestAssert(!structure.GetLastCHoCH(repeated), "failed update does not publish stale event");
  }

bool FindHighLevel(LegacyLiquidityFixture &liquidity, SmcLiquidityLevel &level)
  {
   for(int i = 0; i < liquidity.GetLevelCount(); i++)
      if(liquidity.GetLevel(i, level) && level.IsHighSide()) return true;
   return false;
  }

void TestLiquidityReplay()
  {
   LegacySwingFixture swings;
   swings.Start();
   LegacyLiquidityFixture liquidity;
   if(!liquidity.Init("EURUSD", PERIOD_M1, false, GetPointer(swings), 0))
     { TestAssert(false, "fixture symbol metadata available for liquidity initialization"); return; }
   liquidity.UseFixturePrices();
   MqlRates rates[];
   ArrayResize(rates, 6);
   double centers[] = {10,12,11,12,11,20};
   for(int i = 0; i < 6; i++) LegacyCandle(rates[i], i, centers[i]);
   liquidity.SetRates(rates);
   TestAssert(liquidity.Update(), "two-touch level replay succeeds");
   SmcLiquidityLevel level;
   TestAssert(FindHighLevel(liquidity, level), "equal highs become one level");
   TestEqual(level.touchCount, 2, "each confirmed pivot counted exactly once");
   TestAssert(!level.isSweep, "forming bar cannot sweep liquidity");
   liquidity.SetMinTouches(3);
   TestAssert(liquidity.Update(), "minimum touch setting applies");
   TestAssert(!FindHighLevel(liquidity, level), "two touches do not satisfy configured three");
   liquidity.SetMinTouches(2);
   ArrayResize(rates, 7);
   LegacyCandle(rates[5], 5, 11.5); rates[5].high = 12.2;
   LegacyCandle(rates[6], 6, 10);
   liquidity.SetRates(rates);
   TestAssert(liquidity.Update(), "post-formation sweep replay succeeds");
   TestAssert(FindHighLevel(liquidity, level), "swept level remains historical result");
   TestAssert(level.isSweep, "one tick sweep detected");
   TestEqual(level.sweepTime, rates[5].time, "first sweep timestamp");
   TestEqual(level.touchCount, 2, "sweep candle is not another equal swing touch");
   TestAssert(liquidity.Update(), "repeat liquidity replay succeeds");
   TestAssert(FindHighLevel(liquidity, level), "repeat swept result");
   TestEqual(level.touchCount, 2, "repeat replay cannot accumulate touches");
   TestEqual(level.sweepTime, rates[5].time, "repeat replay retains first sweep");
   ArrayResize(rates, 0); liquidity.SetRates(rates);
   TestAssert(!liquidity.Update(), "liquidity rejects missing data");
   TestEqual(liquidity.GetLevelCount(), 0, "failure clears stale levels");
  }

void TestDirectionalSweepRecency()
  {
   LegacySwingFixture swings;
   swings.Start();
   LegacyLiquidityFixture liquidity;
   TestAssert(liquidity.Init("EURUSD", PERIOD_M1, false, GetPointer(swings), 0), "recency fixture initialization");
   liquidity.UseFixturePrices();
   double centers[] = {10,12,11,12,11,11.5,10,9,10,9,10,9.5,9.5};
   MqlRates rates[];
   ArrayResize(rates, ArraySize(centers));
   for(int i = 0; i < ArraySize(centers); i++) LegacyCandle(rates[i], i, centers[i]);
   rates[5].high = 12.2;
   rates[11].low = 8.8;
   liquidity.SetRates(rates);
   TestAssert(liquidity.Update(), "opposite sweep replay");
   TestAssert(liquidity.IsLiquiditySweep(LIQ_SWEEP_HIGH), "historical high sweep remains retrievable");
   TestAssert(!liquidity.HasRecentSweep(LIQ_SWEEP_HIGH, 5), "old high sweep cannot support current sell confluence");
   TestAssert(liquidity.HasRecentSweep(LIQ_SWEEP_LOW, 5), "recent low sweep supports current buy confluence");
   TestAssert(liquidity.HasRecentSweep(5), "legacy any-direction recency overload retained");
  }

void TestFiveDigitExactTicks()
  {
   LegacySwingFixture swings;
   swings.Start(); swings.UseFiveDigits();
   LegacyLiquidityFixture liquidity;
   TestAssert(liquidity.Init("EURUSD", PERIOD_M1, false, GetPointer(swings), 0), "five-digit fixture initialization");
   liquidity.UseFiveDigits();
   MqlRates rates[];
   ArrayResize(rates, 7);
   double highs[] = {1.00000,1.00001,1.00000,1.00001,1.00000,1.00002,1.00000};
   for(int i = 0; i < 7; i++)
     {
      LegacyCandle(rates[i], i, 0.99999);
      rates[i].high = highs[i];
      rates[i].low = 0.99998;
     }
   liquidity.SetRates(rates);
   TestAssert(liquidity.Update(), "five-digit equal-high replay");
   SmcLiquidityLevel level;
   TestAssert(FindHighLevel(liquidity, level), "five-digit high level exists");
   TestNear(level.price, 1.00001, 0.000000001, "high-side level precision");
   TestAssert(level.isSweep, "exact one-tick high sweep survives binary rounding");
   TestEqual(level.sweepTime, rates[5].time, "exact high sweep timestamp");
   swings.SetRates(rates);
   TestAssert(swings.Update(), "five-digit swing replay");
   SmcSwingPoint point;
   TestAssert(swings.GetSwingHigh(0, point), "five-digit high swing exists");
   TestAssert(point.isBroken, "exact one-tick high swing break survives binary rounding");

   // Mirror the scenario for the low-side threshold.
   double lows[] = {1.00000,0.99999,1.00000,0.99999,1.00000,0.99998,1.00000};
   for(int i = 0; i < 7; i++)
     {
      LegacyCandle(rates[i], i, 1.00001);
      rates[i].high = 1.00002;
      rates[i].low = lows[i];
     }
   liquidity.SetRates(rates);
   TestAssert(liquidity.Update(), "five-digit equal-low replay");
   TestAssert(liquidity.IsLiquiditySweep(LIQ_SWEEP_LOW), "exact one-tick low sweep survives binary rounding");
   swings.SetRates(rates);
   TestAssert(swings.Update(), "five-digit low swing replay");
   TestAssert(swings.GetSwingLow(0, point), "five-digit low swing exists");
   TestAssert(point.isBroken, "exact one-tick low swing break survives binary rounding");
  }

void TestReinitialization()
  {
   CSmcMarketStructure structure;
   TestAssert(structure.Init("EURUSD", PERIOD_M1), "owned structure initialization");
   CSmcSwingPoints *owned = structure.SwingPoints();
   TestAssert(structure.Init("EURUSD", PERIOD_M1, false, owned), "owned swing alias safely reused");
   TestAssert(structure.SwingPoints() == owned, "same dependency pointer retained");
   owned.SetSwingPeriod(1);
   MqlRates rates[];
   ArrayResize(rates, 4);
   LegacyCandle(rates[0], 0, 10); LegacyCandle(rates[1], 1, 12);
   LegacyCandle(rates[2], 2, 11); LegacyCandle(rates[3], 3, 999);
   structure.SetRates(rates);
   TestAssert(structure.Update(), "reused owned dependency still updates automatically");
   TestEqual(owned.GetHighCount(), 1, "ownership retained after alias initialization");

   CSmcPremiumDiscount pd;
   TestAssert(pd.Init("EURUSD", PERIOD_M1), "owned premium discount initialization");
   CSmcSwingPoints *pdOwned = pd.SwingPoints();
   TestAssert(pd.Init("EURUSD", PERIOD_M1, false, pdOwned), "PD reuses owned pointer");
   pdOwned.SetSwingPeriod(1);
   pd.SetRates(rates);
   TestAssert(pd.Update(), "PD updates reused dependency");
   TestEqual(pdOwned.GetHighCount(), 1, "PD ownership not silently discarded");
   TestAssert(!pd.Init("__SMC_TEST_UNKNOWN__", PERIOD_M1), "invalid PD symbol rejected");
   TestNear(pd.GetSwingHigh(), 0, 0, "failed reinitialization clears prices");

   LegacySwingFixture swings;
   swings.Start(); swings.SetRates(rates); swings.Update();
   TestEqual(swings.GetHighCount(), 1, "swing present before failed init");
   TestAssert(!swings.Init("__SMC_TEST_UNKNOWN__", PERIOD_M1), "invalid swing symbol rejected");
   TestEqual(swings.GetHighCount(), 0, "failed initialization clears swings");
  }

void OnStart()
  {
   TestBegin("legacy-structure");
   TestSharedContext();
   TestSwingConfirmation();
   TestStructureReplay();
   TestLiquidityReplay();
   TestReinitialization();
   TestDirectionalSweepRecency();
   TestFiveDigitExactTicks();
   TestFinish();
  }
