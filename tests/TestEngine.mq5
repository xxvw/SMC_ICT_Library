#property strict
#include "TestHarness.mqh"
#include "../Include/SMC/Core/IctEngine.mqh"

void EngineConfig(SmcConfig &config)
  {
   config.SetDefaults();
   config.lookbackBars = 10;
   config.maxRecordsPerConcept = 20;
   config.swingStrength = 2;
   config.displacementBaseline = 3;
   config.maxZoneAge = 3;
   config.bprMaxSeparation = 3;
   config.po3ExpiryBars = 3;
   config.smtRadius = 1;
   config.enableCalendar = false;
   config.enableSMT = false;
   config.enablePO3 = false;
   config.enableDisplacement = false;
   config.enableMSS = false;
   config.enableIFVG = false;
   config.enableBPR = false;
  }

void EngineRates(MqlRates &rates[], const int count)
  {
   ArrayResize(rates, count);
   ArraySetAsSeries(rates, false);
   for(int i = 0; i < count; i++)
     {
      ZeroMemory(rates[i]);
      rates[i].time = D'2026.01.05 00:00' + i * 60;
      rates[i].open = 100.0;
      rates[i].high = 100.2;
      rates[i].low = 99.9;
      rates[i].close = 100.1;
      rates[i].tick_volume = 10;
     }
  }

int EngineModuleIndex(const SmcSnapshot &snapshot, const ENUM_SMC_CONCEPT concept)
  {
   for(int i = 0; i < ArraySize(snapshot.modules); i++)
      if(snapshot.modules[i].concept == concept) return i;
   return -1;
  }

void EngineModuleIs(const SmcSnapshot &snapshot, const ENUM_SMC_CONCEPT concept,
                    const ENUM_SMC_STATUS status, const string label)
  {
   int index = EngineModuleIndex(snapshot, concept);
   TestAssert(index >= 0, label + " module is present");
   if(index >= 0) TestEqual(snapshot.modules[index].status, status, label);
  }

void EngineRecord(SmcSnapshot &snapshot, const string id,
                  const ENUM_SMC_CONCEPT concept, const datetime source,
                  const datetime confirmation, const bool active = true)
  {
   SmcRecord record;
   record.Init();
   record.id = id;
   record.concept = concept;
   record.sourceTime = source;
   record.confirmedAt = confirmation;
   record.updatedAt = confirmation;
   record.lower = 99.0;
   record.upper = 101.0;
   record.active = active;
   TestAssert(SmcAppendRecord(snapshot, record), "fixture record accepted: " + id);
  }

bool EngineHasRecord(const SmcSnapshot &snapshot, const string id)
  {
   for(int i = 0; i < ArraySize(snapshot.records); i++)
      if(snapshot.records[i].id == id) return true;
   return false;
  }

void EngineSnapshotsEqual(const SmcSnapshot &actual, const SmcSnapshot &expected)
  {
   TestAssert(actual.symbol == expected.symbol && actual.timeframe == expected.timeframe &&
              actual.timeBasis == expected.timeBasis && actual.asOf == expected.asOf &&
              actual.status == expected.status, "replay preserves snapshot metadata");
   TestEqual(ArraySize(actual.modules), ArraySize(expected.modules), "replay module count");
   TestEqual(ArraySize(actual.records), ArraySize(expected.records), "replay record count");
   if(ArraySize(actual.modules) == ArraySize(expected.modules))
      for(int i = 0; i < ArraySize(actual.modules); i++)
         TestAssert(actual.modules[i].concept == expected.modules[i].concept &&
                    actual.modules[i].status == expected.modules[i].status &&
                    actual.modules[i].asOf == expected.modules[i].asOf &&
                    actual.modules[i].truncated == expected.modules[i].truncated &&
                    actual.modules[i].message == expected.modules[i].message,
                    "replay preserves complete module " + IntegerToString(i));
   if(ArraySize(actual.records) == ArraySize(expected.records))
      for(int i = 0; i < ArraySize(actual.records); i++)
         TestAssert(actual.records[i].id == expected.records[i].id &&
                    actual.records[i].concept == expected.records[i].concept &&
                    actual.records[i].sourceTime == expected.records[i].sourceTime &&
                    actual.records[i].confirmedAt == expected.records[i].confirmedAt &&
                    actual.records[i].updatedAt == expected.records[i].updatedAt &&
                    actual.records[i].direction == expected.records[i].direction &&
                    actual.records[i].lower == expected.records[i].lower &&
                    actual.records[i].upper == expected.records[i].upper &&
                    actual.records[i].state == expected.records[i].state &&
                    actual.records[i].active == expected.records[i].active &&
                    actual.records[i].relatedId == expected.records[i].relatedId &&
                    actual.records[i].secondaryId == expected.records[i].secondaryId &&
                    actual.records[i].periodStart == expected.records[i].periodStart &&
                    actual.records[i].periodEnd == expected.records[i].periodEnd &&
                    actual.records[i].referencePrice == expected.records[i].referencePrice &&
                    actual.records[i].comparisonPrice == expected.records[i].comparisonPrice &&
                    actual.records[i].strength == expected.records[i].strength &&
                    actual.records[i].reason == expected.records[i].reason,
                    "replay preserves complete record " + IntegerToString(i));
  }

