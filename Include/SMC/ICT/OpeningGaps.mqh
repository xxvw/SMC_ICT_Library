// Broker daily/weekly opening gaps evaluated from closed primary candles.
#ifndef __SMC_ICT_OPENING_GAPS_MQH__
#define __SMC_ICT_OPENING_GAPS_MQH__

#include "../Core/SmcSnapshot.mqh"

void SmcClearOpeningGapRecords(SmcSnapshot &snapshot, const ENUM_SMC_CONCEPT concept)
  {
   int keep = 0;
   for(int i = 0; i < ArraySize(snapshot.records); i++)
      if(snapshot.records[i].concept != concept)
        {
         if(keep != i) snapshot.records[keep] = snapshot.records[i];
         keep++;
        }
   ArrayResize(snapshot.records, keep);
  }

// The inputs are chronological. Period arrays include the period containing
// the last closed primary bar and a predecessor before the first primary bar.
// Only a period's opening price and its COMPLETED predecessor's close are read;
// its current high/low/close can contain future data without affecting results.
bool SmcOpeningGapInputs(const MqlRates &rates[], const MqlRates &periods[],
                         const int periodSeconds, string &reason)
  {
   int size = ArraySize(rates);
   int count = ArraySize(periods);
   if(size == 0 || count < 2)
     {
      reason = "Closed primary bars and at least two broker periods are required";
      return false;
     }
   for(int i = 0; i < size; i++)
     {
      if(rates[i].time <= 0 || (i > 0 && rates[i].time <= rates[i - 1].time) ||
         !MathIsValidNumber(rates[i].high) || !MathIsValidNumber(rates[i].low) ||
         rates[i].high < rates[i].low)
        {
         reason = "Primary bars must have chronological times and finite ranges";
         return false;
        }
     }
   // Inspect only times for future periods. Never use a future period's close
   // or aggregate range to establish either the gap or its filled state.
   for(int i = 0; i < count; i++)
      if(periods[i].time <= 0 || (i > 0 && periods[i].time <= periods[i - 1].time))
        {
         reason = "Broker periods must have strictly chronological times";
         return false;
        }
   int period = 0;
   for(int i = 0; i < size; i++)
     {
      while(period + 1 < count && periods[period + 1].time <= rates[i].time)
         period++;
      if(period < 1 || rates[i].time < periods[period].time ||
         rates[i].time >= periods[period].time + periodSeconds)
        {
         reason = "Broker period history does not cover every closed primary bar and its predecessor";
         return false;
        }
      if(!MathIsValidNumber(periods[period].open) ||
         !MathIsValidNumber(periods[period - 1].close))
        {
         reason = "Broker opening prices and completed preceding closes must be finite";
         return false;
        }
     }
   reason = "";
   return true;
  }

