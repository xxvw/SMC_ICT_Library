// Broker-calendar reference levels, evaluated from chronological price arrays.
#ifndef __SMC_REFERENCE_LEVELS_MQH__
#define __SMC_REFERENCE_LEVELS_MQH__

#include "../Core/SmcSnapshot.mqh"

bool SmcIsReferenceLevelConcept(const ENUM_SMC_CONCEPT concept)
  {
   return concept == ICT_PREVIOUS_DAY_HIGH || concept == ICT_PREVIOUS_DAY_LOW ||
          concept == ICT_PREVIOUS_WEEK_HIGH || concept == ICT_PREVIOUS_WEEK_LOW;
  }

// A caller may reuse its snapshot. Old reference levels must never survive a
// missing-history result or remain alongside the newly selected prior period.
void SmcClearReferenceLevels(SmcSnapshot &snapshot)
  {
   int keep = 0;
   const int count = ArraySize(snapshot.records);
   for(int i = 0; i < count; i++)
      if(!SmcIsReferenceLevelConcept(snapshot.records[i].concept))
        {
         if(keep != i) snapshot.records[keep] = snapshot.records[i];
         keep++;
        }
   ArrayResize(snapshot.records, keep);
  }

void SmcReferencePairStatus(SmcSnapshot &snapshot,
                            const ENUM_SMC_CONCEPT highConcept,
                            const ENUM_SMC_CONCEPT lowConcept,
                            const ENUM_SMC_STATUS status,
                            const datetime asOf, const string message)
  {
   SmcSetModuleStatus(snapshot, highConcept, status, asOf, false, message);
   SmcSetModuleStatus(snapshot, lowConcept, status, asOf, false, message);
  }

// The successor opening is evidence that a broker period is complete. Using
// its timestamp (never its OHLC) handles irregular broker weeks and holidays
// without inventing UTC boundaries or reading a still-forming period's range.
void SmcReferencePeriod(const MqlRates &periods[], const datetime asOf,
                        const int periodSeconds,
                        const string symbol, const ENUM_TIMEFRAMES timeframe,
                        const ENUM_SMC_CONCEPT highConcept,
                        const ENUM_SMC_CONCEPT lowConcept,
                        SmcSnapshot &snapshot)
  {
   const int count = ArraySize(periods);
   int completed = -1;
   int current = -1;
   for(int i = 0; i < count; i++)
     {
      if(periods[i].time <= 0 || (i > 0 && periods[i].time <= periods[i - 1].time))
        {
         SmcReferencePairStatus(snapshot, highConcept, lowConcept, SMC_STATUS_ERROR,
                                asOf, "Period history must be strictly chronological");
         return;
        }
      if(i > 0 && periods[i].time <= asOf) completed = i - 1;
      if(periods[i].time <= asOf) current = i;
     }
   // A stale period array may still contain a completed pair. Require the
   // latest usable period to cover the evaluation time before exposing it.
   // The inclusive end keeps a Friday bar closing on Saturday valid without
   // requiring a nonexistent Saturday D1 candle. Coarse primary timeframes
   // must still supply period history through their actual closing boundary.
   if(current < 0 || asOf > periods[current].time + periodSeconds)
     {
      SmcReferencePairStatus(snapshot, highConcept, lowConcept, SMC_STATUS_NOT_READY,
                             asOf, "Period history does not cover the evaluation time");
      return;
     }
   if(completed < 0)
     {
      SmcReferencePairStatus(snapshot, highConcept, lowConcept, SMC_STATUS_NOT_READY,
                             asOf, "A completed period and its successor opening are required");
      return;
     }
   if(!MathIsValidNumber(periods[completed].high) ||
      !MathIsValidNumber(periods[completed].low) ||
      periods[completed].high < periods[completed].low)
     {
      SmcReferencePairStatus(snapshot, highConcept, lowConcept, SMC_STATUS_ERROR,
                             asOf, "Completed period has an invalid price range");
      return;
     }

   const datetime start = periods[completed].time;
   const datetime end = periods[completed + 1].time;
   SmcRecord record;
   record.Init();
   record.concept = highConcept;
   record.sourceTime = start;
   record.confirmedAt = end;
   record.updatedAt = end;
   record.periodStart = start;
   record.periodEnd = end;
   record.state = "COMPLETED";
   record.direction = 0; // A reference price is not a directional trade signal.
   record.lower = periods[completed].high;
   record.upper = record.lower;
   record.referencePrice = record.lower;
   record.id = SmcRecordId(record.concept, symbol, timeframe, start, record.direction);
   bool appended = SmcAppendRecord(snapshot, record);

   record.concept = lowConcept;
   record.lower = periods[completed].low;
   record.upper = record.lower;
   record.referencePrice = record.lower;
   record.id = SmcRecordId(record.concept, symbol, timeframe, start, record.direction);
   appended = SmcAppendRecord(snapshot, record) && appended;
   SmcReferencePairStatus(snapshot, highConcept, lowConcept,
                          appended ? SMC_STATUS_READY : SMC_STATUS_ERROR,
                          asOf, appended ? "" : "Cannot append reference-level records");
  }

// rates contains only closed primary bars, oldest first. daily/weekly contain
// period bars oldest first and may include the currently forming period. No
// wall-clock time is consulted, so replaying the same inputs is deterministic.
void SmcDetectReferenceLevels(const MqlRates &rates[], const MqlRates &daily[],
                              const MqlRates &weekly[], const SmcConfig &config,
                              const string symbol, const ENUM_TIMEFRAMES tf,
                              const double tick, SmcSnapshot &snapshot)
  {
   SmcClearReferenceLevels(snapshot);
   const int count = ArraySize(rates);
   const int seconds = PeriodSeconds(tf);
   datetime asOf = count > 0 ? SmcBarClosedAt(rates[count - 1].time, tf) : 0;
   ENUM_SMC_STATUS unavailable = SMC_STATUS_READY;
   string message = "";
   if(!config.enableCalendar)
     {
      unavailable = SMC_STATUS_DISABLED;
      message = "Calendar concepts are disabled";
     }
   else if(count == 0)
     {
      unavailable = SMC_STATUS_NOT_READY;
      message = "Closed primary-bar history is required";
     }
   else if(seconds <= 0)
     {
      unavailable = SMC_STATUS_ERROR;
      message = "Primary timeframe has no duration";
     }
   else
      for(int i = 0; i < count; i++)
         if(rates[i].time <= 0 || (i > 0 && rates[i].time <= rates[i - 1].time))
           {
            unavailable = SMC_STATUS_ERROR;
            message = "Primary history must be strictly chronological";
            break;
           }
   if(unavailable != SMC_STATUS_READY)
     {
      SmcReferencePairStatus(snapshot, ICT_PREVIOUS_DAY_HIGH, ICT_PREVIOUS_DAY_LOW,
                             unavailable, asOf, message);
      SmcReferencePairStatus(snapshot, ICT_PREVIOUS_WEEK_HIGH, ICT_PREVIOUS_WEEK_LOW,
                             unavailable, asOf, message);
      return;
     }

   SmcReferencePeriod(daily, asOf, 86400, symbol, tf,
                      ICT_PREVIOUS_DAY_HIGH, ICT_PREVIOUS_DAY_LOW, snapshot);
   SmcReferencePeriod(weekly, asOf, 604800, symbol, tf,
                      ICT_PREVIOUS_WEEK_HIGH, ICT_PREVIOUS_WEEK_LOW, snapshot);
  }

#endif // __SMC_REFERENCE_LEVELS_MQH__
