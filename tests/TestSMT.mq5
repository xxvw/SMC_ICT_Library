#property strict
#include "TestHarness.mqh"
#include <SMC/ICT/SMTDivergence.mqh>

void SMTBars(MqlRates &rates[], const bool primary)
  {
   ArrayResize(rates, 9);
   double highs[] = {10,12,10,11,13,10,11,12,10};
   double lows[] = {8,8,6,8,8,5,8,8,7};
   double comparisonHighs[] = {20,22,20,21,21,20,21,22,20};
   double comparisonLows[] = {18,18,16,18,18,17,18,18,17};
   for(int i = 0; i < 9; i++)
     {
      ZeroMemory(rates[i]);
      rates[i].time = D'2025.01.06 00:00' + i*60;
      rates[i].high = primary ? highs[i] : comparisonHighs[i];
      rates[i].low = primary ? lows[i] : comparisonLows[i];
      rates[i].open = (rates[i].high+rates[i].low)/2;
      rates[i].close = rates[i].open;
     }
  }

ENUM_SMC_STATUS SMTStatus(const SmcSnapshot &snapshot)
  {
   for(int i = 0; i < ArraySize(snapshot.modules); i++)
      if(snapshot.modules[i].concept == ICT_SMT) return snapshot.modules[i].status;
   return SMC_STATUS_ERROR;
  }

int SMTCount(const SmcSnapshot &snapshot, const int direction = 0)
  {
   int count = 0;
   for(int i = 0; i < ArraySize(snapshot.records); i++)
      if(snapshot.records[i].concept == ICT_SMT &&
         (direction == 0 || snapshot.records[i].direction == direction)) count++;
   return count;
  }

