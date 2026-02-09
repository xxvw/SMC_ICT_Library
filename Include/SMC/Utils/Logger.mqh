//+------------------------------------------------------------------+
//|                                                     Logger.mqh   |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_LOGGER_MQH__
#define __SMC_LOGGER_MQH__

#include "../Core/SmcTypes.mqh"

//+------------------------------------------------------------------+
//| CSmcLogger - Logging utility class                               |
//|                                                                    |
//| Static singleton-like logger with file output support:           |
//|   - Multiple log levels (DEBUG, INFO, WARN, ERROR)                |
//|   - Module name tagging                                           |
//|   - File logging with rotation (max 1MB)                          |
//|   - Formatted output: [LEVEL][Module][HH:MM:SS] message          |
//+------------------------------------------------------------------+
class CSmcLogger
  {
private:
   static ENUM_LOG_LEVEL m_level;        // Current log level / 現在のログレベル
   static string         m_moduleName;   // Module name / モジュール名
   static bool           m_enableFile;   // File logging enabled / ファイルログ有効
   static int            m_fileHandle;   // File handle / ファイルハンドル
   static string         m_fileName;     // Current log file name / 現在のログファイル名
   static long           m_fileSize;     // Current file size / 現在のファイルサイズ
   static const long     MAX_FILE_SIZE = 1048576;  // Max file size (1MB) / 最大ファイルサイズ (1MB)

   //+------------------------------------------------------------------+
   //| Get log level string / ログレベル文字列を取得                   |
   //+------------------------------------------------------------------+
   static string GetLevelString(const ENUM_LOG_LEVEL level)
     {
      switch(level)
        {
         case LOG_DEBUG: return "DEBUG";
         case LOG_INFO:  return "INFO";
         case LOG_WARN:  return "WARN";
         case LOG_ERROR: return "ERROR";
         default:        return "UNKNOWN";
        }
     }

   //+------------------------------------------------------------------+
   //| Format log message / ログメッセージをフォーマット               |
   //+------------------------------------------------------------------+
   static string FormatMessage(const ENUM_LOG_LEVEL level, const string msg)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      
      string timeStr = StringFormat("%02d:%02d:%02d", dt.hour, dt.min, dt.sec);
      string levelStr = GetLevelString(level);
      string moduleStr = (m_moduleName != "") ? m_moduleName : "SMC";
      
      return StringFormat("[%s][%s][%s] %s", levelStr, moduleStr, timeStr, msg);
     }

   //+------------------------------------------------------------------+
   //| Write to file / ファイルに書き込み                               |
   //+------------------------------------------------------------------+
   static void WriteToFile(const string msg)
     {
      if(!m_enableFile || m_fileHandle == INVALID_HANDLE)
         return;
      
      // Check file size and rotate if needed / ファイルサイズをチェックし、必要に応じてローテーション
      if(m_fileSize > MAX_FILE_SIZE)
        {
         FileClose(m_fileHandle);
         m_fileHandle = INVALID_HANDLE;
         
         // Create backup filename / バックアップファイル名を作成
         string backupName = m_fileName + ".bak";
         FileMove(m_fileName, 0, backupName, FILE_REWRITE);
         
         // Reopen file / ファイルを再オープン
         m_fileHandle = FileOpen(m_fileName, FILE_WRITE | FILE_TXT | FILE_COMMON);
         if(m_fileHandle != INVALID_HANDLE)
           {
            m_fileSize = 0;
            FileWriteString(m_fileHandle, "=== Log Rotation ===\r\n");
            m_fileSize += StringLen("=== Log Rotation ===\r\n");
           }
        }
      
      if(m_fileHandle != INVALID_HANDLE)
        {
         string line = msg + "\r\n";
         FileWriteString(m_fileHandle, line);
         m_fileSize += StringLen(line);
        }
     }

   //+------------------------------------------------------------------+
   //| Initialize file logging / ファイルログを初期化                   |
   //+------------------------------------------------------------------+
   static void InitFileLogging(const string filename)
     {
      if(m_fileHandle != INVALID_HANDLE)
         FileClose(m_fileHandle);
      
      m_fileHandle = FileOpen(filename, FILE_WRITE | FILE_READ | FILE_TXT | FILE_COMMON);
      if(m_fileHandle != INVALID_HANDLE)
        {
         m_fileName = filename;
         FileSeek(m_fileHandle, 0, SEEK_END);
         m_fileSize = FileTell(m_fileHandle);
         FileSeek(m_fileHandle, 0, SEEK_END);
        }
      else
        {
         m_fileHandle = INVALID_HANDLE;
         m_fileSize = 0;
        }
     }

