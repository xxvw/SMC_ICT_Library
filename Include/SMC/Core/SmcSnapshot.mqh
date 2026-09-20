// Typed, language-neutral ICT snapshot contract. All timestamps use broker time.
#ifndef __SMC_SNAPSHOT_MQH__
#define __SMC_SNAPSHOT_MQH__

#include "SmcTypes.mqh"

#define SMC_SNAPSHOT_SCHEMA_VERSION "1.0"
#define SMC_CONCEPT_COUNT 25

enum ENUM_SMC_STATUS
  {
   SMC_STATUS_READY = 0,
   SMC_STATUS_PARTIAL,
   SMC_STATUS_NOT_READY,
   SMC_STATUS_ERROR,
   SMC_STATUS_DISABLED
  };

enum ENUM_SMC_CONCEPT
  {
   ICT_SWING_HIGH = 0, ICT_SWING_LOW, ICT_BOS, ICT_CHOCH, ICT_ORDER_BLOCK,
   ICT_FVG, ICT_LIQUIDITY, ICT_PREMIUM_DISCOUNT, ICT_OTE, ICT_KILL_ZONE,
   ICT_BREAKER, ICT_DISPLACEMENT, ICT_MSS, ICT_IFVG, ICT_BPR,
   ICT_PREVIOUS_DAY_HIGH, ICT_PREVIOUS_DAY_LOW, ICT_PREVIOUS_WEEK_HIGH,
   ICT_PREVIOUS_WEEK_LOW, ICT_SESSION_HIGH, ICT_SESSION_LOW,
   ICT_DAILY_GAP, ICT_WEEKLY_GAP, ICT_SMT, ICT_PO3
  };

string SmcConceptName(const ENUM_SMC_CONCEPT concept)
  {
   switch(concept)
     {
      case ICT_SWING_HIGH: return "SWING_HIGH";
      case ICT_SWING_LOW: return "SWING_LOW";
      case ICT_BOS: return "BOS";
      case ICT_CHOCH: return "CHOCH";
      case ICT_ORDER_BLOCK: return "ORDER_BLOCK";
      case ICT_FVG: return "FVG";
      case ICT_LIQUIDITY: return "LIQUIDITY";
      case ICT_PREMIUM_DISCOUNT: return "PREMIUM_DISCOUNT";
      case ICT_OTE: return "OTE";
      case ICT_KILL_ZONE: return "KILL_ZONE";
      case ICT_BREAKER: return "BREAKER";
      case ICT_DISPLACEMENT: return "DISPLACEMENT";
      case ICT_MSS: return "MSS";
      case ICT_IFVG: return "IFVG";
      case ICT_BPR: return "BPR";
      case ICT_PREVIOUS_DAY_HIGH: return "PREVIOUS_DAY_HIGH";
      case ICT_PREVIOUS_DAY_LOW: return "PREVIOUS_DAY_LOW";
      case ICT_PREVIOUS_WEEK_HIGH: return "PREVIOUS_WEEK_HIGH";
      case ICT_PREVIOUS_WEEK_LOW: return "PREVIOUS_WEEK_LOW";
      case ICT_SESSION_HIGH: return "SESSION_HIGH";
      case ICT_SESSION_LOW: return "SESSION_LOW";
      case ICT_DAILY_GAP: return "DAILY_GAP";
      case ICT_WEEKLY_GAP: return "WEEKLY_GAP";
      case ICT_SMT: return "SMT";
      case ICT_PO3: return "PO3";
     }
   return "UNKNOWN";
  }

string SmcStatusName(const ENUM_SMC_STATUS status)
  {
   switch(status)
     {
      case SMC_STATUS_READY: return "READY";
      case SMC_STATUS_PARTIAL: return "PARTIAL";
      case SMC_STATUS_NOT_READY: return "NOT_READY";
      case SMC_STATUS_ERROR: return "ERROR";
      case SMC_STATUS_DISABLED: return "DISABLED";
     }
   return "ERROR";
  }

string SmcDirectionName(const int direction)
  {
   if(direction > 0) return "bullish";
   if(direction < 0) return "bearish";
   return "neutral";
  }

// Monthly candles close at the next calendar boundary, not after 30 days.
datetime SmcBarClosedAt(const datetime openTime, const ENUM_TIMEFRAMES timeframe)
  {
   if(openTime <= 0) return 0;
   ENUM_TIMEFRAMES resolved = timeframe;
   if(resolved == PERIOD_CURRENT) resolved = (ENUM_TIMEFRAMES)Period();
   if(resolved == PERIOD_MN1)
     {
      MqlDateTime parts;
      if(!TimeToStruct(openTime, parts)) return 0;
      parts.mon++;
      if(parts.mon > 12) { parts.mon = 1; parts.year++; }
      parts.day = 1;
      parts.hour = 0;
      parts.min = 0;
      parts.sec = 0;
      return StructToTime(parts);
     }
   int seconds = PeriodSeconds(resolved);
   return seconds > 0 ? openTime + seconds : 0;
  }

