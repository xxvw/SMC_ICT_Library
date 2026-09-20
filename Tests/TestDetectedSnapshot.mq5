#property strict
#include "TestHarness.mqh"
#include <SMC/Core/IctEngine.mqh>
#include <SMC/Utils/SnapshotExporter.mqh>

void DetectedSnapshotBar(MqlRates &bar, const int index)
  {
   ZeroMemory(bar);
   bar.time = D'2026.01.05 00:00' + index * 60;
   bar.open = 100.0;
   bar.high = 103.0;
   bar.low = 99.0;
   bar.close = 102.0;
   bar.tick_volume = 100 + index;
  }

int DetectedSnapshotRecord(const SmcSnapshot &snapshot, const string id)
  {
   for(int i = 0; i < ArraySize(snapshot.records); i++)
      if(snapshot.records[i].id == id) return i;
   return -1;
  }

bool DetectedSnapshotRecordEqual(const SmcRecord &actual, const SmcRecord &expected)
  {
   return actual.id == expected.id && actual.concept == expected.concept &&
          actual.sourceTime == expected.sourceTime && actual.confirmedAt == expected.confirmedAt &&
          actual.updatedAt == expected.updatedAt && actual.direction == expected.direction &&
          actual.lower == expected.lower && actual.upper == expected.upper &&
          actual.state == expected.state && actual.active == expected.active &&
          actual.relatedId == expected.relatedId && actual.secondaryId == expected.secondaryId &&
          actual.periodStart == expected.periodStart && actual.periodEnd == expected.periodEnd &&
          actual.referencePrice == expected.referencePrice && actual.comparisonPrice == expected.comparisonPrice &&
          actual.strength == expected.strength && actual.reason == expected.reason;
  }

// Preserve the exporter's actual FILE_COMMON bytes in this isolated terminal's
// sandbox for the host runner's schema validation and six-language readers.
bool SaveDetectedSnapshotFixture(const string commonFile, const string expected)
  {
   int source = FileOpen(commonFile, FILE_READ | FILE_BIN | FILE_COMMON);
   if(source == INVALID_HANDLE) return false;
   int size = (int)FileSize(source);
   uchar bytes[];
   ArrayResize(bytes, size);
   uint read = FileReadArray(source, bytes, 0, size);
   FileClose(source);
   if(size <= 0 || read != (uint)size ||
      CharArrayToString(bytes, 0, size, CP_UTF8) != expected) return false;
   int output = FileOpen("snapshot-fixture.json", FILE_WRITE | FILE_BIN);
   if(output == INVALID_HANDLE) return false;
   uint written = FileWriteArray(output, bytes, 0, size);
   FileFlush(output);
   FileClose(output);
   return written == (uint)size;
  }