void EngineTestValidation()
  {
   SmcConfig config;
   EngineConfig(config);
   MqlRates rates[], empty[];
   int required = config.lookbackBars + config.WarmupBars();
   EngineRates(rates, required);
   SmcSnapshot snapshot;
   snapshot.Reset();
   TestAssert(SmcEvaluateICT(rates, empty, empty, empty, empty, config,
                            "TEST", PERIOD_M1, 0.01, 0.1, 0.01, snapshot),
              "exact required primary history succeeds with all modules disabled");
   TestEqual(snapshot.status, SMC_STATUS_READY, "all disabled is ready");
   TestEqual(ArraySize(snapshot.records), 0, "disabled modules produce no records");
   for(int concept = (int)ICT_DISPLACEMENT; concept < SMC_CONCEPT_COUNT; concept++)
      EngineModuleIs(snapshot, (ENUM_SMC_CONCEPT)concept, SMC_STATUS_DISABLED,
                     "disabled " + SmcConceptName((ENUM_SMC_CONCEPT)concept));
   TestAssert(snapshot.symbol == "TEST" && snapshot.timeframe == PERIOD_M1 &&
              snapshot.timeBasis == "broker", "snapshot retains request identity and time basis");
   TestEqual(snapshot.config.lookbackBars, config.lookbackBars, "snapshot retains effective config");

   EngineRecord(snapshot, "stale", ICT_DISPLACEMENT, rates[0].time, rates[0].time + 60);
   ArrayResize(rates, required - 1);
   TestAssert(!SmcEvaluateICT(rates, empty, empty, empty, empty, config,
                             "TEST", PERIOD_M1, 0.01, 0.1, 0.01, snapshot),
              "one missing primary dependency bar fails closed");
   TestEqual(snapshot.status, SMC_STATUS_NOT_READY, "short primary is not ready");
   TestEqual(ArraySize(snapshot.records), 0, "short primary clears stale records");

   EngineRates(rates, required);
   EngineRecord(snapshot, "stale-config", ICT_DISPLACEMENT, rates[0].time, rates[0].time + 60);
   config.lookbackBars = 0;
   TestAssert(!SmcEvaluateICT(rates, empty, empty, empty, empty, config,
                             "TEST", PERIOD_M1, 0.01, 0.1, 0.01, snapshot),
              "invalid configuration fails closed");
   TestEqual(snapshot.status, SMC_STATUS_ERROR, "invalid config is an error");
   TestEqual(ArraySize(snapshot.records), 0, "invalid config clears stale records");

   EngineConfig(config);
   rates[required - 1].high = rates[required - 1].close - 1.0;
   EngineRecord(snapshot, "stale-rates", ICT_DISPLACEMENT, rates[0].time, rates[0].time + 60);
   TestAssert(!SmcEvaluateICT(rates, empty, empty, empty, empty, config,
                             "TEST", PERIOD_M1, 0.01, 0.1, 0.01, snapshot),
              "invalid OHLC fails closed even when detectors are disabled");
   TestEqual(snapshot.status, SMC_STATUS_ERROR, "invalid primary is an error");
   TestEqual(ArraySize(snapshot.records), 0, "invalid primary clears stale records");
  }

