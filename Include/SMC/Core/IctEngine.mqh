// Deterministic evaluation: all inputs are supplied, chronological broker bars.
#ifndef __SMC_ICT_ENGINE_MQH__
#define __SMC_ICT_ENGINE_MQH__

#include "SmcSnapshot.mqh"
#include "../ICT/Displacement.mqh"
#include "../ICT/MarketStructureShift.mqh"
#include "../ICT/InverseFVG.mqh"
#include "../ICT/BalancedPriceRange.mqh"
#include "../ICT/SMTDivergence.mqh"
#include "../ICT/SessionRanges.mqh"
#include "../ICT/PowerOfThree.mqh"

bool SmcConceptEnabled(const ENUM_SMC_CONCEPT concept,const SmcConfig &config)
  {
   if(concept <= ICT_BREAKER) return true;
   if(concept == ICT_DISPLACEMENT) return config.enableDisplacement;
   if(concept == ICT_MSS) return config.enableMSS;
   if(concept == ICT_IFVG) return config.enableIFVG;
   if(concept == ICT_BPR) return config.enableBPR;
   if(concept == ICT_SMT) return config.IsSMTEnabled();
   if(concept == ICT_PO3) return config.enablePO3;
   return config.enableCalendar;
  }

// This also serves the terminal adapter on acquisition failure. Never retain
// records from a previously successful update in an unavailable snapshot.
void SmcUnavailableSnapshot(SmcSnapshot &snapshot,const SmcConfig &config,
                            const string symbol,const ENUM_TIMEFRAMES timeframe,
                            const ENUM_SMC_STATUS status,const string message,
                            const bool includeLegacy = false)
  {
   snapshot.Reset();
   snapshot.symbol = symbol;
   snapshot.timeframe = timeframe;
   snapshot.config = config;
   snapshot.status = status;
   snapshot.message = message;
   for(int i = (includeLegacy ? 0 : (int)ICT_DISPLACEMENT); i < SMC_CONCEPT_COUNT; i++)
     {
      ENUM_SMC_CONCEPT concept = (ENUM_SMC_CONCEPT)i;
      bool enabled = SmcConceptEnabled(concept,config);
      SmcSetModuleStatus(snapshot,concept,enabled ? status : SMC_STATUS_DISABLED,0,false,
                         enabled ? message : "Disabled by configuration");
     }
  }

void SmcAggregateStatus(SmcSnapshot &snapshot)
  {
   int ready = 0,unavailable = 0;
   bool partial = false;
   for(int i = 0; i < ArraySize(snapshot.modules); i++)
     {
      ENUM_SMC_STATUS status = snapshot.modules[i].status;
      if(status == SMC_STATUS_ERROR) { snapshot.status = SMC_STATUS_ERROR; return; }
      if(status == SMC_STATUS_READY) ready++;
      if(status == SMC_STATUS_NOT_READY) unavailable++;
      if(status == SMC_STATUS_PARTIAL) partial = true;
     }
   if(partial || (ready > 0 && unavailable > 0)) snapshot.status = SMC_STATUS_PARTIAL;
   else if(unavailable > 0) snapshot.status = SMC_STATUS_NOT_READY;
   else snapshot.status = SMC_STATUS_READY;
  }

bool SmcRecordEarlier(const SmcRecord &a,const SmcRecord &b)
  {
   if(a.confirmedAt != b.confirmedAt) return a.confirmedAt < b.confirmedAt;
   if(a.sourceTime != b.sourceTime) return a.sourceTime < b.sourceTime;
   if(a.concept != b.concept) return (int)a.concept < (int)b.concept;
   return StringCompare(a.id,b.id) < 0;
  }

// Stable bottom-up merge sort keeps large configured lookbacks practical.
bool SmcSortRecords(SmcRecord &records[])
  {
   int count = ArraySize(records);
   if(count < 2) return true;
   SmcRecord work[];
   if(ArrayResize(work,count) != count) return false;
   for(int width = 1; width < count; width *= 2)
     {
      for(int left = 0; left < count; left += 2*width)
        {
         int middle = MathMin(left+width,count);
         int end = MathMin(left+2*width,count);
         int a = left,b = middle;
         for(int out = left; out < end; out++)
           {
            if(a < middle && (b >= end || !SmcRecordEarlier(records[b],records[a])))
               work[out] = records[a++];
            else work[out] = records[b++];
           }
        }
      for(int i = 0; i < count; i++) records[i] = work[i];
     }
   return true;
  }

bool SmcKeepHistoricalRecord(const SmcRecord &record)
  {
   // Reference detectors publish only the latest completed reference. Open
   // zones and gaps remain useful even when formed during the warmup period.
   if(record.concept >= ICT_PREVIOUS_DAY_HIGH && record.concept <= ICT_SESSION_LOW)
      return true;
   return record.active && (record.concept == ICT_ORDER_BLOCK || record.concept == ICT_FVG ||
          record.concept == ICT_BREAKER || record.concept == ICT_IFVG || record.concept == ICT_BPR ||
          record.concept == ICT_DAILY_GAP || record.concept == ICT_WEEKLY_GAP);
  }