void OnStart()
  {
   TestBegin("smt");
   MqlRates primary[], companion[];
   SMTBars(primary, true);
   SMTBars(companion, false);
   SmcConfig config;
   config.SetDefaults();
   config.swingStrength = 1;
   config.smtRadius = 1;
   config.smtSymbol = "COMPARE";
   SmcSnapshot snapshot;
   snapshot.Reset();
   snapshot.asOf = primary[8].time+60;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTStatus(snapshot), SMC_STATUS_READY, "aligned histories are ready");
   TestEqual(SMTCount(snapshot, -1), 1, "higher high with no comparison higher high is bearish");
   TestEqual(SMTCount(snapshot, 1), 1, "lower low with no comparison lower low is bullish");
   string firstId = snapshot.records[0].id;
   TestEqual(snapshot.records[0].sourceTime, primary[4].time, "source time identifies primary pivot");
   TestEqual(snapshot.records[0].confirmedAt, primary[5].time+60, "pivot waits for right-side confirmation");
   TestNear(snapshot.records[0].referencePrice, 22, 0, "comparison reference is prior pivot neighborhood extreme");
   TestNear(snapshot.records[0].comparisonPrice, 21, 0, "comparison value is current pivot neighborhood extreme");
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTCount(snapshot), 2, "repeated update has no duplicate records");
   TestAssert(snapshot.records[0].id == firstId, "repeated update preserves stable ID");

   snapshot.asOf = primary[4].time+60;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTCount(snapshot), 0, "future primary and companion bars cannot confirm a pivot early");
   snapshot.asOf = primary[5].time+60;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTCount(snapshot), 1, "event appears exactly when right confirmation bar closes");
   TestAssert(snapshot.records[0].id == firstId, "later data does not change historical ID");

   snapshot.asOf = primary[8].time+60;
   companion[4].time++;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTStatus(snapshot), SMC_STATUS_NOT_READY, "missing exact timestamp is not ready");
   TestEqual(SMTCount(snapshot), 0, "alignment failure clears previous detections");
   SMTBars(companion, false);
   companion[7].time++;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTStatus(snapshot), SMC_STATUS_READY, "unrelated missing timestamp does not invalidate pivot comparisons");
   TestEqual(SMTCount(snapshot), 2, "unrelated timestamp gap preserves complete candidate comparisons");
   SMTBars(companion, false);
   ArrayResize(companion, 8);
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTStatus(snapshot), SMC_STATUS_NOT_READY, "lagging companion cannot publish current results");
   TestEqual(SMTCount(snapshot), 0, "common watermark prevents stale companion results");

   SMTBars(companion, false);
   companion[4].high = 23;
   companion[5].low = 15;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTStatus(snapshot), SMC_STATUS_READY, "non-divergent aligned history is ready");
   TestEqual(SMTCount(snapshot), 0, "companion matching both extremes has no divergence");
   SMTBars(companion, false);
   primary[4].high = 12.5;
   primary[5].low = 5.5;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTCount(snapshot), 0, "primary move below one tick is not a new extreme");
   SMTBars(primary, true);
   primary[1].high = 12.9;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 0.1, 0.1, snapshot);
   TestEqual(SMTCount(snapshot, -1), 1, "decimal one-tick primary move survives floating point rounding");
   companion[4].high = 22.1;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 0.1, 0.1, snapshot);
   TestEqual(SMTCount(snapshot, -1), 0, "decimal one-tick comparison move prevents false divergence");
   SMTBars(primary, true);
   SMTBars(companion, false);

   config.lookbackBars = 3;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTCount(snapshot, -1), 0, "old confirmation excluded from reporting horizon");
   TestEqual(SMTCount(snapshot, 1), 1, "warmup pivot remains available to in-horizon event");
   config.lookbackBars = 2;
   snapshot.asOf = primary[6].time+60;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTCount(snapshot), 0, "previous pivot beyond dependency horizon is not compared");
   config.lookbackBars = 500;
   config.smtRadius = 2;
   snapshot.asOf = primary[5].time+60;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTCount(snapshot), 0, "larger comparison radius waits for its own right-side bars");
   snapshot.asOf = primary[8].time+60;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTStatus(snapshot), SMC_STATUS_NOT_READY, "missing prior pivot neighborhood requires warmup history");
   SmcRecord unrelated;
   unrelated.Init();
   unrelated.id = "unrelated-record";
   unrelated.concept = ICT_DISPLACEMENT;
   SmcAppendRecord(snapshot, unrelated);

   config.smtSymbol = "";
   config.enableSMT = false;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTStatus(snapshot), SMC_STATUS_DISABLED, "unspecified companion disables SMT");
   TestEqual(SMTCount(snapshot), 0, "disabled module exposes no stale records");
   TestEqual(ArraySize(snapshot.records), 1, "SMT refresh preserves other concept records");
   TestAssert(snapshot.records[0].id == "unrelated-record", "unrelated record is unchanged");
   config.enableSMT = true;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTStatus(snapshot), SMC_STATUS_NOT_READY, "explicit enable still requires a companion symbol");
   config.smtSymbol = "COMPARE";
   config.smtRadius = 1;
   primary[4].high = primary[4].low-1;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTStatus(snapshot), SMC_STATUS_ERROR, "invalid primary OHLC envelope is an error");
   SMTBars(primary, true);
   companion[4].low = MathSqrt(-1.0);
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTStatus(snapshot), SMC_STATUS_ERROR, "nonfinite companion price is an error");
   SMTBars(companion, false);
   primary[0].time = 0;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTStatus(snapshot), SMC_STATUS_ERROR, "nonpositive timestamp is an error");
   SMTBars(primary, true);
   ArraySetAsSeries(primary, true);
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTStatus(snapshot), SMC_STATUS_ERROR, "series-order input is rejected explicitly");
   ArraySetAsSeries(primary, false);
   companion[4].time = companion[3].time;
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 1, snapshot);
   TestEqual(SMTStatus(snapshot), SMC_STATUS_ERROR, "duplicate comparison timestamp is an error");
   TestEqual(SMTCount(snapshot), 0, "invalid input never exposes stale SMT results");
   ArrayResize(companion, 0);
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 0, snapshot);
   TestEqual(SMTStatus(snapshot), SMC_STATUS_NOT_READY, "unavailable comparison symbol has no tick metadata yet");
   SMTBars(companion, false);
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_M1, 1, 0, snapshot);
   TestEqual(SMTStatus(snapshot), SMC_STATUS_ERROR, "available history with invalid comparison tick is an error");
   SMTBars(primary, true);
   SMTBars(companion, false);
   for(int i = 0; i < ArraySize(primary); i++)
     {
      primary[i].time = StringToTime("2025." + IntegerToString(i+1) + ".01");
      companion[i].time = primary[i].time;
     }
   snapshot.asOf = D'2025.10.01';
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_MN1, 1, 1, snapshot);
   TestEqual(SMTStatus(snapshot), SMC_STATUS_READY, "monthly common watermark uses calendar close");
   TestEqual(SMTCount(snapshot), 2, "monthly SMT events detected");
   for(int i = 0; i < ArraySize(snapshot.records); i++)
      if(snapshot.records[i].concept == ICT_SMT && snapshot.records[i].direction == 1)
         TestEqual(snapshot.records[i].confirmedAt, D'2025.08.01', "July confirmation candle closes August first");
   snapshot.asOf = D'2025.07.01';
   SmcDetectSMT(primary, companion, config, "PRIMARY", PERIOD_MN1, 1, 1, snapshot);
   TestEqual(SMTCount(snapshot, 1), 0, "unclosed July month cannot confirm bullish SMT early");
   TestFinish();
  }
