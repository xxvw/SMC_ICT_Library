// Versioned, UTF-8 JSON snapshots written to the MT5 common files directory.
#ifndef __SMC_SNAPSHOT_EXPORTER_MQH__
#define __SMC_SNAPSHOT_EXPORTER_MQH__

#include "../Core/SmcSnapshot.mqh"

class CSmcSnapshotExporter
  {
private:
   static string Quote(const string value)
     {
      string result = "\"";
      for(int i = 0; i < StringLen(value); i++)
        {
         ushort c = StringGetCharacter(value, i);
         if(c == 34) result += "\\\"";
         else if(c == 92) result += "\\\\";
         else if(c < 32 || (c >= 0xD800 && c <= 0xDFFF))
            result += StringFormat("\\u%04x", (uint)c);
         else result += ShortToString(c);
        }
      return result + "\"";
     }

   static string Boolean(const bool value) { return value ? "true" : "false"; }
   // 17 significant digits preserve an IEEE-754 double on a JSON round trip.
   static string Number(const double value) { return StringFormat("%.17g", value); }

   static bool ValidTime(const datetime value, const bool nullable)
     {
      if(value == 0) return nullable;
      if(value < 0) return false;
      MqlDateTime parts;
      return TimeToStruct(value, parts) && parts.year >= 1970 && parts.year <= 9999;
     }

   static string Timestamp(const datetime value)
     {
      if(value == 0) return "null";
      MqlDateTime parts;
      TimeToStruct(value, parts);
      return Quote(StringFormat("%04d-%02d-%02dT%02d:%02d:%02d", parts.year,
                                parts.mon, parts.day, parts.hour, parts.min, parts.sec));
     }

   static bool ValidStatus(const ENUM_SMC_STATUS value)
     { return value >= SMC_STATUS_READY && value <= SMC_STATUS_DISABLED; }

   static bool ValidConcept(const ENUM_SMC_CONCEPT value)
     { return value >= ICT_SWING_HIGH && (int)value < SMC_CONCEPT_COUNT; }

   static bool Validate(const SmcSnapshot &snapshot)
     {
      string reason;
      if(snapshot.symbol == "" || snapshot.timeBasis != "broker" ||
         !ValidStatus(snapshot.status) || !ValidTime(snapshot.asOf, true) ||
         !snapshot.config.Validate(reason)) return false;
      string tf = EnumToString(snapshot.timeframe);
      if(StringFind(tf, "PERIOD_") != 0) return false;
      for(int i = 0; i < ArraySize(snapshot.modules); i++)
        {
         if(!ValidConcept(snapshot.modules[i].concept) ||
            !ValidStatus(snapshot.modules[i].status) ||
            !ValidTime(snapshot.modules[i].asOf, true)) return false;
        }
      for(int i = 0; i < ArraySize(snapshot.records); i++)
        {
         SmcRecord record = snapshot.records[i];
         if(record.id == "" || record.state == "" || !ValidConcept(record.concept) ||
            !ValidTime(record.sourceTime, false) || !ValidTime(record.confirmedAt, false) ||
            !ValidTime(record.updatedAt, false) || !ValidTime(record.periodStart, true) ||
            !ValidTime(record.periodEnd, true) || record.direction < -1 || record.direction > 1 ||
            !MathIsValidNumber(record.lower) || !MathIsValidNumber(record.upper) ||
            record.lower > record.upper || !MathIsValidNumber(record.referencePrice) ||
            !MathIsValidNumber(record.comparisonPrice) || !MathIsValidNumber(record.strength)) return false;
        }
      return true;
     }

   static string ConfigJSON(const SmcConfig &config)
     {
      string json = "{\"lookback_bars\":" + IntegerToString(config.lookbackBars) +
         ",\"max_records_per_concept\":" + IntegerToString(config.maxRecordsPerConcept) +
         ",\"swing_strength\":" + IntegerToString(config.swingStrength) +
         ",\"displacement_baseline\":" + IntegerToString(config.displacementBaseline) +
         ",\"displacement_multiplier\":" + Number(config.displacementMultiplier) +
         ",\"displacement_body_fraction\":" + Number(config.displacementBodyFraction) +
         ",\"min_fvg_pips\":" + Number(config.minFvgPips) +
         ",\"max_zone_age\":" + IntegerToString(config.maxZoneAge) +
         ",\"bpr_max_separation\":" + IntegerToString(config.bprMaxSeparation) +
         ",\"po3_expiry_bars\":" + IntegerToString(config.po3ExpiryBars) +
         ",\"smt_symbol\":" + Quote(config.smtSymbol) +
         ",\"smt_radius\":" + IntegerToString(config.smtRadius) +
         ",\"enable_draw\":" + Boolean(config.enableDraw) +
         ",\"enable_calendar\":" + Boolean(config.enableCalendar) +
         ",\"enable_smt\":" + Boolean(config.IsSMTEnabled()) +
         ",\"enable_po3\":" + Boolean(config.enablePO3) +
         ",\"enable_displacement\":" + Boolean(config.enableDisplacement) +
         ",\"enable_mss\":" + Boolean(config.enableMSS) +
         ",\"enable_ifvg\":" + Boolean(config.enableIFVG) +
         ",\"enable_bpr\":" + Boolean(config.enableBPR) +
         ",\"enable_cs\":" + Boolean(config.enableCS) +
         ",\"enable_vix\":" + Boolean(config.enableVIX) + ",\"sessions\":[";
      for(int i = 0; i < 3; i++)
        {
         if(i > 0) json += ",";
         json += "{\"name\":" + Quote(config.sessions[i].name) +
                 ",\"start_minute\":" + IntegerToString(config.sessions[i].startMinute) +
                 ",\"end_minute\":" + IntegerToString(config.sessions[i].endMinute) + "}";
        }
      return json + "]}";
     }

   static string RecordJSON(const SmcRecord &record)
     {
      string related = "[";
      if(record.relatedId != "") related += Quote(record.relatedId);
      if(record.secondaryId != "")
        {
         if(record.relatedId != "") related += ",";
         related += Quote(record.secondaryId);
        }
      related += "]";
      return "{\"id\":" + Quote(record.id) + ",\"concept\":" + Quote(SmcConceptName(record.concept)) +
         ",\"source_time\":" + Timestamp(record.sourceTime) +
         ",\"confirmed_at\":" + Timestamp(record.confirmedAt) +
         ",\"updated_at\":" + Timestamp(record.updatedAt) +
         ",\"direction\":" + Quote(SmcDirectionName(record.direction)) +
         ",\"lower\":" + Number(record.lower) + ",\"upper\":" + Number(record.upper) +
         ",\"state\":" + Quote(record.state) + ",\"active\":" + Boolean(record.active) +
         ",\"related_ids\":" + related + ",\"period_start\":" + Timestamp(record.periodStart) +
         ",\"period_end\":" + Timestamp(record.periodEnd) +
         ",\"reference_price\":" + Number(record.referencePrice) +
         ",\"comparison_price\":" + Number(record.comparisonPrice) +
         ",\"strength\":" + Number(record.strength) + ",\"reason\":" + Quote(record.reason) + "}";
     }

public:
   // Relative paths only; names cannot escape FILE_COMMON or alias a parent path.
   static bool SafePath(const string filename)
     {
      if(filename == "") return false;
      string path = filename;
      StringReplace(path, "/", "\\");
      string components[];
      int count = StringSplit(path, '\\', components);
      for(int i = 0; i < count; i++)
        {
         string component = components[i];
         int length = StringLen(component);
         if(length == 0 || component == "." || component == ".." ||
            StringSubstr(component, length - 1) == "." ||
            StringSubstr(component, length - 1) == " ") return false;
         for(int j = 0; j < length; j++)
           {
            ushort c = StringGetCharacter(component, j);
            if(c < 32 || c == ':' || c == '*' || c == '?' || c == '"' || c == '<' || c == '>' || c == '|')
               return false;
           }
        }
      return count > 0;
     }

   // On failure json is empty, never a partially serialized document.
   static bool Serialize(const SmcSnapshot &snapshot, string &json)
     {
      json = "";
      if(!Validate(snapshot)) return false;
      string tf = EnumToString(snapshot.timeframe);
      StringReplace(tf, "PERIOD_", "");
      string result = "{\"schema_version\":" + Quote(SMC_SNAPSHOT_SCHEMA_VERSION) +
         ",\"library_version\":" + Quote(SMC_LIB_VERSION) + ",\"symbol\":" + Quote(snapshot.symbol) +
         ",\"timeframe\":" + Quote(tf) + ",\"time_basis\":\"broker\",\"as_of\":" + Timestamp(snapshot.asOf) +
         ",\"status\":" + Quote(SmcStatusName(snapshot.status)) + ",\"message\":" + Quote(snapshot.message) + ",\"config\":" + ConfigJSON(snapshot.config) +
         ",\"modules\":[";
      for(int i = 0; i < ArraySize(snapshot.modules); i++)
        {
         if(i > 0) result += ",";
         result += "{\"concept\":" + Quote(SmcConceptName(snapshot.modules[i].concept)) +
            ",\"status\":" + Quote(SmcStatusName(snapshot.modules[i].status)) +
            ",\"as_of\":" + Timestamp(snapshot.modules[i].asOf) +
            ",\"truncated\":" + Boolean(snapshot.modules[i].truncated) +
            ",\"message\":" + Quote(snapshot.modules[i].message) + "}";
        }
      result += "],\"records\":[";
      for(int i = 0; i < ArraySize(snapshot.records); i++)
        {
         if(i > 0) result += ",";
         result += RecordJSON(snapshot.records[i]);
        }
      json = result + "]}\n";
      return true;
     }

   static string ToJSON(const SmcSnapshot &snapshot)
     {
      string json;
      Serialize(snapshot, json);
      return json;
     }

   static bool Export(const SmcSnapshot &snapshot, const string filename)
     {
      string json;
      if(!SafePath(filename) || !Serialize(snapshot, json)) return false;
      uchar bytes[];
      int count = StringToCharArray(json, bytes, 0, WHOLE_ARRAY, CP_UTF8);
      if(count < 2) return false;
      // StringToCharArray includes a terminating NUL; JSON files must not.
      count--;
      static ulong sequence = 0;
      string temporary;
      do
        {
         sequence++;
         temporary = filename + ".tmp." + IntegerToString(ChartID()) + "." +
            IntegerToString((long)TimeLocal()) + "." + IntegerToString((long)GetTickCount64()) + "." +
            IntegerToString((long)GetMicrosecondCount()) + "." + IntegerToString((long)sequence);
        }
      while(FileIsExist(temporary, FILE_COMMON));
      ResetLastError();
      int handle = FileOpen(temporary, FILE_WRITE | FILE_BIN | FILE_COMMON);
      if(handle == INVALID_HANDLE) return false;
      uint written = FileWriteArray(handle, bytes, 0, count);
      FileFlush(handle);
      bool complete = written == (uint)count && FileSize(handle) == (ulong)count && GetLastError() == 0;
      FileClose(handle);
      if(!complete || GetLastError() != 0)
        {
         FileDelete(temporary, FILE_COMMON);
         return false;
        }
      // Readers observe a finished file. Never delete the previous destination.
      if(!FileMove(temporary, FILE_COMMON, filename, FILE_COMMON | FILE_REWRITE))
        {
         FileDelete(temporary, FILE_COMMON);
         return false;
        }
      return true;
     }
  };

#endif // __SMC_SNAPSHOT_EXPORTER_MQH__
