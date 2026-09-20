//+------------------------------------------------------------------+
//| DataExporter.mqh - confirmed-bar CSV export                       |
//| Copyright 2025-2026, SMC_ICT_Library                              |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_DATA_EXPORTER_MQH__
#define __SMC_DATA_EXPORTER_MQH__

// All public entry points retain their historical signatures and CSV
// columns. Rows are UTF-8, oldest first, and exclude the unfinished bar.
class CSmcDataExporter
  {
private:
   static string FormatDatetime(const datetime value)
     {
      MqlDateTime parts;
      TimeToStruct(value, parts);
      return StringFormat("%04d-%02d-%02d %02d:%02d:%02d",
                          parts.year, parts.mon, parts.day,
                          parts.hour, parts.min, parts.sec);
     }

   static bool WriteCSVRow(const int handle, const string &values[])
     {
      string row = "";
      for(int i = 0; i < ArraySize(values); i++)
        {
         if(i > 0)
            row += ",";
         row += values[i];
        }
      row += "\r\n";
      // Headers and formatted numbers are ASCII, hence bytes == characters.
      return FileWriteString(handle, row) == (uint)StringLen(row);
     }

   static bool LoadRates(const string symbol, const ENUM_TIMEFRAMES tf,
                         const int bars, MqlRates &rates[])
     {
      if(bars <= 0)
         return false;
      ArraySetAsSeries(rates, false);
      if(CopyRates(symbol, tf, 1, bars, rates) != bars)
         return false;
      for(int i = 0; i < bars; i++)
        {
         if(rates[i].time <= 0 || (i > 0 && rates[i].time <= rates[i - 1].time) ||
            !MathIsValidNumber(rates[i].open) || !MathIsValidNumber(rates[i].high) ||
            !MathIsValidNumber(rates[i].low) || !MathIsValidNumber(rates[i].close) ||
            rates[i].high < MathMax(rates[i].open, rates[i].close) ||
            rates[i].low > MathMin(rates[i].open, rates[i].close) ||
            rates[i].tick_volume < 0)
            return false;
        }
      return true;
     }

   static bool CopyIndicator(const int handle, const MqlRates &rates[],
                             double &values[])
     {
      int count = ArraySize(rates);
      ArraySetAsSeries(values, false);
      // Time bounds keep indicators aligned if a new candle opens mid-export.
      if(handle == INVALID_HANDLE ||
         CopyBuffer(handle, 0, rates[0].time, rates[count - 1].time, values) != count)
         return false;
      for(int i = 0; i < count; i++)
         if(values[i] == EMPTY_VALUE || !MathIsValidNumber(values[i]))
            return false;
      return true;
     }

   static bool LoadIndicators(const string symbol, const ENUM_TIMEFRAMES tf,
                              const MqlRates &rates[], double &rsi[],
                              double &atr[], double &ma[])
     {
      // SMA(20) needs nineteen predecessors for the first exported candle.
      // Built-in indicators may return finite zero warmup values otherwise.
      MqlRates warmup[];
      if(CopyRates(symbol, tf, rates[0].time, 20, warmup) != 20)
         return false;
      int handles[3];
      handles[0] = iRSI(symbol, tf, 14, PRICE_CLOSE);
      handles[1] = iATR(symbol, tf, 14);
      handles[2] = iMA(symbol, tf, 20, 0, MODE_SMA, PRICE_CLOSE);
      bool ready = CopyIndicator(handles[0], rates, rsi) &&
                   CopyIndicator(handles[1], rates, atr) &&
                   CopyIndicator(handles[2], rates, ma);
      // Release every successfully created handle even on partial creation.
      for(int i = 0; i < 3; i++)
         if(handles[i] != INVALID_HANDLE)
            IndicatorRelease(handles[i]);
      return ready;
     }

   static double AverageRange(const MqlRates &rates[], const int index,
                               const int window)
     {
      int count = MathMin(window, index + 1);
      double sum = 0.0;
      for(int j = index - count + 1; j <= index; j++)
         sum += rates[j].high - rates[j].low;
      return sum / count;
     }

   // mode: 0 = OHLCV, 1 = indicators, 2 = candle features.
   static bool Export(const string symbol, const ENUM_TIMEFRAMES tf,
                       const int bars, const string filename, const int mode)
     {
      if(filename == "")
         return false;
      MqlRates rates[];
      if(!LoadRates(symbol, tf, bars, rates))
         return false;
      double rsi[], atr[], ma[];
      if(mode == 1 && !LoadIndicators(symbol, tf, rates, rsi, atr, ma))
         return false;

      string headers[];
      string header = "datetime,open,high,low,close,volume";
      if(mode == 1)
         header += ",rsi,atr,ma20";
      else if(mode == 2)
         header += ",return,body_ratio,wick_upper_ratio,wick_lower_ratio,volatility,range_ratio";
      StringSplit(header, ',', headers);

      string temporary = filename + "." + IntegerToString(ChartID()) + "." +
                         IntegerToString((long)GetMicrosecondCount()) + ".tmp";
      int handle = FileOpen(temporary, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON,
                            0, CP_UTF8);
      if(handle == INVALID_HANDLE)
         return false;
      bool success = WriteCSVRow(handle, headers);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      string values[];
      ArrayResize(values, ArraySize(headers));
      for(int i = 0; success && i < bars; i++)
        {
         values[0] = FormatDatetime(rates[i].time);
         values[1] = DoubleToString(rates[i].open, digits);
         values[2] = DoubleToString(rates[i].high, digits);
         values[3] = DoubleToString(rates[i].low, digits);
         values[4] = DoubleToString(rates[i].close, digits);
         values[5] = IntegerToString(rates[i].tick_volume);
         if(mode == 1)
           {
            values[6] = DoubleToString(rsi[i], 2);
            values[7] = DoubleToString(atr[i], digits);
            values[8] = DoubleToString(ma[i], digits);
           }
         else if(mode == 2)
           {
            double range = rates[i].high - rates[i].low;
            double ret = 0.0;
            if(i > 0 && rates[i - 1].close != 0.0)
               ret = (rates[i].close - rates[i - 1].close) / rates[i - 1].close;
            double body = MathAbs(rates[i].close - rates[i].open);
            double upper = rates[i].high - MathMax(rates[i].open, rates[i].close);
            double lower = MathMin(rates[i].open, rates[i].close) - rates[i].low;
            double average = AverageRange(rates, i, 20);
            values[6] = DoubleToString(ret, 6);
            values[7] = DoubleToString(range > 0.0 ? body / range : 0.0, 4);
            values[8] = DoubleToString(range > 0.0 ? upper / range : 0.0, 4);
            values[9] = DoubleToString(range > 0.0 ? lower / range : 0.0, 4);
            // Rolling windows include this candle and available prior candles.
            values[10] = DoubleToString(AverageRange(rates, i, 14), digits);
            values[11] = DoubleToString(average > 0.0 ? range / average : 1.0, 4);
           }
         success = WriteCSVRow(handle, values);
        }
      ResetLastError();
      FileFlush(handle);
      if(GetLastError() != 0)
         success = false;
      ResetLastError();
      FileClose(handle);
      if(GetLastError() != 0)
         success = false;
      if(success)
         success = FileMove(temporary, FILE_COMMON, filename, FILE_COMMON | FILE_REWRITE);
      if(!success)
         FileDelete(temporary, FILE_COMMON);
      return success;
     }

public:
   static bool ExportOHLCV(const string symbol, const ENUM_TIMEFRAMES tf,
                           const int bars, const string filename)
     {
      return Export(symbol, tf, bars, filename, 0);
     }

   static bool ExportWithIndicators(const string symbol, const ENUM_TIMEFRAMES tf,
                                    const int bars, const string filename)
     {
      return Export(symbol, tf, bars, filename, 1);
     }

   static bool ExportSmcFeatures(const string symbol, const ENUM_TIMEFRAMES tf,
                                 const int bars, const string filename)
     {
      return Export(symbol, tf, bars, filename, 2);
     }

   static bool ExportMultiSymbol(string &symbols[], const ENUM_TIMEFRAMES tf,
                                 const int bars, const string folder)
     {
      if(ArraySize(symbols) == 0)
         return false;
      bool success = true;
      for(int i = 0; i < ArraySize(symbols); i++)
        {
         string filename = folder + "\\" + symbols[i] + "_" +
                           IntegerToString(tf) + "_OHLCV.csv";
         if(!ExportOHLCV(symbols[i], tf, bars, filename))
           {
            success = false;
            Print("Failed to export: ", symbols[i]);
           }
        }
      return success;
     }
  };

#endif // __SMC_DATA_EXPORTER_MQH__