public:
   //+------------------------------------------------------------------+
   //| Set log level / ログレベルを設定                                 |
   //+------------------------------------------------------------------+
   static void SetLevel(const ENUM_LOG_LEVEL level)
     {
      m_level = level;
     }

   //+------------------------------------------------------------------+
   //| Set module name / モジュール名を設定                             |
   //+------------------------------------------------------------------+
   static void SetModule(const string name)
     {
      m_moduleName = name;
     }

   //+------------------------------------------------------------------+
   //| Enable file logging / ファイルログを有効化                       |
   //+------------------------------------------------------------------+
   static void EnableFileLog(const string filename)
     {
      m_enableFile = true;
      InitFileLogging(filename);
     }

   //+------------------------------------------------------------------+
   //| Disable file logging / ファイルログを無効化                     |
   //+------------------------------------------------------------------+
   static void DisableFileLog()
     {
      m_enableFile = false;
      if(m_fileHandle != INVALID_HANDLE)
        {
         FileClose(m_fileHandle);
         m_fileHandle = INVALID_HANDLE;
        }
     }

   //+------------------------------------------------------------------+
   //| Log debug message / デバッグメッセージをログ                     |
   //+------------------------------------------------------------------+
   static void Debug(const string msg)
     {
      if(m_level > LOG_DEBUG)
         return;
      
      string formatted = FormatMessage(LOG_DEBUG, msg);
      Print(formatted);
      WriteToFile(formatted);
     }

   //+------------------------------------------------------------------+
   //| Log info message / 情報メッセージをログ                           |
   //+------------------------------------------------------------------+
   static void Info(const string msg)
     {
      if(m_level > LOG_INFO)
         return;
      
      string formatted = FormatMessage(LOG_INFO, msg);
      Print(formatted);
      WriteToFile(formatted);
     }

   //+------------------------------------------------------------------+
   //| Log warning message / 警告メッセージをログ                       |
   //+------------------------------------------------------------------+
   static void Warn(const string msg)
     {
      if(m_level > LOG_WARN)
         return;
      
      string formatted = FormatMessage(LOG_WARN, msg);
      Print(formatted);
      WriteToFile(formatted);
     }

   //+------------------------------------------------------------------+
   //| Log error message / エラーメッセージをログ                         |
   //+------------------------------------------------------------------+
   static void Error(const string msg)
     {
      if(m_level > LOG_ERROR)
         return;
      
      string formatted = FormatMessage(LOG_ERROR, msg);
      Print(formatted);
      WriteToFile(formatted);
     }

   //+------------------------------------------------------------------+
   //| Get current log level / 現在のログレベルを取得                   |
   //+------------------------------------------------------------------+
   static ENUM_LOG_LEVEL GetLevel()
     {
      return m_level;
     }

   //+------------------------------------------------------------------+
   //| Check if file logging is enabled / ファイルログが有効かチェック |
   //+------------------------------------------------------------------+
   static bool IsFileLogEnabled()
     {
      return m_enableFile && m_fileHandle != INVALID_HANDLE;
     }
  };

// Initialize static members / 静的メンバを初期化
ENUM_LOG_LEVEL CSmcLogger::m_level = LOG_INFO;
string         CSmcLogger::m_moduleName = "";
bool           CSmcLogger::m_enableFile = false;
int            CSmcLogger::m_fileHandle = INVALID_HANDLE;
string         CSmcLogger::m_fileName = "";
long           CSmcLogger::m_fileSize = 0;

#endif // __SMC_LOGGER_MQH__
//+------------------------------------------------------------------+