void EngineTestOptionalInputs()
  {
   SmcConfig config;
   EngineConfig(config);
   config.enableDisplacement = true;
   config.enableCalendar = true;
   MqlRates rates[], empty[];
   EngineRates(rates, config.lookbackBars + config.WarmupBars());
   SmcSnapshot snapshot;
   snapshot.Reset();
   TestAssert(!SmcEvaluateICT(rates, empty, empty, empty, empty, config,
                             "TEST", PERIOD_M1, 0.01, 0.1, 0.01, snapshot),
              "partial calendar update does not return success");
   TestEqual(snapshot.status, SMC_STATUS_PARTIAL, "missing calendar inputs keep primary results partial");
   EngineModuleIs(snapshot, ICT_DISPLACEMENT, SMC_STATUS_READY, "primary detector remains ready");
   EngineModuleIs(snapshot, ICT_PREVIOUS_DAY_HIGH, SMC_STATUS_NOT_READY, "missing D1 is explicit");
   EngineModuleIs(snapshot, ICT_PREVIOUS_WEEK_LOW, SMC_STATUS_NOT_READY, "missing W1 is explicit");
   EngineModuleIs(snapshot, ICT_SESSION_HIGH, SMC_STATUS_NOT_READY, "missing M1 is explicit");

   config.enableCalendar = false;
   config.smtSymbol = "COMPARE";
   TestAssert(!SmcEvaluateICT(rates, empty, empty, empty, empty, config,
                             "TEST", PERIOD_M1, 0.01, 0.1, 0.01, snapshot),
              "partial SMT update does not return success");
   TestEqual(snapshot.status, SMC_STATUS_PARTIAL, "missing requested SMT comparison is partial");
   EngineModuleIs(snapshot, ICT_SMT, SMC_STATUS_NOT_READY, "configured SMT cannot silently return no signals");
   EngineModuleIs(snapshot, ICT_PREVIOUS_DAY_HIGH, SMC_STATUS_DISABLED, "disabled calendar differs from missing input");

   config.smtSymbol = "";
   config.enablePO3 = true;
   TestAssert(!SmcEvaluateICT(rates, empty, empty, empty, empty, config,
                             "TEST", PERIOD_M1, 0.01, 0.1, 0.01, snapshot),
              "partial PO3 update does not return success");
   TestEqual(snapshot.status, SMC_STATUS_PARTIAL, "PO3 without accumulation history is partial");
   EngineModuleIs(snapshot, ICT_PO3, SMC_STATUS_NOT_READY, "PO3 missing M1 is explicit");
  }

void EngineTestAggregation()
  {
   SmcSnapshot snapshot;
   snapshot.Reset();
   SmcSetModuleStatus(snapshot, ICT_DISPLACEMENT, SMC_STATUS_DISABLED);
   SmcAggregateStatus(snapshot);
   TestEqual(snapshot.status, SMC_STATUS_READY, "disabled modules do not impair aggregate availability");
   SmcSetModuleStatus(snapshot, ICT_DISPLACEMENT, SMC_STATUS_NOT_READY);
   SmcAggregateStatus(snapshot);
   TestEqual(snapshot.status, SMC_STATUS_NOT_READY, "all enabled modules not ready aggregates not ready");
   SmcSetModuleStatus(snapshot, ICT_MSS, SMC_STATUS_READY);
   SmcAggregateStatus(snapshot);
   TestEqual(snapshot.status, SMC_STATUS_PARTIAL, "ready and not ready aggregate partial");
   SmcSetModuleStatus(snapshot, ICT_DISPLACEMENT, SMC_STATUS_READY);
   SmcAggregateStatus(snapshot);
   TestEqual(snapshot.status, SMC_STATUS_READY, "all enabled modules ready aggregates ready");
   SmcSetModuleStatus(snapshot, ICT_MSS, SMC_STATUS_PARTIAL);
   SmcAggregateStatus(snapshot);
   TestEqual(snapshot.status, SMC_STATUS_PARTIAL, "module partial propagates");
   SmcSetModuleStatus(snapshot, ICT_IFVG, SMC_STATUS_ERROR);
   SmcAggregateStatus(snapshot);
   TestEqual(snapshot.status, SMC_STATUS_ERROR, "module error takes precedence over partial");
  }

