#property strict
#include "TestHarness.mqh"
#include <SMC/Utils/SnapshotExporter.mqh>

void BuildExportFixture(SmcSnapshot &snapshot)
  {
   snapshot.Reset();
   snapshot.symbol = "EURUSD";
   snapshot.timeframe = PERIOD_M15;
   snapshot.asOf = D'2026.09.18 12:00:00';
   snapshot.status = SMC_STATUS_READY;
   snapshot.message = "diagnostic\nmessage";
   for(int i = 0; i < SMC_CONCEPT_COUNT; i++)
      SmcSetModuleStatus(snapshot, (ENUM_SMC_CONCEPT)i, SMC_STATUS_READY, snapshot.asOf);
   for(int i = 0; i < SMC_CONCEPT_COUNT; i++)
     {
      SmcRecord record;
      record.Init();
      record.concept = (ENUM_SMC_CONCEPT)i;
      record.id = SmcRecordId(record.concept, snapshot.symbol, snapshot.timeframe, snapshot.asOf, 1);
      record.sourceTime = snapshot.asOf;
      record.confirmedAt = snapshot.asOf;
      record.updatedAt = snapshot.asOf;
      record.direction = i % 3 - 1;
      record.lower = 1.12345678912345;
      record.upper = 1.13;
      record.relatedId = "parent\"one";
      record.secondaryId = "parent\\two";
      record.referencePrice = 1.1;
      record.comparisonPrice = 1.2;
      record.strength = 0.75;
      record.reason = "quote\" slash\\ line\n tab\t return\r " + ShortToString(1) + " 日本語";
      SmcAppendRecord(snapshot, record);
     }
  }

string ReadCommon(const string filename)
  {
   int handle = FileOpen(filename, FILE_READ | FILE_BIN | FILE_COMMON);
   if(handle == INVALID_HANDLE) return "";
   uchar bytes[];
   int count = (int)FileSize(handle);
   ArrayResize(bytes, count);
   FileReadArray(handle, bytes, 0, count);
   FileClose(handle);
   return CharArrayToString(bytes, 0, count, CP_UTF8);
  }

bool CopyCommonFixture(const string source, const string target)
  {
   int sourceHandle = FileOpen(source, FILE_READ | FILE_BIN | FILE_COMMON);
   if(sourceHandle == INVALID_HANDLE) return false;
   int count = (int)FileSize(sourceHandle);
   uchar bytes[];
   ArrayResize(bytes, count);
   uint read = FileReadArray(sourceHandle, bytes, 0, count);
   FileClose(sourceHandle);
   if(read != (uint)count) return false;
   int output = FileOpen(target, FILE_WRITE | FILE_BIN);
   if(output == INVALID_HANDLE) return false;
   uint written = FileWriteArray(output, bytes, 0, count);
   FileFlush(output);
   FileClose(output);
   return written == (uint)count;
  }

void AssertExactUTF8(const string filename, const string expected)
  {
   int handle = FileOpen(filename, FILE_READ | FILE_BIN | FILE_COMMON);
   TestAssert(handle != INVALID_HANDLE, "UTF8 byte inspection opens file");
   if(handle == INVALID_HANDLE) return;
   uchar actual[], wanted[];
   int size = (int)FileSize(handle);
   ArrayResize(actual, size);
   uint copied = FileReadArray(handle, actual, 0, size);
   FileClose(handle);
   int count = StringToCharArray(expected, wanted, 0, WHOLE_ARRAY, CP_UTF8) - 1;
   TestAssert(copied == (uint)size && size == count, "file size equals UTF8 payload without terminator");
   bool equal = size == count;
   for(int i = 0; equal && i < size; i++) equal = actual[i] == wanted[i];
   TestAssert(equal, "every exported byte matches UTF8 encoding");
   TestAssert(size > 0 && actual[0] == '{', "no BOM before JSON object");
   bool hasNul = false;
   for(int i = 0; i < size; i++) if(actual[i] == 0) hasNul = true;
   TestAssert(!hasNul, "no embedded or trailing NUL bytes");
  }