// Run after all dependencies and legacy adapters. Capping earlier could change
// derived detections and makes output limits affect the underlying analysis.
void SmcFinalizeSnapshot(SmcSnapshot &snapshot,const MqlRates &rates[])
  {
   int count = ArraySize(rates);
   datetime cutoff = count > 0 ? rates[MathMax(0,count-snapshot.config.lookbackBars)].time : 0;
   int kept = 0;
   for(int i = 0; i < ArraySize(snapshot.records); i++)
     {
      SmcRecord record = snapshot.records[i];
      if(record.sourceTime < cutoff && record.confirmedAt < cutoff && !SmcKeepHistoricalRecord(record))
         continue;
      snapshot.records[kept++] = record;
     }
   ArrayResize(snapshot.records,kept);
   if(!SmcSortRecords(snapshot.records))
     {
      ArrayResize(snapshot.records,0);
      snapshot.status = SMC_STATUS_ERROR;
      snapshot.message = "Cannot allocate snapshot sorting storage";
      return;
     }
   int counts[SMC_CONCEPT_COUNT];
   ArrayInitialize(counts,0);
   bool retain[];
   if(ArrayResize(retain,kept) != kept)
     {
      ArrayResize(snapshot.records,0);
      snapshot.status = SMC_STATUS_ERROR;
      snapshot.message = "Cannot allocate snapshot output limit storage";
      return;
     }
   ArrayInitialize(retain,false);
   for(int i = kept-1; i >= 0; i--)
     {
      int concept = (int)snapshot.records[i].concept;
      if(concept < 0 || concept >= SMC_CONCEPT_COUNT) continue;
      counts[concept]++;
      if(counts[concept] <= snapshot.config.maxRecordsPerConcept) retain[i] = true;
      else
         for(int m = 0; m < ArraySize(snapshot.modules); m++)
            if((int)snapshot.modules[m].concept == concept) snapshot.modules[m].truncated = true;
     }
   int out = 0;
   for(int i = 0; i < kept; i++)
      if(retain[i]) snapshot.records[out++] = snapshot.records[i];
   ArrayResize(snapshot.records,out);
   SmcAggregateStatus(snapshot);
  }

// Daily/weekly arrays include the current period for its open/time only. All
// other arrays exclude forming bars. coverageStart/End attest a synchronized,
// successful M1 request, including legitimate weekends without traded bars.
bool SmcEvaluateICT(const MqlRates &rates[],const MqlRates &daily[],const MqlRates &weekly[],
                    const MqlRates &minutes[],const MqlRates &companion[],const SmcConfig &config,
                    const string symbol,const ENUM_TIMEFRAMES timeframe,const double tick,
                    const double pip,const double companionTick,SmcSnapshot &snapshot,
                    const datetime coverageStart = 0,const datetime coverageEnd = 0)
  {
   string reason;
   if(!config.Validate(reason) || symbol == "" || PeriodSeconds(timeframe) <= 0 || ArrayGetAsSeries(rates) ||
      !MathIsValidNumber(tick) || tick <= 0 || !MathIsValidNumber(pip) || pip <= 0)
     {
      if(reason == "") reason = "Invalid symbol, timeframe or price increment";
      SmcUnavailableSnapshot(snapshot,config,symbol,timeframe,SMC_STATUS_ERROR,reason);
      return false;
     }
   int count = ArraySize(rates);
   for(int i = 0; i < count; i++)
      if(rates[i].time <= 0 || (i > 0 && rates[i].time <= rates[i-1].time) ||
         !MathIsValidNumber(rates[i].open) || !MathIsValidNumber(rates[i].close) ||
         !MathIsValidNumber(rates[i].high) || !MathIsValidNumber(rates[i].low) ||
         rates[i].high < MathMax(rates[i].open,rates[i].close) ||
         rates[i].low > MathMin(rates[i].open,rates[i].close) || rates[i].low > rates[i].high)
        {
         SmcUnavailableSnapshot(snapshot,config,symbol,timeframe,SMC_STATUS_ERROR,"Invalid chronological primary OHLC");
         return false;
        }
   if(count < config.lookbackBars+config.WarmupBars())
     {
      SmcUnavailableSnapshot(snapshot,config,symbol,timeframe,SMC_STATUS_NOT_READY,"Primary history is shorter than lookback plus warmup");
      return false;
     }
   snapshot.Reset();
   snapshot.symbol = symbol;
   snapshot.timeframe = timeframe;
   snapshot.config = config;
   snapshot.asOf = SmcBarClosedAt(rates[count-1].time,timeframe);
   SmcDetectDisplacement(rates,config,symbol,timeframe,tick,snapshot);
   SmcDetectMSS(rates,config,symbol,timeframe,tick,snapshot);
   SmcDetectIFVG(rates,config,symbol,timeframe,tick,pip,snapshot);
   SmcDetectBPR(rates,config,symbol,timeframe,tick,pip,snapshot);
   SmcDetectCalendar(rates,daily,weekly,minutes,config,symbol,timeframe,tick,snapshot,coverageStart,coverageEnd);
   SmcDetectSMT(rates,companion,config,symbol,timeframe,tick,companionTick,snapshot);
   SmcDetectPO3(rates,minutes,config,symbol,timeframe,tick,snapshot,coverageStart,coverageEnd);
   SmcFinalizeSnapshot(snapshot,rates);
   return snapshot.status == SMC_STATUS_READY;
  }

#endif