void EngineTestFinalization()
  {
   SmcConfig config;
   EngineConfig(config);
   config.maxRecordsPerConcept = 2;
   MqlRates rates[];
   EngineRates(rates, config.lookbackBars + config.WarmupBars());
   int count = ArraySize(rates);
   SmcSnapshot snapshot;
   snapshot.Reset();
   snapshot.config = config;
   snapshot.asOf = rates[count - 1].time + 60;
   SmcSetModuleStatus(snapshot, ICT_DISPLACEMENT, SMC_STATUS_READY, snapshot.asOf);
   SmcSetModuleStatus(snapshot, ICT_MSS, SMC_STATUS_READY, snapshot.asOf);
   datetime first = rates[count - 3].time;
   datetime middle = rates[count - 2].time;
   datetime last = rates[count - 1].time;
   EngineRecord(snapshot, "latest", ICT_DISPLACEMENT, last, last + 60);
   EngineRecord(snapshot, "tie-b", ICT_DISPLACEMENT, middle, middle + 60);
   EngineRecord(snapshot, "oldest", ICT_DISPLACEMENT, first, first + 60);
   EngineRecord(snapshot, "tie-a", ICT_DISPLACEMENT, middle, middle + 60);
   EngineRecord(snapshot, "other-concept", ICT_MSS, middle, middle + 60);
   SmcFinalizeSnapshot(snapshot, rates);
   TestEqual(ArraySize(snapshot.records), 3, "record cap applies independently to each concept");
   TestAssert(!EngineHasRecord(snapshot, "oldest") && !EngineHasRecord(snapshot, "tie-a"),
              "cap discards oldest records and resolves matching timestamps by ID");
   if(ArraySize(snapshot.records) == 3)
     {
      TestAssert(snapshot.records[0].id == "tie-b", "sort places retained earlier displacement first");
      TestAssert(snapshot.records[1].id == "other-concept", "sort uses concept after identical timestamps");
      TestAssert(snapshot.records[2].id == "latest", "sort places latest confirmation last");
     }
   int displaced = EngineModuleIndex(snapshot, ICT_DISPLACEMENT);
   int shifted = EngineModuleIndex(snapshot, ICT_MSS);
   TestAssert(displaced >= 0 && shifted >= 0, "finalization preserves module statuses");
   if(displaced >= 0) TestAssert(snapshot.modules[displaced].truncated, "capped module is marked truncated");
   if(shifted >= 0) TestAssert(!snapshot.modules[shifted].truncated, "uncapped module remains complete");

   snapshot.Reset();
   snapshot.config = config;
   snapshot.config.maxRecordsPerConcept = 20;
   snapshot.asOf = last + 60;
   datetime outside = rates[0].time;
   EngineRecord(snapshot, "old-event", ICT_DISPLACEMENT, outside, outside + 60);
   EngineRecord(snapshot, "live-zone", ICT_IFVG, outside, outside + 60);
   EngineRecord(snapshot, "dead-zone", ICT_IFVG, outside, outside + 60, false);
   EngineRecord(snapshot, "active-reference", ICT_PREVIOUS_DAY_HIGH, outside, outside + 60);
   EngineRecord(snapshot, "late-confirmation", ICT_MSS, outside, last + 60);
   datetime cutoff = rates[count - config.lookbackBars].time;
   EngineRecord(snapshot, "boundary-event", ICT_DISPLACEMENT, cutoff, cutoff + 60);
   SmcFinalizeSnapshot(snapshot, rates);
   TestAssert(!EngineHasRecord(snapshot, "old-event"), "warmup events stay outside reporting horizon");
   TestAssert(!EngineHasRecord(snapshot, "dead-zone"), "inactive warmup zone stays outside horizon");
   TestAssert(EngineHasRecord(snapshot, "live-zone"), "live warmup zone remains available");
   TestAssert(EngineHasRecord(snapshot, "active-reference"), "active calendar reference remains available");
   TestAssert(EngineHasRecord(snapshot, "late-confirmation"), "confirmation inside horizon retains older source");
   TestAssert(EngineHasRecord(snapshot, "boundary-event"), "lookback boundary is inclusive");
  }

void EngineTestReplay()
  {
   SmcConfig config;
   EngineConfig(config);
   config.enableDisplacement = true;
   config.enableMSS = true;
   config.enableIFVG = true;
   config.enableBPR = true;
   MqlRates rates[], empty[];
   EngineRates(rates, config.lookbackBars + config.WarmupBars());
   int last = ArraySize(rates) - 1;
   rates[last].close = 102.0;
   rates[last].high = 102.1;
   SmcSnapshot first, replay;
   first.Reset();
   replay.Reset();
   TestAssert(SmcEvaluateICT(rates, empty, empty, empty, empty, config,
                            "TEST", PERIOD_M1, 0.01, 0.1, 0.01, first), "valid primary detectors evaluate");
   TestEqual(first.status, SMC_STATUS_READY, "available enabled detectors are ready");
   TestAssert(ArraySize(first.records) > 0, "determinism fixture emits a real detection");
   SmcEvaluateICT(rates, empty, empty, empty, empty, config,
                  "TEST", PERIOD_M1, 0.01, 0.1, 0.01, replay);
   EngineSnapshotsEqual(replay, first);
   SmcEvaluateICT(rates, empty, empty, empty, empty, config,
                  "TEST", PERIOD_M1, 0.01, 0.1, 0.01, replay);
   EngineSnapshotsEqual(replay, first);
  }

void OnStart()
  {
   TestBegin("ICT-engine");
   EngineTestValidation();
   EngineTestOptionalInputs();
   EngineTestAggregation();
   EngineTestFinalization();
   EngineTestReplay();
   TestFinish();
  }