void SmcDetectOpeningGapPeriod(const MqlRates &rates[], const MqlRates &periods[],
                               const ENUM_SMC_CONCEPT concept,
                               const int periodSeconds,
                               const string symbol, const ENUM_TIMEFRAMES timeframe,
                               const double tick, SmcSnapshot &snapshot,
                               const ENUM_TIMEFRAMES replayTimeframe = PERIOD_CURRENT,
                               const datetime evaluatedAt = 0)
  {
   SmcClearOpeningGapRecords(snapshot, concept);
   int size = ArraySize(rates);
   ENUM_TIMEFRAMES candleTimeframe = replayTimeframe == PERIOD_CURRENT ? timeframe : replayTimeframe;
   int seconds = PeriodSeconds(candleTimeframe);
   datetime asOf = evaluatedAt > 0 ? evaluatedAt :
                   (size > 0 ? SmcBarClosedAt(rates[size - 1].time, candleTimeframe) : 0);
   string reason;
   if(!SmcOpeningGapInputs(rates, periods, periodSeconds, reason))
     {
      SmcSetModuleStatus(snapshot, concept, SMC_STATUS_NOT_READY, asOf, false, reason);
      return;
     }
   if(seconds <= 0 || !MathIsValidNumber(tick) || tick <= 0)
     {
      SmcSetModuleStatus(snapshot, concept, SMC_STATUS_ERROR, asOf, false,
                         "A positive tick size and concrete primary timeframe are required");
      return;
     }
   int primary = 0;
   for(int period = 1; period < ArraySize(periods); period++)
     {
      datetime start = periods[period].time;
      if(start > rates[size - 1].time) break;
      // A source before the supplied primary history cannot be reconstructed
      // causally: its earliest confirmation and fills might be missing.
      if(start < rates[0].time) continue;
      while(primary < size && rates[primary].time < start) primary++;
      if(primary == size) break;
      datetime end = start + periodSeconds;
      if(rates[primary].time >= end) continue; // no primary bar in this period
      if(period + 1 < ArraySize(periods) &&
         rates[primary].time >= periods[period + 1].time) continue;
      double previousClose = periods[period - 1].close;
      double opening = periods[period].open;
      double distance = opening - previousClose;
      // Tiny floating-point error must not discard a one-tick difference.
      if(MathAbs(distance) + tick * 1e-8 < tick) continue;

      SmcRecord gap;
      gap.Init();
      gap.concept = concept;
      gap.sourceTime = start;
      gap.periodStart = start;
      gap.periodEnd = end;
      gap.confirmedAt = SmcBarClosedAt(rates[primary].time, candleTimeframe);
      gap.updatedAt = gap.confirmedAt;
      gap.direction = distance > 0 ? 1 : -1;
      gap.lower = MathMin(previousClose, opening);
      gap.upper = MathMax(previousClose, opening);
      gap.referencePrice = previousClose;
      gap.comparisonPrice = opening;
      gap.state = "ACTIVE";
      gap.id = SmcRecordId(concept, symbol, timeframe, start, gap.direction);
      gap.relatedId = "BROKER_PERIOD|" + IntegerToString(periodSeconds) + "|" +
                      IntegerToString((long)periods[period - 1].time);

      // The confirming candle is closed and may itself fill the gap. Later
      // candles update only lifecycle fields; identity and confirmation stay.
      for(int bar = primary; bar < size; bar++)
         if((gap.direction > 0 && rates[bar].low <= previousClose) ||
            (gap.direction < 0 && rates[bar].high >= previousClose))
           {
            gap.state = "FILLED";
            gap.active = false;
            gap.updatedAt = SmcBarClosedAt(rates[bar].time, candleTimeframe);
            gap.reason = "The previous broker period close was reached";
            break;
           }
      if(!SmcAppendRecord(snapshot, gap))
        {
         SmcSetModuleStatus(snapshot, concept, SMC_STATUS_ERROR, asOf, false,
                            "Unable to append broker opening gap");
         return;
        }
     }
   SmcSetModuleStatus(snapshot, concept, SMC_STATUS_READY, asOf);
  }

