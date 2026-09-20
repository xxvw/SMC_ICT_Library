//+------------------------------------------------------------------+
//|                                                   TimeUtils.mqh  |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_TIME_UTILS_MQH__
#define __SMC_TIME_UTILS_MQH__

#include "../Core/SmcTypes.mqh"

//+------------------------------------------------------------------+
//| CSmcTimeUtils - Time utility functions                           |
//|                                                                    |
//| Static utility methods for:                                      |
//|   - GMT offset detection                                          |
//|   - Time conversions                                              |
//|   - New bar detection                                             |
//|   - Day/weekend checks                                            |
//|   - DST detection                                                 |
//+------------------------------------------------------------------+
class CSmcTimeUtils
  {
private:
   static string   m_barKeys[];
   static datetime m_lastBarTime[];  // Track last bar time per symbol+timeframe
                                     // シンボル+タイムフレームごとの最後のバー時刻を追跡

public:
   //--- GMT Offset Methods / GMTオフセットメソッド
   
   //+------------------------------------------------------------------+
   //| Auto-detect broker GMT offset                                   |
   //| ブローカーのGMTオフセットを自動検出                             |
   //+------------------------------------------------------------------+
   static int GetGMTOffset()
     {
      // Live estimate only. Historical conversions must supply the broker's
      // offset explicitly; the workstation timezone is not the broker timezone.
      datetime serverTime = TimeTradeServer();
      datetime utcTime = TimeGMT();
      if(serverTime <= 0 || utcTime <= 0)
         return 0;
      return (int)MathRound((double)(serverTime - utcTime) / 3600.0);
     }
   
   //+------------------------------------------------------------------+
   //| Convert local time to GMT                                       |
   //| ローカル時刻をGMTに変換                                         |
   //+------------------------------------------------------------------+
   static datetime ToGMT(const datetime time, const int offset)
     {
      return time - (offset * 3600);
     }
   
   //+------------------------------------------------------------------+
   //| Convert GMT time to local time                                  |
   //| GMT時刻をローカル時刻に変換                                     |
   //+------------------------------------------------------------------+
   static datetime FromGMT(const datetime time, const int offset)
     {
      return time + (offset * 3600);
     }
   
   //--- Bar Detection Methods / バー検出メソッド
   
   //+------------------------------------------------------------------+
   //| Check if a new bar has formed                                   |
   //| 新しいバーが形成されたかチェック                                 |
   //+------------------------------------------------------------------+
   static bool IsNewBar(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      datetime currentBarTime = iTime(symbol, tf, 0);
      
      if(currentBarTime == 0)
         return false;
      
      // Use the exact key; hashes can make two symbols suppress each other.
      string key = symbol + "_" + IntegerToString(tf);
      int index = -1;
      for(int i = 0; i < ArraySize(m_barKeys); i++)
         if(m_barKeys[i] == key) { index = i; break; }
      if(index < 0)
        {
         index = ArraySize(m_barKeys);
         if(ArrayResize(m_barKeys, index + 1) != index + 1 ||
            ArrayResize(m_lastBarTime, index + 1) != index + 1)
            return false;
         m_barKeys[index] = key;
         m_lastBarTime[index] = 0;
        }
      if(m_lastBarTime[index] != currentBarTime)
        {
         m_lastBarTime[index] = currentBarTime;
         return true;
        }
      
      return false;
     }
   
   //--- Day/Week Methods / 日/週メソッド
   
   //+------------------------------------------------------------------+
   //| Get day of week (0=Sunday, 1=Monday, ..., 6=Saturday)           |
   //| 曜日を取得（0=日曜日、1=月曜日、...、6=土曜日）                 |
   //+------------------------------------------------------------------+
   static int GetDayOfWeek()
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      return dt.day_of_week;
     }
   
   //+------------------------------------------------------------------+
   //| Check if current time is weekend                                |
   //| 現在の時刻が週末かチェック                                       |
   //+------------------------------------------------------------------+
   static bool IsWeekend()
     {
      int dayOfWeek = GetDayOfWeek();
      return (dayOfWeek == 0 || dayOfWeek == 6); // Sunday or Saturday
     }
   
   //+------------------------------------------------------------------+
   //| Check if current time is end of trading day                      |
   //| 現在の時刻が取引日の終わりかチェック                             |
   //+------------------------------------------------------------------+
   static bool IsEndOfDay(const int hourGMT = 22)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      
      // Convert to GMT if needed
      // 必要に応じてGMTに変換
      int gmtOffset = GetGMTOffset();
      int currentHourGMT = dt.hour - gmtOffset;
      if(currentHourGMT < 0)
         currentHourGMT += 24;
      if(currentHourGMT >= 24)
         currentHourGMT -= 24;
      
      return (currentHourGMT >= hourGMT);
     }
   
   //+------------------------------------------------------------------+
   //| Check if current time is end of trading week                    |
   //| 現在の時刻が取引週の終わりかチェック                             |
   //+------------------------------------------------------------------+
   static bool IsEndOfWeek()
     {
      MqlDateTime dt;
      TimeToStruct(ToGMT(TimeCurrent(), GetGMTOffset()), dt);
      return (dt.day_of_week == 5 && dt.hour >= 22);
     }
   
   //--- DST Detection Methods / DST検出メソッド
   
   //+------------------------------------------------------------------+
   //| Check if daylight saving time is active                         |
   //| サマータイムが有効かチェック                                     |
   //+------------------------------------------------------------------+
   static bool IsDST()
     {
      // A broker's historical DST policy cannot be inferred from local time.
      // This legacy no-argument query reports no known adjustment.
      return false;
     }
   
   // Broker DST is explicit: callers supply standard and current offsets.
   static bool IsDST(const int standardOffset, const int currentOffset)
     {
      return currentOffset == standardOffset + 1;
     }

   // Most recently started daily window. An equal start/end is a full day,
   // preserving the legacy range convention. Returned bounds are server time.
   static bool SessionBounds(const datetime serverTime,
                             const int startHour, const int startMinute,
                             const int endHour, const int endMinute,
                             const int gmtOffset,
                             datetime &start, datetime &end)
     {
      start = 0;
      end = 0;
      if(serverTime <= 0 || startHour < 0 || startHour > 23 ||
         endHour < 0 || endHour > 23 || startMinute < 0 || startMinute > 59 ||
         endMinute < 0 || endMinute > 59)
         return false;
      datetime reference = ToGMT(serverTime, gmtOffset);
      MqlDateTime day;
      if(!TimeToStruct(reference, day))
         return false;
      day.hour = 0; day.min = 0; day.sec = 0;
      datetime window = StructToTime(day) + (startHour * 60 + startMinute) * 60;
      if(reference < window)
         window -= 86400;
      int duration = (endHour * 60 + endMinute) - (startHour * 60 + startMinute);
      if(duration <= 0)
         duration += 1440;
      start = FromGMT(window, gmtOffset);
      end = start + duration * 60;
      return true;
     }

   static bool IsInSessionAt(const datetime serverTime,
                            const int startHour, const int startMinute,
                            const int endHour, const int endMinute,
                            const int gmtOffset = 0)
     {
      datetime start, end;
      return SessionBounds(serverTime, startHour, startMinute, endHour, endMinute,
                           gmtOffset, start, end) && serverTime >= start && serverTime < end;
     }

   //--- Bar Time Methods / バー時刻メソッド
   
   //+------------------------------------------------------------------+
   //| Get seconds since current bar opened                            |
   //| 現在のバーが開いてからの秒数を取得                               |
   //+------------------------------------------------------------------+
   static int SecondsSinceBarOpen(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      datetime barTime = iTime(symbol, tf, 0);
      if(barTime == 0)
         return 0;
      
      datetime currentTime = TimeCurrent();
      return (int)(currentTime - barTime);
     }
  };

// Initialize static array
// 静的配列を初期化
string CSmcTimeUtils::m_barKeys[];
datetime CSmcTimeUtils::m_lastBarTime[];

#endif // __SMC_TIME_UTILS_MQH__
//+------------------------------------------------------------------+
