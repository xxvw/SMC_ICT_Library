#property strict
#include "TestHarness.mqh"
#include <SMC/Analysis/VIXCalculator.mqh>
#include <SMC/Analysis/CurrencyStrength.mqh>

void Rates(MqlRates &rates[], const int count, const bool alternate = false)
  {
   ArrayResize(rates, count);
   for(int i = 0; i < count; i++)
     {
      ZeroMemory(rates[i]);
      rates[i].time = D'2026.01.05 00:00' + i * 60;
      rates[i].close = alternate && i % 2 == 1 ? 110 : 100;
      rates[i].open = rates[i].close;
      rates[i].high = rates[i].close + 1;
      rates[i].low = rates[i].close - 1;
      rates[i].tick_volume = 100;
     }
  }

void CheckVixUnavailable(CSmcVIXCalculator &vix, const string reason)
  {
   TestAssert(!vix.IsReady(), reason + ": not ready");
   TestNear(vix.GetVIX(), 0, 0, reason + ": stale value cleared");
   TestEqual(vix.GetVIXTrend(), 0, reason + ": stale trend cleared");
   TestNear(vix.GetVIXMA(), 0, 0, reason + ": stale history cleared");
   TestAssert(!vix.IsEntryAllowed(), reason + ": entry waits for valid data");
   TestNear(vix.GetLotMultiplier(), 0, 0, reason + ": no lot guidance while unavailable");
   TestAssert(vix.GetVIXLevelName() == "Not ready", reason + ": explicit display status");
  }

void TestSharedVix()
  {
   CSmcVIXCalculator vix;
   TestAssert(vix.Init("EURUSD", PERIOD_M1, false, 5, PERIOD_M1), "VIX shared initialization");
   MqlRates rates[];
   Rates(rates, 7, true);
   // A large forming-candle move must not enter any return.
   rates[6].open = rates[6].close = 10000;
   rates[6].high = 10001;
   rates[6].low = 9999;
   vix.SetRates(rates);
   TestAssert(vix.Update(), "valid completed shared history is ready");
   TestAssert(vix.IsReady(), "readiness distinguishable from numeric value");
   TestNear(vix.GetVIX(), 165.74108679498343, 0.00001, "five completed alternating log returns");
   double original = vix.GetVIX();
   TestAssert(vix.Update(), "same shared context can be reevaluated");
   TestNear(vix.GetVIX(), original, 0, "same candle is deterministic");
   TestNear(vix.GetPercentile(), 50, 0, "same candle does not duplicate history");
   Rates(rates, 7, false);
   vix.SetRates(rates);
   TestAssert(vix.Update(), "constant closes are valid zero variance");
   TestAssert(vix.IsReady(), "zero volatility remains ready");
   TestNear(vix.GetVIX(), 0, 0, "constant closes produce zero");
   TestAssert(vix.IsEntryAllowed(), "valid zero volatility uses normal policy");
   TestNear(vix.GetVIXMA(0), 0, 0, "invalid MA period cannot divide by zero");
   TestNear(vix.GetPercentile(0), 0, 0, "invalid percentile period cannot divide by zero");

   Rates(rates, 3);
   vix.SetRates(rates);
   TestAssert(!vix.Update(), "too little shared history fails");
   CheckVixUnavailable(vix, "short history");
   Rates(rates, 7, true);
   vix.SetRates(rates);
   TestAssert(vix.Update(), "valid data recovers after history failure");
   rates[3].open = rates[3].high = rates[3].low = rates[3].close = 0;
   vix.SetRates(rates);
   TestAssert(!vix.Update(), "zero close is invalid for logarithmic returns");
   CheckVixUnavailable(vix, "invalid close");
   Rates(rates, 7, true);
   vix.SetRates(rates);
   TestAssert(vix.Update(), "recover before failed reinitialization");
   TestAssert(!vix.Init("SMC_MISSING_ANALYSIS_SYMBOL", PERIOD_M1), "invalid symbol initialization fails");
   CheckVixUnavailable(vix, "failed initialization");
   TestAssert(vix.Init("EURUSD", PERIOD_M1, false, 2147483647, PERIOD_M1), "large legacy period initializes");
   Rates(rates, 7);
   vix.SetRates(rates);
   TestAssert(!vix.Update(), "unrepresentable history request cannot overflow array bounds");
  }

void TestTerminalVix()
  {
   string symbol = "SV" + StringSubstr(SMC_TestRunId, 0, 20);
   bool created = CustomSymbolCreate(symbol, "SMCTests", "EURUSD");
   TestAssert(created, "create volatility history symbol");
   if(!created) return;
   TestAssert(SymbolSelect(symbol, true), "select volatility symbol");
   MqlRates rates[];
   Rates(rates, 40, false);
   TestEqual(CustomRatesUpdate(symbol, rates), 40, "import constant terminal closes");
   {
      CSmcVIXCalculator vix;
      TestAssert(vix.Init(symbol, PERIOD_M1, false, 5, PERIOD_M1), "standalone volatility init");
      TestAssert(vix.Update(), "standalone confirmed rates ready");
      TestNear(vix.GetVIX(), 0, 0, "terminal zero variance is valid");
      TestAssert(vix.IsReady(), "terminal zero variance readiness");
      // The shared M1 cache cannot satisfy the legacy D1 calculation horizon.
      TestAssert(vix.Init(symbol, PERIOD_M1, false, 5, PERIOD_D1), "independent D1 volatility init");
      vix.SetRates(rates);
      TestAssert(!vix.Update(), "M1 shared data cannot disguise missing D1 history");
      CheckVixUnavailable(vix, "missing calculation timeframe");
   }
   TestAssert(SymbolSelect(symbol, false), "deselect volatility symbol");
   TestAssert(CustomSymbolDelete(symbol), "delete volatility symbol");
  }