// A weekly/monthly primary candle cannot place intraperiod daily/weekly gaps
// or their fills in causal order. Reconstruct those paths from closed D1 bars.
// Current/future D1 aggregate prices are never read; their opening timestamps
// can establish that the supplied history covers the evaluation boundary.
bool SmcOpeningGapDailyReplay(const MqlRates &primary[],const MqlRates &daily[],
                              const ENUM_TIMEFRAMES timeframe,MqlRates &replay[],string &reason)
  {
   ArrayResize(replay,0);
   int size=ArraySize(primary),count=ArraySize(daily);
   if(size==0 || count<2)
     {
      reason="Coarse primary timeframes require covered D1 history and a predecessor";
      return false;
     }
   datetime asOf=SmcBarClosedAt(primary[size-1].time,timeframe);
   for(int i=0;i<size;i++)
      if(primary[i].time<=0 || (i>0 && primary[i].time<=primary[i-1].time))
        {
         reason="Primary replay history must have strictly chronological times";
         return false;
        }
   int latest=-1;
   for(int i=0;i<count;i++)
     {
      if(daily[i].time<=0 || (i>0 && daily[i].time<=daily[i-1].time))
        {
         reason="Daily replay history must have strictly chronological times";
         return false;
        }
      if(daily[i].time<=asOf) latest=i;
     }
   // Inclusive closure admits a final Friday candle at Saturday 00:00. A
   // longer unproven interval remains NOT_READY rather than assuming holidays.
   if(asOf<=0 || latest<0 || daily[0].time>primary[0].time ||
      asOf>SmcBarClosedAt(daily[latest].time,PERIOD_D1))
     {
      reason="Daily replay history does not cover the complete primary evaluation interval";
      return false;
     }
   for(int i=0;i<count;i++)
     {
      if(daily[i].time<primary[0].time || SmcBarClosedAt(daily[i].time,PERIOD_D1)>asOf) continue;
      int index=ArraySize(replay);
      if(ArrayResize(replay,index+1)!=index+1)
        {
         reason="Unable to allocate closed daily replay history";
         return false;
        }
      replay[index]=daily[i];
     }
   if(ArraySize(replay)==0)
     {
      reason="No closed daily candles are available inside the primary evaluation interval";
      return false;
     }
   reason="";
   return true;
  }

// Replace only these two concepts on every evaluation, including failure and
// disabling, so a standalone caller can never mistake stale gaps for results.
// The caller applies snapshot-wide lookback and per-concept record caps.
void SmcDetectOpeningGaps(const MqlRates &rates[], const MqlRates &daily[],
                          const MqlRates &weekly[], const SmcConfig &config,
                          const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const double tick, SmcSnapshot &snapshot)
  {
   datetime asOf = ArraySize(rates) > 0 ?
                   SmcBarClosedAt(rates[ArraySize(rates) - 1].time, timeframe) : 0;
   if(!config.enableCalendar)
     {
      SmcClearOpeningGapRecords(snapshot, ICT_DAILY_GAP);
      SmcClearOpeningGapRecords(snapshot, ICT_WEEKLY_GAP);
      SmcSetModuleStatus(snapshot, ICT_DAILY_GAP, SMC_STATUS_DISABLED, asOf);
      SmcSetModuleStatus(snapshot, ICT_WEEKLY_GAP, SMC_STATUS_DISABLED, asOf);
      return;
     }
   bool coarseDaily=PeriodSeconds(timeframe)>86400;
   bool coarseWeekly=PeriodSeconds(timeframe)>604800;
   MqlRates replay[];
   string reason;
   bool replayReady=true;
   if(coarseDaily || coarseWeekly)
      replayReady=SmcOpeningGapDailyReplay(rates,daily,timeframe,replay,reason);
   if(!coarseDaily)
      SmcDetectOpeningGapPeriod(rates,daily,ICT_DAILY_GAP,86400,symbol,timeframe,tick,snapshot);
   else if(replayReady)
      SmcDetectOpeningGapPeriod(replay,daily,ICT_DAILY_GAP,86400,symbol,timeframe,tick,snapshot,PERIOD_D1,asOf);
   else
     {
      SmcClearOpeningGapRecords(snapshot,ICT_DAILY_GAP);
      SmcSetModuleStatus(snapshot,ICT_DAILY_GAP,SMC_STATUS_NOT_READY,asOf,false,reason);
     }
   if(!coarseWeekly)
      SmcDetectOpeningGapPeriod(rates,weekly,ICT_WEEKLY_GAP,604800,symbol,timeframe,tick,snapshot);
   else if(replayReady)
      SmcDetectOpeningGapPeriod(replay,weekly,ICT_WEEKLY_GAP,604800,symbol,timeframe,tick,snapshot,PERIOD_D1,asOf);
   else
     {
      SmcClearOpeningGapRecords(snapshot,ICT_WEEKLY_GAP);
      SmcSetModuleStatus(snapshot,ICT_WEEKLY_GAP,SMC_STATUS_NOT_READY,asOf,false,reason);
     }
  }

#endif // __SMC_ICT_OPENING_GAPS_MQH__
