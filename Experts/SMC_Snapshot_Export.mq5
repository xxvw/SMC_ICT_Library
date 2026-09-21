// Attach to any chart to publish ICT snapshots. This EA never places orders.
#property copyright "ICT_Library_MQ5"
#property version "1.00"
#property strict

#include <SMC/SmcManager.mqh>
#include <SMC/Utils/SnapshotExporter.mqh>

input string          InpSymbol = "";                    // Blank uses the chart symbol
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_CURRENT;       // CURRENT uses the chart period
input string          InpFolder = "SMC_Export";           // Relative folder in Common/Files
input string          InpSMTSymbol = "";                  // Optional positive-correlation comparison

CSmcManager snapshot_manager;
string snapshot_symbol;
ENUM_TIMEFRAMES snapshot_timeframe;
string snapshot_filename;
datetime snapshot_completed_bar = 0;
datetime snapshot_last_attempt = 0;
int snapshot_writer_lock = INVALID_HANDLE;

string SnapshotFilenamePart(const string value)
  {
   string result = "";
   for(int i = 0; i < StringLen(value); i++)
     {
      ushort c = StringGetCharacter(value, i);
      // Brokers may use '/', ':' or other filesystem separators in symbols.
      // Encode these rather than allowing the symbol to create a path.
      if((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
         (c >= '0' && c <= '9') || c == '-' || c == '.')
         result += ShortToString(c);
      else result += StringFormat("_%04x", (uint)c);
     }
   if(result == "") result = "symbol";
   return result;
  }

void PublishClosedSnapshot()
  {
   // Rate-limit OnTick and OnTimer together while unavailable history retries.
   datetime now = TimeLocal();
   if(now == snapshot_last_attempt) return;
   snapshot_last_attempt = now;
   datetime closed = iTime(snapshot_symbol, snapshot_timeframe, 1);
   if(closed > 0 && closed == snapshot_completed_bar) return;

   bool updated = snapshot_manager.Update();
   SmcSnapshot snapshot;
   // Unavailable/error snapshots remain useful: they explicitly replace stale
   // results, and the watermark is not advanced until a READY export succeeds.
   if(!snapshot_manager.GetSnapshot(snapshot)) return;
   if(!CSmcSnapshotExporter::Export(snapshot, snapshot_filename))
     {
      Print("Snapshot export failed: ", snapshot_filename, " (error ", GetLastError(), ")");
      return;
     }
   // iTime identifies the bar by its opening time; the snapshot evaluation time
   // is its close. Recheck identity in case a new bar arrived during evaluation.
   datetime latestClosed = iTime(snapshot_symbol, snapshot_timeframe, 1);
   if(updated && snapshot.status == SMC_STATUS_READY && closed > 0 && latestClosed == closed &&
      snapshot.asOf == SmcBarClosedAt(closed, snapshot_timeframe))
      snapshot_completed_bar = closed;
  }

void ReleaseSnapshotResources()
  {
   EventKillTimer();
   snapshot_manager.Clean();
   if(snapshot_writer_lock != INVALID_HANDLE)
     {
      FileClose(snapshot_writer_lock);
      snapshot_writer_lock = INVALID_HANDLE;
     }
  }

int OnInit()
  {
   // Globals may survive reinitialization after chart/input changes.
   ReleaseSnapshotResources();
   snapshot_completed_bar = 0;
   snapshot_last_attempt = 0;
   snapshot_symbol = InpSymbol == "" ? _Symbol : InpSymbol;
   snapshot_timeframe = InpTimeframe == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)_Period : InpTimeframe;
   if(InpFolder == "" || !CSmcSnapshotExporter::SafePath(InpFolder))
     {
      Print("InpFolder must be a relative folder without parent components.");
      return INIT_PARAMETERS_INCORRECT;
     }
   string period = EnumToString(snapshot_timeframe);
   StringReplace(period, "PERIOD_", "");
   snapshot_filename = InpFolder + "\\" + SnapshotFilenamePart(snapshot_symbol) + "_" + period + ".json";
   if(!CSmcSnapshotExporter::SafePath(snapshot_filename)) return INIT_PARAMETERS_INCORRECT;
   // One publisher owns each destination. Other configurations/terminals can
   // use a separate InpFolder. The OS releases this lock after exit or a crash;
   // its empty file can remain safely and must not be deleted after unlocking.
   snapshot_writer_lock = FileOpen(snapshot_filename + ".lock", FILE_READ | FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(snapshot_writer_lock == INVALID_HANDLE)
     {
      Print("Snapshot destination is unavailable or already has a publisher: ", snapshot_filename);
      return INIT_FAILED;
     }
   SmcConfig config;
   config.SetDefaults();
   config.enableDraw = false;
   config.smtSymbol = InpSMTSymbol;
   if(!snapshot_manager.Init(snapshot_symbol, snapshot_timeframe, config))
     {
      Print("Snapshot manager initialization failed.");
      ReleaseSnapshotResources();
      return INIT_FAILED;
     }
   if(!EventSetTimer(1))
     {
      ReleaseSnapshotResources();
      return INIT_FAILED;
     }
   Print("Snapshot output: ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\", snapshot_filename);
   PublishClosedSnapshot();
   return INIT_SUCCEEDED;
  }

void OnTick() { PublishClosedSnapshot(); }
void OnTimer() { PublishClosedSnapshot(); }
void OnDeinit(const int reason)
  {
   ReleaseSnapshotResources();
  }
