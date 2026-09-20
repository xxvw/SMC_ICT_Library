#ifndef __SMC_ICT_MARKET_STRUCTURE_SHIFT_MQH__
#define __SMC_ICT_MARKET_STRUCTURE_SHIFT_MQH__

#include "Displacement.mqh"

// Replay causally: a pivot joins the known structure only at the close of its
// right confirmation window. A mixed pair does not erase a known direction,
// but the evidence establishing that direction expires after lookbackBars.
void SmcDetectMSS(const MqlRates &rates[], const SmcConfig &config,
                  const string symbol, const ENUM_TIMEFRAMES timeframe,
                  const double tick, SmcSnapshot &snapshot)
  {
   SmcClearPatternRecords(snapshot, ICT_MSS);
   if(!config.enableMSS)
     {
      SmcSetModuleStatus(snapshot, ICT_MSS, SMC_STATUS_DISABLED, snapshot.asOf);
      return;
     }
   if(!SmcPatternInputsValid(rates, config, timeframe, tick))
     {
      SmcSetModuleStatus(snapshot, ICT_MSS, SMC_STATUS_ERROR, snapshot.asOf,
                         false, "Invalid configuration or chronological OHLC input");
      return;
     }
   int count = ArraySize(rates);
   if(count <= config.displacementBaseline || count < 2 * config.swingStrength + 1)
     {
      SmcSetModuleStatus(snapshot, ICT_MSS, SMC_STATUS_NOT_READY, snapshot.asOf,
                         false, "Insufficient baseline or swing confirmation history");
      return;
     }
   int previousHigh = -1, lastHigh = -1, previousLow = -1, lastLow = -1;
   int trend = 0, evidenceStart = -1, consumedHigh = -1, consumedLow = -1;
   int firstReported = MathMax(0, count - config.lookbackBars);
   for(int i = 0; i < count; i++)
     {
      if(evidenceStart >= 0 && i - evidenceStart > config.lookbackBars) trend = 0;
      int target = trend == 1 ? lastLow : lastHigh;
      bool bullish = trend == -1;
      if(trend != 0 && target >= 0 && i > 0 && i - target <= config.lookbackBars &&
         SmcIsDisplacement(rates, i, config))
        {
         double level = bullish ? rates[target].high : rates[target].low;
         // A decimal quote exactly one tick beyond a level can subtract to
         // slightly less than that tick in binary floating-point arithmetic.
         double distance = bullish ? rates[i].close - level : level - rates[i].close;
         bool reached = distance + tick * 1e-8 >= tick;
         bool crossed = reached && (bullish ? rates[i-1].close <= level
                                             : rates[i-1].close >= level);
         bool matchingBody = bullish ? rates[i].close > rates[i].open
                                     : rates[i].close < rates[i].open;
         bool consumed = bullish ? consumedHigh == target : consumedLow == target;
         if(crossed && matchingBody && !consumed)
           {
            // Consume during warmup too, so changing the report horizon cannot
            // manufacture another event when price recrosses an old target.
            if(bullish) consumedHigh = target;
            else consumedLow = target;
            if(i >= firstReported)
              {
               SmcRecord record;
               record.Init();
               record.concept = ICT_MSS;
               record.sourceTime = rates[target].time;
               record.confirmedAt = SmcBarClosedAt(rates[i].time, timeframe);
               record.updatedAt = record.confirmedAt;
               record.direction = bullish ? 1 : -1;
               record.lower = MathMin(level, rates[i].close);
               record.upper = MathMax(level, rates[i].close);
               record.state = "CONFIRMED";
               record.referencePrice = level;
               record.comparisonPrice = rates[i].close;
               record.relatedId = SmcRecordId(bullish ? ICT_SWING_HIGH : ICT_SWING_LOW,
                                              symbol, timeframe, rates[target].time,
                                              bullish ? -1 : 1);
               record.secondaryId = SmcRecordId(ICT_DISPLACEMENT, symbol, timeframe,
                                                rates[i].time, record.direction);
               record.id = SmcRecordId(ICT_MSS, symbol, timeframe, record.sourceTime,
                                      record.direction, record.relatedId);
               if(!SmcAppendRecord(snapshot, record))
                 {
                  SmcClearPatternRecords(snapshot, ICT_MSS);
                  SmcSetModuleStatus(snapshot, ICT_MSS, SMC_STATUS_ERROR, snapshot.asOf,
                                     false, "Unable to append market structure shift");
                  return;
                 }
              }
           }
        }
      // Knowledge gained at this close can only affect subsequent candles.
      int pivot = i - config.swingStrength;
      if(pivot < config.swingStrength) continue;
      if(SmcIsStrictSwing(rates, pivot, config.swingStrength, true))
        {
         previousHigh = lastHigh;
         lastHigh = pivot;
        }
      if(SmcIsStrictSwing(rates, pivot, config.swingStrength, false))
        {
         previousLow = lastLow;
         lastLow = pivot;
        }
      if(previousHigh < 0 || previousLow < 0) continue;
      int earliest = MathMin(previousHigh, previousLow);
      if(i - earliest > config.lookbackBars) continue;
      if(rates[lastHigh].high > rates[previousHigh].high &&
         rates[lastLow].low > rates[previousLow].low)
        {
         trend = 1;
         evidenceStart = earliest;
        }
      else if(rates[lastHigh].high < rates[previousHigh].high &&
              rates[lastLow].low < rates[previousLow].low)
        {
         trend = -1;
         evidenceStart = earliest;
        }
     }
   SmcSetModuleStatus(snapshot, ICT_MSS, SMC_STATUS_READY, snapshot.asOf);
  }

#endif