void OnStart()
  {
   // The shared runner requires fresh snapshot-fixture.json for this suite.
   // The manifest also records this distinct source filename.
   TestBegin("snapshot_export");
   SmcConfig config;
   config.SetDefaults();
   config.lookbackBars = 32;
   config.enableCalendar = false;
   config.enableSMT = false;
   config.enablePO3 = false;
   config.enableMSS = false;
   config.enableIFVG = false;
   config.enableBPR = false;

   int required = config.lookbackBars + config.WarmupBars();
   MqlRates rates[], prefix[], empty[];
   ArrayResize(rates, required + 1);
   ArraySetAsSeries(rates, false);
   for(int i = 0; i < ArraySize(rates); i++) DetectedSnapshotBar(rates[i], i);
   // Exactly the standard inclusive thresholds: body 3 >= mean 2 * 1.5,
   // and body / range = 3 / 5 = 60 percent.
   rates[required].close = 103.0;
   rates[required].high = 104.0;
   ArrayCopy(prefix, rates, 0, 0, required);
   ArraySetAsSeries(prefix, false);

   SmcSnapshot before, detected, repeated, extended;
   TestAssert(SmcEvaluateICT(prefix, empty, empty, empty, empty, config,
                            "SYNTHETIC", PERIOD_M1, 0.01, 0.1, 0.01, before),
              "complete quiet prefix evaluates without broker input");
   TestEqual(ArraySize(before.records), 0, "future displacement absent from prior closed-bar snapshot");

   TestAssert(SmcEvaluateICT(rates, empty, empty, empty, empty, config,
                            "SYNTHETIC", PERIOD_M1, 0.01, 0.1, 0.01, detected),
              "pure ICT engine detects supplied closed bars");
   TestEqual(detected.status, SMC_STATUS_READY, "detected snapshot is ready");
   TestEqual(detected.asOf, rates[required].time + 60, "as-of is candidate close in broker time");
   TestEqual(ArraySize(detected.records), 1, "one real displacement is produced");
   if(ArraySize(detected.records) == 1)
     {
      TestEqual(detected.records[0].concept, ICT_DISPLACEMENT, "record came from displacement detector");
      TestEqual(detected.records[0].direction, 1, "real detection is bullish");
      TestEqual(detected.records[0].sourceTime, rates[required].time, "detector retains source bar");
      TestEqual(detected.records[0].confirmedAt, detected.asOf, "detection confirmed only after candle closes");
      TestNear(detected.records[0].lower, 100.0, 0.000001, "detected body lower bound");
      TestNear(detected.records[0].upper, 103.0, 0.000001, "detected body upper bound");
     }

   string originalJSON, repeatedJSON;
   TestAssert(CSmcSnapshotExporter::Serialize(detected, originalJSON), "real detected snapshot serializes");
   TestAssert(SmcEvaluateICT(rates, empty, empty, empty, empty, config,
                            "SYNTHETIC", PERIOD_M1, 0.01, 0.1, 0.01, repeated),
              "identical history reevaluates successfully");
   TestAssert(CSmcSnapshotExporter::Serialize(repeated, repeatedJSON), "repeated evaluation serializes");
   TestAssert(originalJSON == repeatedJSON, "same history and configuration yield identical JSON");

   int previousCount = ArraySize(rates);
   ArrayResize(rates, previousCount + 5);
   for(int i = previousCount; i < ArraySize(rates); i++) DetectedSnapshotBar(rates[i], i);
   int last = ArraySize(rates) - 1;
   rates[last].open = 102.0;
   rates[last].close = 96.0;
   rates[last].high = 103.0;
   rates[last].low = 95.0;
   TestAssert(SmcEvaluateICT(rates, empty, empty, empty, empty, config,
                            "SYNTHETIC", PERIOD_M1, 0.01, 0.1, 0.01, extended),
              "future closed bars evaluate without mutating past detections");
   TestEqual(ArraySize(extended.records), 2, "later bearish displacement joins original bullish detection");
   if(ArraySize(detected.records) == 1)
     {
      int retained = DetectedSnapshotRecord(extended, detected.records[0].id);
      TestAssert(retained >= 0, "original stable ID survives appended future bars");
      if(retained >= 0)
         TestAssert(DetectedSnapshotRecordEqual(extended.records[retained], detected.records[0]),
                    "future bars preserve every original record field");
     }
   if(ArraySize(extended.records) == 2)
     {
      TestEqual(extended.records[1].direction, -1, "new detection is bearish");
      TestEqual(extended.records[1].sourceTime, rates[last].time, "new detection uses only new source bar");
      TestEqual(extended.records[1].confirmedAt, rates[last].time + 60, "new detection confirms at its own close");
     }

   string exportedJSON;
   TestAssert(CSmcSnapshotExporter::Serialize(extended, exportedJSON), "detector output remains exportable");
   string suffix = SMC_TestRunId != "" ? SMC_TestRunId : IntegerToString((long)GetMicrosecondCount());
   string filename = "SMC_Tests\\detected-snapshot-" + suffix + ".json";
   TestAssert(CSmcSnapshotExporter::Export(extended, filename), "actual detector output exported through FILE_COMMON");
   TestAssert(SaveDetectedSnapshotFixture(filename, exportedJSON),
              "exact emitted bytes staged for host schema and six-language validation");
   TestAssert(FileDelete(filename, FILE_COMMON), "test removes only its own common export");
   TestFinish();
  }