struct SmcSessionConfig
  {
   string name;
   int    startMinute;
   int    endMinute;

   void Init()
     {
      name = "";
      startMinute = 0;
      endMinute = 0;
     }
  };

struct SmcConfig
  {
   int    lookbackBars;
   int    maxRecordsPerConcept;
   int    swingStrength;
   int    displacementBaseline;
   double displacementMultiplier;
   double displacementBodyFraction;
   double minFvgPips;
   int    maxZoneAge;
   int    bprMaxSeparation;
   int    po3ExpiryBars;
   string smtSymbol;
   int    smtRadius;
   bool   enableDraw;
   bool   enableCalendar;
   bool   enableSMT;
   bool   enablePO3;
   bool   enableDisplacement;
   bool   enableMSS;
   bool   enableIFVG;
   bool   enableBPR;
   bool   enableCS;
   bool   enableVIX;
   SmcSessionConfig sessions[3];

   void SetDefaults()
     {
      lookbackBars = 500;
      maxRecordsPerConcept = 100;
      swingStrength = 5;
      displacementBaseline = 20;
      displacementMultiplier = 1.5;
      displacementBodyFraction = 0.6;
      minFvgPips = 2.0;
      maxZoneAge = 200;
      bprMaxSeparation = 50;
      po3ExpiryBars = 20;
      smtSymbol = "";
      smtRadius = 1;
      enableDraw = false;
      enableCalendar = true;
      enableSMT = false;
      enablePO3 = true;
      enableDisplacement = true;
      enableMSS = true;
      enableIFVG = true;
      enableBPR = true;
      enableCS = false;
      enableVIX = false;
      sessions[0].name = "Asian";
      sessions[0].startMinute = 0;
      sessions[0].endMinute = 480;
      sessions[1].name = "London";
      sessions[1].startMinute = 420;
      sessions[1].endMinute = 960;
      sessions[2].name = "NewYork";
      sessions[2].startMinute = 720;
      sessions[2].endMinute = 1260;
     }

   void Init() { SetDefaults(); }

   // Supplying a comparison symbol opts into SMT without a second switch.
   bool IsSMTEnabled() const { return enableSMT || smtSymbol != ""; }

   // Finite, conservative dependency horizon before the visible lookback.
   // Keep FVG and derived IFVG lifetimes, opposite FVG window, swing confirmation,
   // displacement baseline, SMT pivot neighborhood and PO3 expiry window.
   int WarmupBars() const
     {
      int zoneDependency = 2 * maxZoneAge + bprMaxSeparation + 2 * swingStrength + 1 +
                           displacementBaseline + 2 * smtRadius + 1 + po3ExpiryBars;
      // MSS direction and SMT divergence need a prior confirmed pivot within
      // the bounded evaluation horizon, plus its confirmation neighborhood.
      int pivotDependency = lookbackBars + 2 * swingStrength + displacementBaseline +
                            2 * smtRadius + 1;
      return zoneDependency > pivotDependency ? zoneDependency : pivotDependency;
     }

   bool Validate(string &reason) const
     {
      reason = "";
      if(lookbackBars < 1 || lookbackBars > 100000)
         reason = "lookbackBars must be between 1 and 100000";
      else if(maxRecordsPerConcept < 1 || maxRecordsPerConcept > 100000)
         reason = "maxRecordsPerConcept must be between 1 and 100000";
      else if(swingStrength < 1 || swingStrength > 5000)
         reason = "swingStrength must be between 1 and 5000";
      else if(displacementBaseline < 1 || displacementBaseline > 5000)
         reason = "displacementBaseline must be between 1 and 5000";
      else if(!MathIsValidNumber(displacementMultiplier) || displacementMultiplier <= 0)
         reason = "displacementMultiplier must be finite and positive";
      else if(!MathIsValidNumber(displacementBodyFraction) || displacementBodyFraction <= 0 || displacementBodyFraction > 1)
         reason = "displacementBodyFraction must be in (0, 1]";
      else if(!MathIsValidNumber(minFvgPips) || minFvgPips < 0)
         reason = "minFvgPips must be finite and nonnegative";
      else if(maxZoneAge < 1 || maxZoneAge > 10000)
         reason = "maxZoneAge must be between 1 and 10000";
      else if(bprMaxSeparation < 1 || bprMaxSeparation > 10000)
         reason = "bprMaxSeparation must be between 1 and 10000";
      else if(po3ExpiryBars < 1 || po3ExpiryBars > 10000)
         reason = "po3ExpiryBars must be between 1 and 10000";
      else if(smtRadius < 0 || smtRadius > 5000)
         reason = "smtRadius must be between 0 and 5000";
      else if(enableSMT && smtSymbol == "")
         reason = "SMT requires a comparison symbol";
      if(reason != "") return false;
      for(int i = 0; i < 3; i++)
        {
         if(sessions[i].name == "" || sessions[i].startMinute < 0 || sessions[i].startMinute > 1439 ||
            sessions[i].endMinute < 0 || sessions[i].endMinute > 1439 ||
            sessions[i].startMinute == sessions[i].endMinute)
           {
            reason = "sessions require a name and distinct minute values in [0, 1439]";
            return false;
           }
         for(int j = 0; j < i; j++)
            if(sessions[j].name == sessions[i].name)
              {
               reason = "session names must be unique";
               return false;
              }
        }
      return true;
     }
  };

