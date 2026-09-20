#property strict
#include "TestHarness.mqh"
#include <SMC/Core/SmcSnapshot.mqh>

void TestCloseTimes()
  {
   TestEqual(SmcBarClosedAt(D'2026.02.01 00:00', PERIOD_MN1),
             D'2026.03.01 00:00', "February closes at March boundary");
   TestEqual(SmcBarClosedAt(D'2024.02.01 00:00', PERIOD_MN1),
             D'2024.03.01 00:00', "leap February closes at March boundary");
   TestEqual(SmcBarClosedAt(D'2026.01.01 00:00', PERIOD_MN1),
             D'2026.02.01 00:00', "31-day month closes at next boundary");
   TestEqual(SmcBarClosedAt(D'2026.04.01 00:00', PERIOD_MN1),
             D'2026.05.01 00:00', "30-day month closes at next boundary");
   TestEqual(SmcBarClosedAt(D'2026.12.01 00:00', PERIOD_MN1),
             D'2027.01.01 00:00', "December advances year");
   TestEqual(SmcBarClosedAt(D'2026.09.18 12:55', PERIOD_M5),
             D'2026.09.18 13:00', "intraday closing timestamp");
   TestEqual(SmcBarClosedAt(D'2026.09.18 00:00', PERIOD_D1),
             D'2026.09.19 00:00', "daily closing timestamp");
   TestEqual(SmcBarClosedAt(D'2026.09.14 00:00', PERIOD_W1),
             D'2026.09.21 00:00', "weekly closing timestamp");
   TestEqual(SmcBarClosedAt(0, PERIOD_MN1), 0, "missing time remains missing");
  }

void TestConfigContract()
  {
   SmcConfig config;
   config.SetDefaults();
   string error;
   TestAssert(config.Validate(error), "defaults validate");
   TestEqual(config.WarmupBars(), 533, "default history includes bounded previous pivot");
   config.lookbackBars = 10;
   TestEqual(config.WarmupBars(), 504, "short lookback retains full zone ancestry");
   config.maxZoneAge = 1000;
   TestEqual(config.WarmupBars(), 2104, "IFVG ancestry includes original and derived lifetimes");
   config.Init();
   config.lookbackBars = 2000;
   TestEqual(config.WarmupBars(), 2033, "long lookback extends prior pivot horizon");
   config.Init();
   TestAssert(!config.IsSMTEnabled(), "SMT disabled without symbol");
   config.smtSymbol = "GBPUSD";
   TestAssert(config.IsSMTEnabled(), "comparison symbol enables SMT");
   config.Init();
   config.enableSMT = true;
   TestAssert(!config.Validate(error), "explicit SMT requires symbol");
   config.Init();
   config.sessions[1].name = config.sessions[0].name;
   TestAssert(!config.Validate(error), "duplicate session name rejected");
   config.Init();
   config.sessions[0].startMinute = 1320;
   config.sessions[0].endMinute = 120;
   TestAssert(config.Validate(error), "overnight session accepted");
   config.sessions[0].endMinute = 1320;
   TestAssert(!config.Validate(error), "zero-duration session rejected");
   config.Init();
   config.displacementBodyFraction = 1.1;
   TestAssert(!config.Validate(error), "body fraction above one rejected");
  }

void TestSnapshotContract()
  {
   SmcSnapshot snapshot;
   snapshot.Reset();
   TestAssert(snapshot.message == "", "diagnostic defaults empty");
   snapshot.message = "VIX unavailable";
   snapshot.Reset();
   TestAssert(snapshot.message == "", "reset clears diagnostics");
   TestEqual(snapshot.status, SMC_STATUS_NOT_READY, "reset clears readiness");
   SmcRecord record;
   record.Init();
   record.id = SmcRecordId(ICT_FVG, "EURUSD", PERIOD_M5, D'2026.09.18 12:00', 1);
   record.concept = ICT_FVG;
   record.direction = 1;
   record.lower = 1.10;
   record.upper = 1.11;
   TestAssert(SmcAppendRecord(snapshot, record), "valid record inserted");
   record.state = "TESTED";
   TestAssert(SmcAppendRecord(snapshot, record), "same identity updates record");
   TestEqual(ArraySize(snapshot.records), 1, "upsert retains unique identity");
   TestAssert(snapshot.records[0].state == "TESTED", "upsert stores latest lifecycle");
   record.lower = 1.12;
   TestAssert(!SmcAppendRecord(snapshot, record), "reversed bounds rejected");
   TestAssert(SmcSetModuleStatus(snapshot, ICT_FVG, SMC_STATUS_READY), "module inserted");
   TestAssert(SmcSetModuleStatus(snapshot, ICT_FVG, SMC_STATUS_PARTIAL, 0, true, "capped"), "module updated");
   TestEqual(ArraySize(snapshot.modules), 1, "module identity unique");
   TestAssert(snapshot.modules[0].truncated && snapshot.modules[0].message == "capped", "module metadata updated");
  }

void OnStart()
  {
   TestBegin("snapshot-contract");
   TestCloseTimes();
   TestConfigContract();
   TestSnapshotContract();
   TestFinish();
  }
