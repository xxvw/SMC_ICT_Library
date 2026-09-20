// Pure detection helpers: input rates are chronological and closed only.
#ifndef __SMC_ICT_DISPLACEMENT_MQH__
#define __SMC_ICT_DISPLACEMENT_MQH__

#include "../Core/SmcSnapshot.mqh"

// A candidate never contributes to its own baseline. Flat baselines and
// zero-range candles carry no displacement information.
bool SmcIsDisplacement(const MqlRates &rates[], const int index,
                       const SmcConfig &config)
  {
   if(config.displacementBaseline < 1 || index < config.displacementBaseline ||
      index >= ArraySize(rates)) return false;
   double body = MathAbs(rates[index].close - rates[index].open);
   double range = rates[index].high - rates[index].low;
   if(body <= 0 || range <= 0) return false;
   double sum = 0;
   for(int i = index - config.displacementBaseline; i < index; i++)
      sum += MathAbs(rates[i].close - rates[i].open);
   double mean = sum / config.displacementBaseline;
   double minimum = mean * config.displacementMultiplier;
   // Decimal OHLC subtraction can round an exact inclusive threshold down.
   // Small relative slack keeps values meaningfully below either configured
   // threshold excluded while accepting decimal boundary fixtures.
   double bodyTolerance = MathMax(body, minimum) * 1e-8;
   return mean > 0 && body + bodyTolerance >= minimum &&
          body / range + 1e-8 >= config.displacementBodyFraction;
  }

// Call only once the entire right-hand confirmation window has closed.
// Equal highs/lows do not create a swing.
bool SmcIsStrictSwing(const MqlRates &rates[], const int pivot,
                      const int strength, const bool highSide)
  {
   if(strength < 1 || pivot < strength || pivot + strength >= ArraySize(rates))
      return false;
   for(int offset = 1; offset <= strength; offset++)
     {
      if(highSide && (rates[pivot].high <= rates[pivot-offset].high ||
                     rates[pivot].high <= rates[pivot+offset].high)) return false;
      if(!highSide && (rates[pivot].low >= rates[pivot-offset].low ||
                      rates[pivot].low >= rates[pivot+offset].low)) return false;
     }
   return true;
  }

// Each pure evaluation replaces only its own concept; unrelated results stay.
void SmcClearPatternRecords(SmcSnapshot &snapshot, const ENUM_SMC_CONCEPT concept)
  {
   int retained = 0;
   for(int i = 0; i < ArraySize(snapshot.records); i++)
      if(snapshot.records[i].concept != concept)
        {
         if(retained != i) snapshot.records[retained] = snapshot.records[i];
         retained++;
        }
   ArrayResize(snapshot.records, retained);
  }

bool SmcPatternInputsValid(const MqlRates &rates[], const SmcConfig &config,
                           const ENUM_TIMEFRAMES timeframe, const double tick)
  {
   string reason;
   if(!config.Validate(reason) || PeriodSeconds(timeframe) <= 0 ||
      !MathIsValidNumber(tick) || tick <= 0 || ArrayGetAsSeries(rates)) return false;
   for(int i = 0; i < ArraySize(rates); i++)
     {
      if(rates[i].time <= 0 || (i > 0 && rates[i].time <= rates[i-1].time) ||
         !MathIsValidNumber(rates[i].open) || !MathIsValidNumber(rates[i].close) ||
         !MathIsValidNumber(rates[i].high) || !MathIsValidNumber(rates[i].low) ||
         rates[i].high < MathMax(rates[i].open, rates[i].close) ||
         rates[i].low > MathMin(rates[i].open, rates[i].close)) return false;
     }
   return true;
  }

void SmcDetectDisplacement(const MqlRates &rates[], const SmcConfig &config,
                           const string symbol, const ENUM_TIMEFRAMES timeframe,
                           const double tick, SmcSnapshot &snapshot)
  {
   SmcClearPatternRecords(snapshot, ICT_DISPLACEMENT);
   if(!config.enableDisplacement)
     {
      SmcSetModuleStatus(snapshot, ICT_DISPLACEMENT, SMC_STATUS_DISABLED, snapshot.asOf);
      return;
     }
   if(!SmcPatternInputsValid(rates, config, timeframe, tick))
     {
      SmcSetModuleStatus(snapshot, ICT_DISPLACEMENT, SMC_STATUS_ERROR, snapshot.asOf,
                         false, "Invalid configuration or chronological OHLC input");
      return;
     }
   int count = ArraySize(rates);
   if(count <= config.displacementBaseline)
     {
      SmcSetModuleStatus(snapshot, ICT_DISPLACEMENT, SMC_STATUS_NOT_READY, snapshot.asOf,
                         false, "Insufficient displacement baseline");
      return;
     }
   int first = MathMax(config.displacementBaseline, count - config.lookbackBars);
   for(int i = first; i < count; i++)
     {
      if(!SmcIsDisplacement(rates, i, config)) continue;
      SmcRecord record;
      record.Init();
      record.concept = ICT_DISPLACEMENT;
      record.sourceTime = rates[i].time;
      record.confirmedAt = SmcBarClosedAt(rates[i].time, timeframe);
      record.updatedAt = record.confirmedAt;
      record.direction = rates[i].close > rates[i].open ? 1 : -1;
      record.lower = MathMin(rates[i].open, rates[i].close);
      record.upper = MathMax(rates[i].open, rates[i].close);
      record.state = "CONFIRMED";
      record.strength = MathAbs(rates[i].close - rates[i].open) /
                        (rates[i].high - rates[i].low);
      record.id = SmcRecordId(record.concept, symbol, timeframe,
                             record.sourceTime, record.direction);
      if(!SmcAppendRecord(snapshot, record))
        {
         SmcClearPatternRecords(snapshot, ICT_DISPLACEMENT);
         SmcSetModuleStatus(snapshot, ICT_DISPLACEMENT, SMC_STATUS_ERROR, snapshot.asOf,
                            false, "Unable to append displacement result");
         return;
        }
     }
   SmcSetModuleStatus(snapshot, ICT_DISPLACEMENT, SMC_STATUS_READY, snapshot.asOf);
  }

#endif
