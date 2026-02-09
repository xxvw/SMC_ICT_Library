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
      datetime serverTime = TimeCurrent();
      datetime localTime = TimeLocal();
      
      // Calculate offset in hours
      // オフセットを時間単位で計算
      int offsetSeconds = (int)(serverTime - localTime);
      int offsetHours = offsetSeconds / 3600;
      
      return offsetHours;
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
      
      // Create unique key for symbol+timeframe combination
      // シンボル+タイムフレームの組み合わせの一意キーを作成
      string key = symbol + "_" + IntegerToString(tf);
      
      // Simple hash function for MQL5 compatibility
      // MQL5互換の簡単なハッシュ関数
      int hash = 0;
      int len = StringLen(key);
      for(int i = 0; i < len; i++)
         hash = hash * 31 + StringGetCharacter(key, i);
      hash = MathAbs(hash) % 1000; // Limit to reasonable array size
                                    // 合理的な配列サイズに制限
      
      // Resize array if needed
      // 必要に応じて配列をリサイズ
      int arraySize = ArraySize(m_lastBarTime);
      if(hash >= arraySize)
        {
         int newSize = hash + 10; // Add some buffer
                                    // バッファを追加
         ArrayResize(m_lastBarTime, newSize);
         // Initialize new elements to 0
         // 新しい要素を0で初期化
         for(int i = arraySize; i < newSize; i++)
            m_lastBarTime[i] = 0;
        }
      
      // Check if bar time has changed
      // バー時刻が変更されたかチェック
      if(m_lastBarTime[hash] != currentBarTime)
        {
         m_lastBarTime[hash] = currentBarTime;
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
      int dayOfWeek = GetDayOfWeek();
      int hour = TimeHour(TimeCurrent());
      
      // Friday after market close (typically 22:00 GMT)
      // 金曜日の市場終了後（通常22:00 GMT）
      return (dayOfWeek == 5 && hour >= 22);
     }
   
   //--- DST Detection Methods / DST検出メソッド
   
   //+------------------------------------------------------------------+
   //| Check if daylight saving time is active                         |
   //| サマータイムが有効かチェック                                     |
   //+------------------------------------------------------------------+
   static bool IsDST()
     {
      datetime serverTime = TimeCurrent();
      datetime localTime = TimeLocal();
      
      // If server time is ahead of local time by non-standard amount,
      // it might indicate DST
      // サーバー時刻がローカル時刻より標準以外の量だけ進んでいる場合、
      // DSTを示している可能性がある
      int offsetSeconds = (int)(serverTime - localTime);
      int offsetHours = offsetSeconds / 3600;
      
      // This is a simple heuristic - adjust based on your broker's timezone
      // これは簡単なヒューリスティックです - ブローカーのタイムゾーンに応じて調整
      // Most brokers don't observe DST, so this checks for unusual offsets
      // ほとんどのブローカーはDSTを観察しないため、異常なオフセットをチェック
      return (MathAbs(offsetHours) > 12); // Unusual offset might indicate DST
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
datetime CSmcTimeUtils::m_lastBarTime[];

#endif // __SMC_TIME_UTILS_MQH__
//+------------------------------------------------------------------+
