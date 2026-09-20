// Pure replay helpers shared by IFVG and BPR. Input is chronological CLOSED bars.
#ifndef __SMC_FVG_REPLAY_MQH__
#define __SMC_FVG_REPLAY_MQH__

#include "../Core/SmcSnapshot.mqh"

struct SmcFvgSource
  {
   string id;
   int direction;
   int confirmedBar;
   datetime sourceTime;
   datetime confirmedAt;
   double lower;
   double upper;
  };

// Tick-scaled tolerance protects exact decimal-tick boundaries from binary
// floating-point roundoff, without accepting a meaningfully smaller movement.
bool SmcImbalanceAtLeast(const double value,const double minimum,const double tick)
  {
   return value + tick * 1.0e-8 >= minimum;
  }

bool SmcValidateImbalanceInput(const MqlRates &rates[],const SmcConfig &config,
                               const ENUM_TIMEFRAMES timeframe,const double tick,
                               const double pip,string &reason)
  {
   if(!config.Validate(reason)) return false;
   if(!MathIsValidNumber(tick) || tick <= 0 || !MathIsValidNumber(pip) || pip <= 0 ||
      PeriodSeconds(timeframe) <= 0)
     {
      reason = "Imbalance replay requires a positive tick, pip and explicit timeframe";
      return false;
     }
   if(ArrayGetAsSeries(rates))
     {
      reason = "Imbalance replay requires chronological bars";
      return false;
     }
   for(int i=0;i<ArraySize(rates);i++)
     {
      if(rates[i].time <= 0 || (i > 0 && rates[i].time <= rates[i-1].time) ||
         !MathIsValidNumber(rates[i].open) || !MathIsValidNumber(rates[i].high) ||
         !MathIsValidNumber(rates[i].low) || !MathIsValidNumber(rates[i].close) ||
         rates[i].high < rates[i].low || rates[i].open < rates[i].low ||
         rates[i].open > rates[i].high || rates[i].close < rates[i].low ||
         rates[i].close > rates[i].high)
        {
         reason = "Imbalance replay received invalid OHLC or unordered timestamps";
         return false;
        }
     }
   reason = "";
   return true;
  }

// Original FVGs remain available as historical ancestors even after they have
// been filled or broken. Derived detections apply their own age constraints.
bool SmcCollectFvgSources(const MqlRates &rates[],const SmcConfig &config,
                          const string symbol,const ENUM_TIMEFRAMES timeframe,
                          const double tick,const double pip,SmcFvgSource &sources[])
  {
   ArrayResize(sources,0);
   for(int i=2;i<ArraySize(rates);i++)
     {
      int direction=0;
      double lower=0,upper=0;
      if(rates[i].low > rates[i-2].high)
        {
         direction=1;
         lower=rates[i-2].high;
         upper=rates[i].low;
        }
      else if(rates[i].high < rates[i-2].low)
        {
         direction=-1;
         lower=rates[i].high;
         upper=rates[i-2].low;
        }
      if(direction == 0 || !SmcImbalanceAtLeast(upper-lower,config.minFvgPips*pip,tick))
         continue;
      int n=ArraySize(sources);
      if(ArrayResize(sources,n+1) != n+1) return false;
      sources[n].id=SmcRecordId(ICT_FVG,symbol,timeframe,rates[i-1].time,direction);
      sources[n].direction=direction;
      sources[n].confirmedBar=i;
      sources[n].sourceTime=rates[i-1].time;
      sources[n].confirmedAt=SmcBarClosedAt(rates[i].time,timeframe);
      sources[n].lower=lower;
      sources[n].upper=upper;
     }
   return true;
  }

bool SmcImbalanceCloseThrough(const double close,const int direction,
                              const double lower,const double upper,const double tick)
  {
   return direction > 0 ? SmcImbalanceAtLeast(lower-close,tick,tick) :
                          SmcImbalanceAtLeast(close-upper,tick,tick);
  }

// Formation bars cannot mitigate their own new zone. State only strengthens;
// expiry preserves that state and records a separate invalidation reason.
void SmcReplayImbalanceState(const MqlRates &rates[],const int confirmedBar,
                             const ENUM_TIMEFRAMES timeframe,const double tick,
                             const int maxAge,SmcRecord &record)
  {
   for(int i=confirmedBar+1;i<ArraySize(rates);i++)
     {
      record.updatedAt=SmcBarClosedAt(rates[i].time,timeframe);
      if(i-confirmedBar > maxAge)
        {
         record.active=false;
         record.reason="expired";
         return;
        }
      if(SmcImbalanceCloseThrough(rates[i].close,record.direction,record.lower,record.upper,tick))
        {
         record.state="BROKEN";
         record.active=false;
         record.reason="close_through";
         return;
        }
      bool touches=rates[i].low <= record.upper && rates[i].high >= record.lower;
      if(!touches) continue;
      double midpoint=(record.lower+record.upper)*0.5;
      bool mitigated=record.direction > 0 ? rates[i].low <= midpoint : rates[i].high >= midpoint;
      if(mitigated) record.state="MITIGATED";
      else if(record.state == "FRESH") record.state="TESTED";
     }
  }

#endif // __SMC_FVG_REPLAY_MQH__
