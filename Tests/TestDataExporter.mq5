#property strict
#include "TestHarness.mqh"
#include <SMC/Utils/DataExporter.mqh>

string ReadBytes(const string filename)
  {
   int handle = FileOpen(filename, FILE_READ | FILE_BIN | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return "";
   uchar bytes[];
   uint count = (uint)FileSize(handle);
   uint copied = FileReadArray(handle, bytes, 0, count);
   FileClose(handle);
   TestEqual(copied, count, "read every output byte");
   for(uint i = 0; i < count; i++)
      if(bytes[i] == 0)
        {
         TestAssert(false, "CSV is UTF-8 without UTF-16 null bytes");
         break;
        }
   return CharArrayToString(bytes, 0, count, CP_UTF8);
  }

string Timestamp(const datetime value)
  {
   string formatted = TimeToString(value, TIME_DATE | TIME_SECONDS);
   StringReplace(formatted, ".", "-");
   return formatted;
  }

void AssertCsv(const string filename, const string symbol, const MqlRates &rates[], const int mode)
  {
   double rsi[];
   if(mode == 1)
     {
      // The exporter promises MT5's indicator values, not a second RSI model.
      int handle = iRSI(symbol, PERIOD_M1, 14, PRICE_CLOSE);
      TestAssert(handle != INVALID_HANDLE, "create independent RSI oracle");
      if(handle != INVALID_HANDLE)
        {
         TestEqual(CopyBuffer(handle, 0, 1, 3, rsi), 3, "load independent RSI by position");
         IndicatorRelease(handle);
        }
     }
   string bytes = ReadBytes(filename);
   TestAssert(StringFind(bytes, "datetime,open,high,low,close,volume") == 0,
              "UTF-8 ASCII header starts at first byte");
   StringReplace(bytes, "\r", "");
   string lines[];
   TestEqual(StringSplit(bytes, '\n', lines), 5, "header, three candles, final newline");
   if(ArraySize(lines) != 5)
      return;
   string fields[];
   for(int i = 0; i < 3; i++)
     {
      int source = ArraySize(rates) - 4 + i;
      int expected = mode == 0 ? 6 : (mode == 1 ? 9 : 12);
      TestEqual(StringSplit(lines[i + 1], ',', fields), expected, "historical column count");
      if(ArraySize(fields) != expected)
         continue;
      TestAssert(fields[0] == Timestamp(rates[source].time), "chronological confirmed candle timestamp");
      TestNear(StringToDouble(fields[1]), rates[source].open, 0.00001, "exact opening price");
      TestNear(StringToDouble(fields[4]), rates[source].close, 0.00001, "exact closing price");
      TestEqual(StringToInteger(fields[5]), rates[source].tick_volume, "64-bit tick volume preserved");
      if(mode == 1)
        {
         if(ArraySize(rsi) == 3)
            TestNear(StringToDouble(fields[6]), rsi[i], 0.0051, "RSI matches the same MT5 candle");
         TestAssert(StringToDouble(fields[7]) > 0.0, "ATR is available after warmup");
         TestNear(StringToDouble(fields[8]), rates[source].close - 9.5, 0.00001,
                  "SMA aligned to the same candle");
        }
      if(mode == 2)
        {
         double ret = i == 0 ? 0 : (rates[source].close - rates[source - 1].close) / rates[source - 1].close;
         TestNear(StringToDouble(fields[6]), ret, 0.00000051, "return uses prior chronological close");
         double range = rates[source].high - rates[source].low;
         double average = 0;
         for(int previous = 0; previous <= i; previous++)
           {
            int index = ArraySize(rates) - 4 + previous;
            average += rates[index].high - rates[index].low;
           }
         average /= i + 1;
         TestNear(StringToDouble(fields[7]), 0.5 / range, 0.000051, "body-to-range ratio");
         TestNear(StringToDouble(fields[10]), average, 0.00001, "rolling range has no future bars");
         TestNear(StringToDouble(fields[11]), range / average, 0.000051, "range ratio uses available history");
        }
     }
  }

void OnStart()
  {
   TestBegin("DataExporter");
   string identity = SMC_TestRunId;
   if(identity == "")
      identity = IntegerToString((long)GetMicrosecondCount());
   string symbol = "SMC" + StringSubstr(identity, 0, 20);
   string folder = "smc-export-tests-" + identity;
   string ohlcv = folder + "\\ohlcv.csv";
   string features = folder + "\\features.csv";
   string indicators = folder + "\\indicators.csv";
   string missing = folder + "\\unavailable.csv";
   bool created = CustomSymbolCreate(symbol, "SMCTests", "EURUSD");
   TestAssert(created, "create isolated custom symbol");
   if(!created)
     {
      TestFinish();
      return;
     }
   TestAssert(CustomSymbolSetInteger(symbol, SYMBOL_DIGITS, 5), "set fixture precision");
   TestAssert(SymbolSelect(symbol, true), "select fixture symbol");
   MqlRates rates[];
   ArrayResize(rates, 40);
   for(int i = 0; i < ArraySize(rates); i++)
     {
      ZeroMemory(rates[i]);
      rates[i].time = D'2026.01.05 00:00:00' + i * 60;
      rates[i].open = 100 + i;
      rates[i].high = 101 + i + (i % 3);
      rates[i].low = 99 + i;
      rates[i].close = 100.5 + i;
      rates[i].tick_volume = 3000000000 + i;
     }
   TestEqual(CustomRatesUpdate(symbol, rates), 40, "import deterministic M1 history");
   TestAssert(!CSmcDataExporter::ExportOHLCV(symbol, PERIOD_M1, 100, missing),
              "incomplete first export fails");
   TestAssert(!FileIsExist(missing, FILE_COMMON), "failed first export creates no partial CSV");
   bool written = CSmcDataExporter::ExportOHLCV(symbol, PERIOD_M1, 3, ohlcv);
   TestAssert(written, "export confirmed OHLCV bars");
   if(written)
     {
      AssertCsv(ohlcv, symbol, rates, 0);
      string original = ReadBytes(ohlcv);
      TestAssert(!CSmcDataExporter::ExportOHLCV(symbol, PERIOD_M1, 100, ohlcv), "reject incomplete history");
      TestAssert(ReadBytes(ohlcv) == original, "history failure preserves previous output");
      TestAssert(!CSmcDataExporter::ExportOHLCV(symbol, PERIOD_M1, 0, ohlcv), "reject empty request");
      TestAssert(ReadBytes(ohlcv) == original, "argument failure preserves previous output");
      TestAssert(!CSmcDataExporter::ExportWithIndicators(symbol, PERIOD_M1, 38, ohlcv),
                 "reject finite indicator warmup placeholders");
      TestAssert(ReadBytes(ohlcv) == original, "indicator failure preserves previous output");

      int exclusive = FileOpen(ohlcv, FILE_READ | FILE_BIN | FILE_COMMON);
      TestAssert(exclusive != INVALID_HANDLE, "lock existing destination without sharing");
      if(exclusive != INVALID_HANDLE)
        {
         TestAssert(!CSmcDataExporter::ExportOHLCV(symbol, PERIOD_M1, 2, ohlcv),
                    "failed replacement reports failure");
         FileClose(exclusive);
         TestAssert(ReadBytes(ohlcv) == original, "failed replacement preserves previous output");
        }
      string residue;
      long search = FileFindFirst(ohlcv + ".*.tmp", residue, FILE_COMMON);
      TestAssert(search == INVALID_HANDLE, "failed replacement removes temporary file");
      if(search != INVALID_HANDLE)
         FileFindClose(search);
     }
   written = CSmcDataExporter::ExportSmcFeatures(symbol, PERIOD_M1, 3, features);
   TestAssert(written, "export deterministic candle features");
   if(written)
      AssertCsv(features, symbol, rates, 2);
   written = CSmcDataExporter::ExportWithIndicators(symbol, PERIOD_M1, 3, indicators);
   TestAssert(written, "export indicators with sufficient history");
   if(written)
      AssertCsv(indicators, symbol, rates, 1);
   FileDelete(ohlcv, FILE_COMMON);
   FileDelete(features, FILE_COMMON);
   FileDelete(indicators, FILE_COMMON);
   FileDelete(missing, FILE_COMMON);
   FolderDelete(folder, FILE_COMMON);
   TestAssert(SymbolSelect(symbol, false), "deselect fixture symbol");
   TestAssert(CustomSymbolDelete(symbol), "delete fixture symbol");
   TestFinish();
  }