void TestCurrencyCoverage()
  {
   string names[] = {"EURUSD", "USDGBP", "USDJPY", "USDAUD", "USDCAD", "USDNZD", "USDCHF"};
   string symbols[];
   ArrayResize(symbols, 7);
   string suffix = ".t" + StringSubstr(SMC_TestRunId, 0, 8);
   bool created[7];
   ArrayInitialize(created, false);
   MqlRates rates[];
   Rates(rates, 12);
   for(int i = 0; i < ArraySize(rates); i++)
     {
      rates[i].open = rates[i].close = 100 + i;
      rates[i].high = 101 + i;
      rates[i].low = 99 + i;
     }
   bool available = true;
   for(int pair = 0; pair < 7; pair++)
     {
      symbols[pair] = names[pair] + suffix;
      created[pair] = CustomSymbolCreate(symbols[pair], "SMCTests", "EURUSD");
      TestAssert(created[pair], "create currency fixture " + names[pair]);
      if(!created[pair]) { available = false; continue; }
      TestAssert(SymbolSelect(symbols[pair], true), "select currency fixture");
      TestEqual(CustomRatesUpdate(symbols[pair], rates), 12, "import closed currency history");
     }
   if(available)
     {
      CSmcCurrencyStrength strength;
      TestAssert(strength.Init(symbols[2], PERIOD_M1, false, CS_METHOD_RATE_CHANGE, 3), "currency analysis init");
      strength.SetRates(rates);
      TestAssert(strength.Update(), "seven crosses cover all eight currencies");
      TestNear(strength.GetStrength("USD"), 100, 0.000001, "USD contributions normalized");
      TestNear(strength.GetStrength("EUR"), 20, 0.000001, "reversed EURUSD contribution oriented correctly");
      TestAssert(strength.GetStrongest() == "USD", "valid strongest currency");
      TestNear(strength.GetMomentum("USD"), 0, 0, "first valid result has no invented momentum");
      TestAssert(strength.Update(), "currency repeated update succeeds");
      TestNear(strength.GetMomentum("USD"), 0, 0, "same candle momentum remains stable");
      string ranked[];
      strength.GetSortedCurrencies(ranked);
      TestEqual(ArraySize(ranked), 8, "all eight ranks published when covered");
      SmcCurrencyInfo info;
      TestAssert(strength.GetCurrencyInfo("CHF", info), "covered currency info available");
      TestEqual(CustomRatesDelete(symbols[6], rates[10].time, rates[10].time), 1, "remove exact CHF anchor");
      TestAssert(!strength.Update(), "missing one currency fails complete ranking");
      TestNear(strength.GetStrength("USD"), 0, 0, "failure clears previously strong USD");
      TestNear(strength.GetMomentum("USD"), 0, 0, "failure clears momentum");
      TestEqual(strength.GetRank("USD"), 0, "failure clears ranks");
      TestAssert(strength.GetStrongest() == "", "failure exposes no strongest currency");
      TestAssert(strength.GetBestPair() == "", "failure exposes no best pair");
      TestAssert(!strength.GetCurrencyInfo("CHF", info), "missing currency info is unavailable");
      TestEqual(info.rank, 0, "output parameter cannot preserve stale rank");
      strength.GetSortedCurrencies(ranked);
      TestEqual(ArraySize(ranked), 0, "failure empties sorted currency output");
      string fixedRanks[8];
      for(int i = 0; i < 8; i++) fixedRanks[i] = "stale";
      strength.GetSortedCurrencies(fixedRanks);
      for(int i = 0; i < 8; i++)
         TestAssert(fixedRanks[i] == "", "failure clears fixed-size sorted output");
      TestEqual(CustomRatesUpdate(symbols[6], rates), 12, "restore missing currency candle");
      TestAssert(strength.Update(), "currency data recovery succeeds");
      TestNear(strength.GetMomentum("USD"), 0, 0, "recovery does not invent momentum jump");
      strength.SetMethod(CS_METHOD_RSI);
      TestAssert(strength.Update(), "RSI requires usable exact closed buffers for every currency");
      TestAssert(strength.GetCurrencyInfo("USD", info), "RSI result published after all coverage checks");
      strength.SetPeriod(20);
      TestAssert(!strength.Update(), "insufficient period history fails RSI readiness");
      TestAssert(!strength.GetCurrencyInfo("USD", info), "RSI history failure clears info");
      TestAssert(!strength.Init("SMC_MISSING_ANALYSIS_SYMBOL", PERIOD_M1), "invalid currency initialization fails");
      TestEqual(strength.GetRank("USD"), 0, "failed initialization clears rank");
     }
   for(int pair = 0; pair < 7; pair++)
      if(created[pair])
        {
         TestAssert(SymbolSelect(symbols[pair], false), "deselect currency fixture");
         TestAssert(CustomSymbolDelete(symbols[pair]), "delete currency fixture");
        }
  }

void OnStart()
  {
   TestBegin("Analysis readiness");
   TestSharedVix();
   TestTerminalVix();
   TestCurrencyCoverage();
   TestFinish();
  }
