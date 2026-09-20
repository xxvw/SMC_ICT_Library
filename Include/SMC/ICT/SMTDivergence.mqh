// Positive-correlation SMT: strict primary swings, exact companion timestamps.
#ifndef __SMC_ICT_SMT_DIVERGENCE_MQH__
#define __SMC_ICT_SMT_DIVERGENCE_MQH__

#include "../Core/SmcSnapshot.mqh"

void SmcClearSMT(SmcSnapshot &snapshot)
  {
   int write = 0;
   for(int i = 0; i < ArraySize(snapshot.records); i++)
      if(snapshot.records[i].concept != ICT_SMT)
         snapshot.records[write++] = snapshot.records[i];
   ArrayResize(snapshot.records, write);
  }

bool SmcSMTStrictSwing(const MqlRates &rates[], const int pivot,
                       const int strength, const bool highSide)
  {
   if(strength < 1 || pivot < strength || pivot + strength >= ArraySize(rates))
      return false;
   for(int distance = 1; distance <= strength; distance++)
     {
      if(highSide && (rates[pivot].high <= rates[pivot-distance].high ||
                      rates[pivot].high <= rates[pivot+distance].high)) return false;
      if(!highSide && (rates[pivot].low >= rates[pivot-distance].low ||
                       rates[pivot].low >= rates[pivot+distance].low)) return false;
     }
   return true;
  }

double SmcSMTCompanionExtreme(const MqlRates &companion[], const int &matches[],
                               const int pivot, const int radius, const bool highSide)
  {
   double result = highSide ? companion[matches[pivot-radius]].high :
                              companion[matches[pivot-radius]].low;
   for(int i = pivot-radius+1; i <= pivot+radius; i++)
      result = highSide ? MathMax(result, companion[matches[i]].high) :
                          MathMin(result, companion[matches[i]].low);
   return result;
  }

// Decimal broker prices can subtract to infinitesimally less than one tick.
bool SmcSMTReachesTick(const double change, const double tick)
  {
   return change + tick*1e-8 >= tick;
  }

bool SmcSMTHistoryValid(const MqlRates &rates[])
  {
   if(ArrayGetAsSeries(rates)) return false;
   for(int i = 0; i < ArraySize(rates); i++)
     {
      if(rates[i].time <= 0 || (i > 0 && rates[i].time <= rates[i-1].time) ||
         !MathIsValidNumber(rates[i].open) || !MathIsValidNumber(rates[i].high) ||
         !MathIsValidNumber(rates[i].low) || !MathIsValidNumber(rates[i].close) ||
         rates[i].high < MathMax(rates[i].open, rates[i].close) ||
         rates[i].low > MathMin(rates[i].open, rates[i].close) || rates[i].low > rates[i].high)
         return false;
     }
   return true;
  }