void OnStart()
  {
   TestBegin("snapshot_export");
   SmcSnapshot snapshot;
   BuildExportFixture(snapshot);
   string json;
   TestAssert(CSmcSnapshotExporter::Serialize(snapshot, json), "complete snapshot serializes");
   TestAssert(StringFind(json, "\"schema_version\":\"1.0\"") >= 0, "schema version");
   TestAssert(StringFind(json, "\"as_of\":\"2026-09-18T12:00:00\"") >= 0, "broker ISO time without Z");
   TestAssert(StringFind(json, "\\u0001") >= 0, "control character escaped");
   TestAssert(StringFind(json, "quote\\\" slash\\\\ line\\u000a tab\\u0009 return\\u000d") >= 0,
              "quotes backslashes and whitespace escaped");
   TestAssert(StringFind(json, "日本語") >= 0, "Unicode preserved");
   TestAssert(StringFind(json, "\"message\":\"diagnostic\\u000amessage\"") >= 0, "snapshot diagnostic escaped");
   TestAssert(StringFind(json, "\"related_ids\":[\"parent\\\"one\",\"parent\\\\two\"]") >= 0, "both related IDs");
   for(int i = 0; i < SMC_CONCEPT_COUNT; i++)
      TestAssert(StringFind(json, "\"concept\":\"" + SmcConceptName((ENUM_SMC_CONCEPT)i) + "\"") >= 0,
                 "concept name " + IntegerToString(i));

   string filename = "SMC_Tests\\snapshot-" + SMC_TestRunId + ".json";
   TestAssert(CSmcSnapshotExporter::Export(snapshot, filename), "UTF8 file exported");
   TestAssert(ReadCommon(filename) == json, "file bytes decode to exact serialization");
   AssertExactUTF8(filename, json);
   string original = ReadCommon(filename);
   snapshot.records[0].lower = snapshot.records[0].upper + 1;
   json = "previous content";
   TestAssert(!CSmcSnapshotExporter::Serialize(snapshot, json) && json == "", "invalid bounds fail without JSON fragment");
   TestAssert(!CSmcSnapshotExporter::Export(snapshot, filename), "invalid export fails");
   TestAssert(ReadCommon(filename) == original, "invalid export preserves previous file");
   BuildExportFixture(snapshot);
   snapshot.records[0].strength = MathArcsin(2.0);
   TestAssert(!CSmcSnapshotExporter::Serialize(snapshot, json), "NaN rejected");
   BuildExportFixture(snapshot);
   snapshot.records[0].sourceTime = 0;
   TestAssert(!CSmcSnapshotExporter::Serialize(snapshot, json), "record time required");
   BuildExportFixture(snapshot);
   snapshot.records[0].direction = 2;
   TestAssert(!CSmcSnapshotExporter::Serialize(snapshot, json), "invalid direction rejected");
   BuildExportFixture(snapshot);
   snapshot.modules[0].concept = (ENUM_SMC_CONCEPT)99;
   TestAssert(!CSmcSnapshotExporter::Serialize(snapshot, json), "invalid concept rejected");
   BuildExportFixture(snapshot);
   snapshot.config.displacementMultiplier = MathArcsin(2.0);
   TestAssert(!CSmcSnapshotExporter::Serialize(snapshot, json), "nonfinite config rejected");
   BuildExportFixture(snapshot);
   snapshot.config.sessions[0].endMinute = 1440;
   TestAssert(!CSmcSnapshotExporter::Serialize(snapshot, json), "invalid session minute rejected");
   TestAssert(!CSmcSnapshotExporter::SafePath("../escape.json"), "parent path rejected");
   TestAssert(!CSmcSnapshotExporter::SafePath("C:\\escape.json"), "absolute path rejected");
   TestAssert(!CSmcSnapshotExporter::SafePath("folder\\..\\escape.json"), "nested parent rejected");

   // A reader that denies write sharing forces replacement failure.
   BuildExportFixture(snapshot);
   int locked = FileOpen(filename, FILE_READ | FILE_BIN | FILE_COMMON);
   TestAssert(locked != INVALID_HANDLE, "lock existing export");
   if(locked != INVALID_HANDLE)
     {
      snapshot.symbol = "GBPUSD";
      TestAssert(!CSmcSnapshotExporter::Export(snapshot, filename), "locked replacement fails");
      FileClose(locked);
      TestAssert(ReadCommon(filename) == original, "failed replacement preserves previous file");
     }

   snapshot.Reset();
   snapshot.symbol = "EURUSD";
   snapshot.timeframe = PERIOD_M15;
   SmcSetModuleStatus(snapshot, ICT_SMT, SMC_STATUS_DISABLED);
   TestAssert(CSmcSnapshotExporter::Serialize(snapshot, json), "empty unavailable snapshot serializes");
   TestAssert(StringFind(json, "\"as_of\":null") >= 0, "unavailable time is null");
   TestAssert(StringFind(json, "\"records\":[]") >= 0, "unavailable records empty");
   TestAssert(StringFind(json, "\"status\":\"DISABLED\"") >= 0, "disabled module explicit");
   TestAssert(CSmcSnapshotExporter::Export(snapshot, filename), "complete replacement succeeds");
   TestAssert(ReadCommon(filename) == json, "replacement content exact");
   FileDelete(filename, FILE_COMMON);

   // The runtime runner requires and validates these exact freshly exported bytes.
   BuildExportFixture(snapshot);
   string fixture = "SMC_Tests\\snapshot-fixture-" + SMC_TestRunId + ".json";
   TestAssert(CSmcSnapshotExporter::Export(snapshot, fixture), "runtime schema fixture exported");
   TestAssert(CopyCommonFixture(fixture, "snapshot-fixture.json"), "runtime schema fixture bytecopy staged");
   FileDelete(fixture, FILE_COMMON);
   TestFinish();
  }