struct SmcRecord
  {
   string id;
   ENUM_SMC_CONCEPT concept;
   datetime sourceTime;
   datetime confirmedAt;
   datetime updatedAt;
   int direction;
   double lower;
   double upper;
   string state;
   bool active;
   string relatedId;
   string secondaryId;
   datetime periodStart;
   datetime periodEnd;
   double referencePrice;
   double comparisonPrice;
   double strength;
   string reason;

   void Init()
     {
      id = "";
      concept = ICT_SWING_HIGH;
      sourceTime = 0;
      confirmedAt = 0;
      updatedAt = 0;
      direction = 0;
      lower = 0;
      upper = 0;
      state = "FRESH";
      active = true;
      relatedId = "";
      secondaryId = "";
      periodStart = 0;
      periodEnd = 0;
      referencePrice = 0;
      comparisonPrice = 0;
      strength = 0;
      reason = "";
     }
  };

struct SmcModuleStatus
  {
   ENUM_SMC_CONCEPT concept;
   ENUM_SMC_STATUS status;
   datetime asOf;
   bool truncated;
   string message;

   void Init()
     {
      concept = ICT_SWING_HIGH;
      status = SMC_STATUS_NOT_READY;
      asOf = 0;
      truncated = false;
      message = "";
     }
  };

struct SmcSnapshot
  {
   string symbol;
   ENUM_TIMEFRAMES timeframe;
   string timeBasis;
   datetime asOf;
   ENUM_SMC_STATUS status;
   string message;
   SmcConfig config;
   SmcModuleStatus modules[];
   SmcRecord records[];

   void Reset()
     {
      symbol = "";
      timeframe = PERIOD_CURRENT;
      timeBasis = "broker";
      asOf = 0;
      status = SMC_STATUS_NOT_READY;
      message = "";
      config.SetDefaults();
      ArrayResize(modules, 0);
      ArrayResize(records, 0);
     }
  };

// Length-prefix variable strings so unusual broker symbols cannot collide.
// Identity excludes mutable state and array position.
string SmcRecordId(const ENUM_SMC_CONCEPT concept, const string symbol,
                   const ENUM_TIMEFRAMES timeframe, const datetime sourceTime,
                   const int direction, const string parent = "")
  {
   return SmcConceptName(concept) + "|" + IntegerToString(StringLen(symbol)) + ":" + symbol +
          "|" + IntegerToString((int)timeframe) + "|" + IntegerToString((long)sourceTime) +
          "|" + IntegerToString(direction) + "|" + IntegerToString(StringLen(parent)) + ":" + parent;
  }

// Upsert by ID: repeating the same evaluation cannot duplicate a record.
bool SmcAppendRecord(SmcSnapshot &snapshot, const SmcRecord &record)
  {
   if(record.id == "" || record.direction < -1 || record.direction > 1 ||
      !MathIsValidNumber(record.lower) || !MathIsValidNumber(record.upper) || record.lower > record.upper ||
      !MathIsValidNumber(record.referencePrice) || !MathIsValidNumber(record.comparisonPrice) ||
      !MathIsValidNumber(record.strength)) return false;
   int count = ArraySize(snapshot.records);
   for(int i = 0; i < count; i++)
      if(snapshot.records[i].id == record.id)
        {
         snapshot.records[i] = record;
         return true;
        }
   if(ArrayResize(snapshot.records, count + 1) != count + 1) return false;
   snapshot.records[count] = record;
   return true;
  }

bool SmcSetModuleStatus(SmcSnapshot &snapshot, const ENUM_SMC_CONCEPT concept,
                        const ENUM_SMC_STATUS status, const datetime asOf = 0,
                        const bool truncated = false, const string message = "")
  {
   int count = ArraySize(snapshot.modules);
   int index = -1;
   for(int i = 0; i < count; i++)
      if(snapshot.modules[i].concept == concept) { index = i; break; }
   if(index < 0)
     {
      if(ArrayResize(snapshot.modules, count + 1) != count + 1) return false;
      index = count;
     }
   snapshot.modules[index].concept = concept;
   snapshot.modules[index].status = status;
   snapshot.modules[index].asOf = asOf;
   snapshot.modules[index].truncated = truncated;
   snapshot.modules[index].message = message;
   return true;
  }

#endif // __SMC_SNAPSHOT_MQH__