// All bars are chronological and closed. The snapshot watermark is the close
// time of the primary evaluation bar. Bars after that watermark are ignored.
// Incomplete alignment publishes no SMT events, including those from a prior
// invocation: callers must never mistake incomplete history for no divergence.
void SmcDetectSMT(const MqlRates &rates[], const MqlRates &companion[],
                  const SmcConfig &config, const string symbol,
                  const ENUM_TIMEFRAMES tf, const double tick,
                  const double companionTick, SmcSnapshot &snapshot)
  {
   SmcClearSMT(snapshot);
   if(!config.IsSMTEnabled())
     {
      SmcSetModuleStatus(snapshot, ICT_SMT, SMC_STATUS_DISABLED, snapshot.asOf,
                         false, "Set smtSymbol to enable positive-correlation SMT");
      return;
     }
   if(config.smtSymbol == "")
     {
      SmcSetModuleStatus(snapshot, ICT_SMT, SMC_STATUS_NOT_READY, 0, false,
                         "SMT requires an explicit comparison symbol");
      return;
     }
   int seconds = PeriodSeconds(tf);
   string reason;
   if(!config.Validate(reason) || seconds <= 0 || !MathIsValidNumber(tick) || tick <= 0)
     {
      SmcSetModuleStatus(snapshot, ICT_SMT, SMC_STATUS_ERROR, 0, false,
                         reason != "" ? reason : "Invalid SMT timeframe or tick size");
      return;
     }
   if(snapshot.asOf <= 0 || ArraySize(rates) == 0 || ArraySize(companion) == 0)
     {
      SmcSetModuleStatus(snapshot, ICT_SMT, SMC_STATUS_NOT_READY, 0, false,
                         "SMT requires closed history for both symbols");
      return;
     }
   if(!MathIsValidNumber(companionTick) || companionTick <= 0)
     {
      SmcSetModuleStatus(snapshot, ICT_SMT, SMC_STATUS_ERROR, 0, false,
                         "Invalid comparison tick size for available history");
      return;
     }
   if(!SmcSMTHistoryValid(rates) || !SmcSMTHistoryValid(companion))
     {
      SmcSetModuleStatus(snapshot, ICT_SMT, SMC_STATUS_ERROR, 0, false,
                         "SMT requires chronological finite OHLC bars with positive timestamps");
      return;
     }

   int count = 0, comparisonCount = 0;
   for(int i = 0; i < ArraySize(rates); i++)
      if(SmcBarClosedAt(rates[i].time, tf) <= snapshot.asOf) count++;
   for(int i = 0; i < ArraySize(companion); i++)
      if(SmcBarClosedAt(companion[i].time, tf) <= snapshot.asOf) comparisonCount++;
   int delay = MathMax(config.swingStrength, config.smtRadius);
   if(count < 2*delay+1 || comparisonCount == 0)
     {
      SmcSetModuleStatus(snapshot, ICT_SMT, SMC_STATUS_NOT_READY, 0, false,
                         "SMT needs enough closed bars to confirm a pivot neighborhood");
      return;
     }
   datetime watermark = MathMin(snapshot.asOf,
                        MathMin(SmcBarClosedAt(rates[count-1].time, tf),
                                SmcBarClosedAt(companion[comparisonCount-1].time, tf)));
   if(watermark < snapshot.asOf)
     {
      SmcSetModuleStatus(snapshot, ICT_SMT, SMC_STATUS_NOT_READY, watermark,
                         false, "Comparison history has not reached the evaluation watermark");
      return;
     }

   // Exact matching permits extra companion bars. Mark missing timestamps;
   // only a gap in a required pivot neighborhood makes the result incomplete.
   // Never substitute a neighboring quote or a bar after the watermark.
   int matches[];
   if(ArrayResize(matches, count) != count)
     {
      SmcSetModuleStatus(snapshot, ICT_SMT, SMC_STATUS_ERROR, watermark, false,
                         "Cannot allocate SMT alignment buffer");
      return;
     }
   int comparisonIndex = 0;
   for(int i = 0; i < count; i++)
     {
      while(comparisonIndex < comparisonCount && companion[comparisonIndex].time < rates[i].time)
         comparisonIndex++;
      matches[i] = comparisonIndex < comparisonCount && companion[comparisonIndex].time == rates[i].time ?
                   comparisonIndex : -1;
     }

   int previousHigh = -1, previousLow = -1;
   int horizon = MathMax(0, count-config.lookbackBars);
   for(int pivot = config.swingStrength; pivot + delay < count; pivot++)
     {
      for(int side = 0; side < 2; side++)
        {
         bool highSide = side == 0;
         if(!SmcSMTStrictSwing(rates, pivot, config.swingStrength, highSide)) continue;
         int previous = highSide ? previousHigh : previousLow;
         if(highSide) previousHigh = pivot;
         else previousLow = pivot;
         // Bound the previous-pivot dependency by pivot-to-pivot bar distance.
         if(previous < 0 || pivot+delay < horizon || pivot-previous > config.lookbackBars) continue;

         double currentPrice = highSide ? rates[pivot].high : rates[pivot].low;
         double previousPrice = highSide ? rates[previous].high : rates[previous].low;
         double primaryChange = highSide ? currentPrice-previousPrice : previousPrice-currentPrice;
         if(!SmcSMTReachesTick(primaryChange, tick)) continue;
         if(previous-config.smtRadius < 0)
           {
            SmcClearSMT(snapshot);
            SmcSetModuleStatus(snapshot, ICT_SMT, SMC_STATUS_NOT_READY, watermark, false,
                               "SMT needs earlier history for the previous pivot neighborhood");
            return;
           }
         for(int offset = -config.smtRadius; offset <= config.smtRadius; offset++)
           {
            int missing = matches[previous+offset] < 0 ? previous+offset :
                          matches[pivot+offset] < 0 ? pivot+offset : -1;
            if(missing >= 0)
              {
               SmcClearSMT(snapshot);
               SmcSetModuleStatus(snapshot, ICT_SMT, SMC_STATUS_NOT_READY, watermark, false,
                                  "Missing exact comparison timestamp: " + TimeToString(rates[missing].time, TIME_DATE|TIME_SECONDS));
               return;
              }
           }
         double currentComparison = SmcSMTCompanionExtreme(companion, matches, pivot, config.smtRadius, highSide);
         double previousComparison = SmcSMTCompanionExtreme(companion, matches, previous, config.smtRadius, highSide);
         double comparisonChange = highSide ? currentComparison-previousComparison : previousComparison-currentComparison;
         if(SmcSMTReachesTick(comparisonChange, companionTick)) continue;

         SmcRecord record;
         record.Init();
         record.concept = ICT_SMT;
         record.direction = highSide ? -1 : 1;
         record.sourceTime = rates[pivot].time;
         record.confirmedAt = SmcBarClosedAt(rates[pivot+delay].time, tf);
         record.updatedAt = record.confirmedAt;
         record.lower = MathMin(previousPrice, currentPrice);
         record.upper = MathMax(previousPrice, currentPrice);
         record.state = "CONFIRMED";
         record.relatedId = SmcRecordId(highSide ? ICT_SWING_HIGH : ICT_SWING_LOW,
                                        symbol, tf, rates[previous].time, highSide ? -1 : 1);
         record.secondaryId = SmcRecordId(highSide ? ICT_SWING_HIGH : ICT_SWING_LOW,
                                          symbol, tf, rates[pivot].time, highSide ? -1 : 1);
         string comparisonIdentity = SmcRecordId(ICT_SMT, config.smtSymbol, tf,
                                                  rates[previous].time, record.direction, record.relatedId);
         record.id = SmcRecordId(ICT_SMT, symbol, tf, record.sourceTime, record.direction, comparisonIdentity);
         record.referencePrice = previousComparison;
         record.comparisonPrice = currentComparison;
         record.strength = primaryChange / tick;
         record.reason = "Positive-correlation divergence versus " + config.smtSymbol;
         if(!SmcAppendRecord(snapshot, record))
           {
            SmcClearSMT(snapshot);
            SmcSetModuleStatus(snapshot, ICT_SMT, SMC_STATUS_ERROR, watermark, false,
                               "Cannot append SMT result");
            return;
           }
        }
     }
   SmcSetModuleStatus(snapshot, ICT_SMT, SMC_STATUS_READY, watermark);
  }

#endif // __SMC_ICT_SMT_DIVERGENCE_MQH__
