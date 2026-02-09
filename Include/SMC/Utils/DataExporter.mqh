//+------------------------------------------------------------------+
//|                                                DataExporter.mqh  |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_DATA_EXPORTER_MQH__
#define __SMC_DATA_EXPORTER_MQH__

#include "../Core/SmcTypes.mqh"

//+------------------------------------------------------------------+
//| CSmcDataExporter - Data export utility class                     |
//|                                                                    |
//| Export market data to CSV format:                                 |
//|   - OHLCV data                                                    |
//|   - OHLCV + Indicators (RSI, ATR, MA)                             |
//|   - SMC-specific features for ML training                        |
//|   - Multi-symbol batch export                                     |
//+------------------------------------------------------------------+
class CSmcDataExporter
  {
private:
   //+------------------------------------------------------------------+
   //| Write CSV header / CSVヘッダーを書き込み                         |
   //+------------------------------------------------------------------+
   static void WriteCSVHeader(int handle, const string &headers[])
     {
      string headerLine = "";
      int count = ArraySize(headers);
      for(int i = 0; i < count; i++)
        {
         if(i > 0)
            headerLine += ",";
         headerLine += headers[i];
        }
      FileWriteString(handle, headerLine + "\r\n");
     }

   //+------------------------------------------------------------------+
   //| Write CSV row / CSV行を書き込み                                 |
   //+------------------------------------------------------------------+
   static void WriteCSVRow(int handle, const string &values[])
     {
      string row = "";
      int count = ArraySize(values);
      for(int i = 0; i < count; i++)
        {
         if(i > 0)
            row += ",";
         row += values[i];
        }
      FileWriteString(handle, row + "\r\n");
     }

   //+------------------------------------------------------------------+
   //| Format datetime for CSV / CSV用に日時をフォーマット             |
   //+------------------------------------------------------------------+
   static string FormatDatetime(const datetime dt)
     {
      MqlDateTime mdt;
      TimeToStruct(dt, mdt);
      return StringFormat("%04d-%02d-%02d %02d:%02d:%02d",
                         mdt.year, mdt.mon, mdt.day,
                         mdt.hour, mdt.min, mdt.sec);
     }

   //+------------------------------------------------------------------+
   //| Format double value / double値をフォーマット                     |
   //+------------------------------------------------------------------+
   static string FormatDouble(const double value, const int digits = 5)
     {
      return DoubleToString(value, digits);
     }

public:
   //+------------------------------------------------------------------+
   //| Export OHLCV data to CSV / OHLCVデータをCSVにエクスポート       |
   //+------------------------------------------------------------------+
   static bool ExportOHLCV(const string symbol, const ENUM_TIMEFRAMES tf, 
                           const int bars, const string filename)
     {
      if(bars <= 0)
         return false;
      
      int handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_COMMON, ',');
      if(handle == INVALID_HANDLE)
         return false;
      
      // Write header / ヘッダーを書き込み
      string headers[];
      ArrayResize(headers, 6);
      headers[0] = "datetime";
      headers[1] = "open";
      headers[2] = "high";
      headers[3] = "low";
      headers[4] = "close";
      headers[5] = "volume";
      WriteCSVHeader(handle, headers);
      
      // Copy price arrays / 価格配列をコピー
      double open[], high[], low[], close[], volume[];
      datetime time[];
      
      int copied = CopyOpen(symbol, tf, 0, bars, open);
      if(copied != bars)
        {
         FileClose(handle);
         return false;
        }
      
      CopyHigh(symbol, tf, 0, bars, high);
      CopyLow(symbol, tf, 0, bars, low);
      CopyClose(symbol, tf, 0, bars, close);
      CopyTickVolume(symbol, tf, 0, bars, volume);
      CopyTime(symbol, tf, 0, bars, time);
      
      // Write data rows / データ行を書き込み
      string values[];
      ArrayResize(values, 6);
      
      for(int i = bars - 1; i >= 0; i--) // Oldest first / 古い順
        {
         values[0] = FormatDatetime(time[i]);
         values[1] = FormatDouble(open[i]);
         values[2] = FormatDouble(high[i]);
         values[3] = FormatDouble(low[i]);
         values[4] = FormatDouble(close[i]);
         values[5] = IntegerToString((long)volume[i]);
         WriteCSVRow(handle, values);
        }
      
      FileClose(handle);
      return true;
     }

   //+------------------------------------------------------------------+
   //| Export OHLCV with indicators / インジケーター付きOHLCVをエクスポート |
   //+------------------------------------------------------------------+
   static bool ExportWithIndicators(const string symbol, const ENUM_TIMEFRAMES tf,
                                    const int bars, const string filename)
     {
      if(bars <= 0)
         return false;
      
      // Create indicators / インジケーターを作成
      int rsiHandle = iRSI(symbol, tf, 14, PRICE_CLOSE);
      int atrHandle = iATR(symbol, tf, 14);
      int maHandle = iMA(symbol, tf, 20, 0, MODE_SMA, PRICE_CLOSE);
      
      if(rsiHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE || maHandle == INVALID_HANDLE)
         return false;
      
      int handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_COMMON, ',');
      if(handle == INVALID_HANDLE)
        {
         IndicatorRelease(rsiHandle);
         IndicatorRelease(atrHandle);
         IndicatorRelease(maHandle);
         return false;
        }
      
      // Write header / ヘッダーを書き込み
      string headers[];
      ArrayResize(headers, 9);
      headers[0] = "datetime";
      headers[1] = "open";
      headers[2] = "high";
      headers[3] = "low";
      headers[4] = "close";
      headers[5] = "volume";
      headers[6] = "rsi";
      headers[7] = "atr";
      headers[8] = "ma20";
      WriteCSVHeader(handle, headers);
      
      // Copy data / データをコピー
      double open[], high[], low[], close[], volume[];
      double rsi[], atr[], ma[];
      datetime time[];
      
      int copied = CopyOpen(symbol, tf, 0, bars, open);
      if(copied != bars)
        {
         FileClose(handle);
         IndicatorRelease(rsiHandle);
         IndicatorRelease(atrHandle);
         IndicatorRelease(maHandle);
         return false;
        }
      
      CopyHigh(symbol, tf, 0, bars, high);
      CopyLow(symbol, tf, 0, bars, low);
      CopyClose(symbol, tf, 0, bars, close);
      CopyTickVolume(symbol, tf, 0, bars, volume);
      CopyTime(symbol, tf, 0, bars, time);
      
      CopyBuffer(rsiHandle, 0, 0, bars, rsi);
      CopyBuffer(atrHandle, 0, 0, bars, atr);
      CopyBuffer(maHandle, 0, 0, bars, ma);
      
      // Write data rows / データ行を書き込み
      string values[];
      ArrayResize(values, 9);
      
      for(int i = bars - 1; i >= 0; i--)
        {
         values[0] = FormatDatetime(time[i]);
         values[1] = FormatDouble(open[i]);
         values[2] = FormatDouble(high[i]);
         values[3] = FormatDouble(low[i]);
         values[4] = FormatDouble(close[i]);
         values[5] = IntegerToString((long)volume[i]);
         values[6] = FormatDouble(rsi[i], 2);
         values[7] = FormatDouble(atr[i]);
         values[8] = FormatDouble(ma[i]);
         WriteCSVRow(handle, values);
        }
      
      FileClose(handle);
      IndicatorRelease(rsiHandle);
      IndicatorRelease(atrHandle);
      IndicatorRelease(maHandle);
      return true;
     }

   //+------------------------------------------------------------------+
   //| Export SMC-specific features for ML / ML用SMC特徴量をエクスポート |
   //+------------------------------------------------------------------+
   static bool ExportSmcFeatures(const string symbol, const ENUM_TIMEFRAMES tf,
                                 const int bars, const string filename)
     {
      if(bars <= 0)
         return false;
      
      int handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_COMMON, ',');
      if(handle == INVALID_HANDLE)
         return false;
      
      // Write header / ヘッダーを書き込み
      string headers[];
      ArrayResize(headers, 12);
      headers[0] = "datetime";
      headers[1] = "open";
      headers[2] = "high";
      headers[3] = "low";
      headers[4] = "close";
      headers[5] = "volume";
      headers[6] = "return";
      headers[7] = "body_ratio";
      headers[8] = "wick_upper_ratio";
      headers[9] = "wick_lower_ratio";
      headers[10] = "volatility";
      headers[11] = "range_ratio";
      WriteCSVHeader(handle, headers);
      
      // Copy price data / 価格データをコピー
      double open[], high[], low[], close[], volume[];
      datetime time[];
      
      int copied = CopyOpen(symbol, tf, 0, bars, open);
      if(copied != bars)
        {
         FileClose(handle);
         return false;
        }
      
      CopyHigh(symbol, tf, 0, bars, high);
      CopyLow(symbol, tf, 0, bars, low);
      CopyClose(symbol, tf, 0, bars, close);
      CopyTickVolume(symbol, tf, 0, bars, volume);
      CopyTime(symbol, tf, 0, bars, time);
      
      // Calculate features / 特徴量を計算
      string values[];
      ArrayResize(values, 12);
      
      for(int i = bars - 1; i >= 0; i--)
        {
         // Basic OHLCV / 基本OHLCV
         values[0] = FormatDatetime(time[i]);
         values[1] = FormatDouble(open[i]);
         values[2] = FormatDouble(high[i]);
         values[3] = FormatDouble(low[i]);
         values[4] = FormatDouble(close[i]);
         values[5] = IntegerToString((long)volume[i]);
         
         // Return (close-to-close) / リターン（終値-終値）
         double ret = 0.0;
         if(i < bars - 1)
            ret = (close[i] - close[i + 1]) / close[i + 1];
         values[6] = FormatDouble(ret, 6);
         
         // Body ratio / ボディ比率
         double bodySize = MathAbs(close[i] - open[i]);
         double range = high[i] - low[i];
         double bodyRatio = (range > 0) ? bodySize / range : 0.0;
         values[7] = FormatDouble(bodyRatio, 4);
         
         // Upper wick ratio / 上ヒゲ比率
         double upperWick = high[i] - MathMax(open[i], close[i]);
         double upperWickRatio = (range > 0) ? upperWick / range : 0.0;
         values[8] = FormatDouble(upperWickRatio, 4);
         
         // Lower wick ratio / 下ヒゲ比率
         double lowerWick = MathMin(open[i], close[i]) - low[i];
         double lowerWickRatio = (range > 0) ? lowerWick / range : 0.0;
         values[9] = FormatDouble(lowerWickRatio, 4);
         
         // Volatility (ATR-like, using recent range) / ボラティリティ（ATR風、最近のレンジ使用）
         double volatility = 0.0;
         if(i < bars - 1)
           {
            double sumRange = 0.0;
            int period = MathMin(14, bars - i - 1);
            for(int j = 0; j < period; j++)
               sumRange += (high[i + j] - low[i + j]);
            volatility = (period > 0) ? sumRange / period : range;
           }
         else
            volatility = range;
         values[10] = FormatDouble(volatility, 5);
         
         // Range ratio (current range vs average) / レンジ比率（現在のレンジ vs 平均）
         double rangeRatio = 1.0;
         if(i < bars - 1)
           {
            double avgRange = 0.0;
            int period = MathMin(20, bars - i - 1);
            for(int j = 0; j < period; j++)
               avgRange += (high[i + j] - low[i + j]);
            avgRange = (period > 0) ? avgRange / period : range;
            rangeRatio = (avgRange > 0) ? range / avgRange : 1.0;
           }
         values[11] = FormatDouble(rangeRatio, 4);
         
         WriteCSVRow(handle, values);
        }
      
      FileClose(handle);
      return true;
     }

   //+------------------------------------------------------------------+
   //| Export multiple symbols / 複数シンボルをエクスポート               |
   //+------------------------------------------------------------------+
   static bool ExportMultiSymbol(string &symbols[], const ENUM_TIMEFRAMES tf,
                                 const int bars, const string folder)
     {
      int count = ArraySize(symbols);
      if(count == 0)
         return false;
      
      bool allSuccess = true;
      
      for(int i = 0; i < count; i++)
        {
         string filename = folder + "\\" + symbols[i] + "_" + 
                          IntegerToString(tf) + "_OHLCV.csv";
         
         if(!ExportOHLCV(symbols[i], tf, bars, filename))
           {
            allSuccess = false;
            Print("Failed to export: ", symbols[i]);
           }
        }
      
      return allSuccess;
     }
  };

#endif // __SMC_DATA_EXPORTER_MQH__
//+------------------------------------------------------------------+
