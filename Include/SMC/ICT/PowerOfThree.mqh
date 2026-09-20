// Causal accumulation -> manipulation -> distribution replay in broker time.
#ifndef __SMC_POWER_OF_THREE_MQH__
#define __SMC_POWER_OF_THREE_MQH__

#include "SessionRanges.mqh"
#include "Displacement.mqh"

// Match the opening-gap threshold: tolerate only floating-point round-off,
// without admitting a materially sub-tick sweep or closing break.
bool SmcPO3AtLeastTick(const double difference,const double tick)
  {
   return difference+tick*1e-8>=tick;
  }

void SmcRemovePO3Records(SmcSnapshot &snapshot)
  {
   int count=ArraySize(snapshot.records),target=0;
   for(int i=0;i<count;i++)
      if(snapshot.records[i].concept!=ICT_PO3)
        {
         if(target!=i) snapshot.records[target]=snapshot.records[i];
         target++;
        }
   ArrayResize(snapshot.records,target);
  }

// Each stage is an immutable confirmation event. Only active/updatedAt change
// when a successor closes the stage; relatedId points to that previous stage.
void SmcPO3Advance(SmcSnapshot &snapshot,SmcRecord &previous,const string state,
                   const datetime when,const int direction,const double reference,
                   const double comparison,const string reason,const string symbol,
                   const ENUM_TIMEFRAMES tf,const string sessionName)
  {
   string previousId=previous.id;
   previous.active=false;
   previous.updatedAt=when;
   SmcAppendRecord(snapshot,previous);
   SmcRecord next;
   next.Init();
   next.concept=ICT_PO3;
   next.sourceTime=previous.sourceTime;
   next.confirmedAt=when;
   next.updatedAt=when;
   next.direction=direction;
   next.lower=previous.lower;
   next.upper=previous.upper;
   next.periodStart=previous.periodStart;
   next.periodEnd=previous.periodEnd;
   next.referencePrice=reference;
   next.comparisonPrice=comparison;
   next.state=state;
   next.active=state=="MANIPULATION";
   next.relatedId=previousId;
   next.reason=reason;
   next.id=SmcRecordId(ICT_PO3,symbol,tf,next.sourceTime,direction,sessionName+":"+state);
   SmcAppendRecord(snapshot,next);
   previous=next;
  }

void SmcDetectPO3(const MqlRates &rates[],const MqlRates &minutes[],const SmcConfig &config,
                  const string symbol,const ENUM_TIMEFRAMES tf,const double tick,
                  SmcSnapshot &snapshot,const datetime coverageStart=0,const datetime coverageEnd=0)
  {
   SmcRemovePO3Records(snapshot);
   int n=ArraySize(rates);
   datetime asOf=n>0 ? SmcBarClosedAt(rates[n-1].time,tf) : 0;
   if(!config.enablePO3)
     {
      SmcSetModuleStatus(snapshot,ICT_PO3,SMC_STATUS_DISABLED,asOf);
      return;
     }
   if(!SmcSessionInputsValid(rates,minutes,config,tf) || !SmcPatternInputsValid(rates,config,tf,tick))
     {
      SmcSetModuleStatus(snapshot,ICT_PO3,SMC_STATUS_ERROR,asOf,false,"Invalid configuration or chronological OHLC history");
      return;
     }
   if(n<=config.displacementBaseline)
     {
      SmcSetModuleStatus(snapshot,ICT_PO3,SMC_STATUS_NOT_READY,asOf,false,
                         "PO3 requires closed primary history, a displacement baseline and tick size");
      return;
     }
   SmcCompletedSession ranges[];
   SmcBuildCompletedSessions(minutes,config.sessions[0],SmcBrokerDayStart(rates[0].time)-86400,
                            asOf,ranges,coverageStart,coverageEnd);
   int count=ArraySize(ranges);
   bool ready=count>0 && ranges[count-1].available && ranges[count-1].end>=rates[0].time;
   int omitted=0;
   for(int s=0;s<count;s++)
     {
      if(!ranges[s].available || ranges[s].end<rates[0].time)
        {
         omitted++;
         continue;
        }
      SmcRecord stage;
      stage.Init();
      stage.concept=ICT_PO3;
      stage.sourceTime=ranges[s].start;
      stage.confirmedAt=ranges[s].end;
      stage.updatedAt=stage.confirmedAt;
      stage.periodStart=ranges[s].start;
      stage.periodEnd=ranges[s].end;
      stage.lower=ranges[s].low;
      stage.upper=ranges[s].high;
      stage.state="ACCUMULATION";
      stage.reason=config.sessions[0].name;
      stage.id=SmcRecordId(ICT_PO3,symbol,tf,stage.sourceTime,0,config.sessions[0].name+":ACCUMULATION");
      SmcAppendRecord(snapshot,stage);
      datetime nextSessionStart=ranges[s].start+86400;
      int manipulation=-1;
      for(int i=0;i<n;i++)
        {
         datetime closeTime=SmcBarClosedAt(rates[i].time,tf);
         if(closeTime<=ranges[s].end) continue;
         if(closeTime>=nextSessionStart)
           {
            SmcPO3Advance(snapshot,stage,"EXPIRED",nextSessionStart,stage.direction,
                          stage.referencePrice,0,"next_accumulation_session",symbol,tf,config.sessions[0].name);
            break;
           }
         // A candle straddling the accumulation boundary contains prices that
         // formed the range; it cannot prove a later manipulation.
         if(rates[i].time<ranges[s].end) continue;
         bool sweptHigh=SmcPO3AtLeastTick(rates[i].high-ranges[s].high,tick);
         bool sweptLow=SmcPO3AtLeastTick(ranges[s].low-rates[i].low,tick);
         if(sweptHigh && sweptLow)
           {
            SmcPO3Advance(snapshot,stage,"INVALIDATED",closeTime,stage.direction,
                          stage.referencePrice,rates[i].close,"ambiguous_both_side_sweep",symbol,tf,config.sessions[0].name);
            break;
           }
         if(manipulation<0)
           {
            bool inside=rates[i].close>=ranges[s].low && rates[i].close<=ranges[s].high;
            if(inside && (sweptHigh || sweptLow))
              {
               int direction=sweptLow ? 1 : -1;
               double extreme=sweptLow ? rates[i].low : rates[i].high;
               SmcPO3Advance(snapshot,stage,"MANIPULATION",closeTime,direction,extreme,0,
                             "sweep_and_close_back_inside",symbol,tf,config.sessions[0].name);
               manipulation=i;
              }
            continue;
           }
         bool wrongSide=stage.direction>0 ? SmcPO3AtLeastTick(ranges[s].low-rates[i].close,tick) :
            SmcPO3AtLeastTick(rates[i].close-ranges[s].high,tick);
         if(wrongSide)
           {
            SmcPO3Advance(snapshot,stage,"INVALIDATED",closeTime,stage.direction,
                          stage.referencePrice,rates[i].close,"close_through_manipulation_side",symbol,tf,config.sessions[0].name);
            break;
           }
         bool opposite=stage.direction>0 ? SmcPO3AtLeastTick(rates[i].close-ranges[s].high,tick) :
            SmcPO3AtLeastTick(ranges[s].low-rates[i].close,tick);
         bool correctBody=stage.direction>0 ? rates[i].close>rates[i].open : rates[i].close<rates[i].open;
         if(opposite && correctBody && SmcIsDisplacement(rates,i,config))
           {
            SmcPO3Advance(snapshot,stage,"DISTRIBUTION",closeTime,stage.direction,
                          stage.referencePrice,rates[i].close,"opposite_displacement_break",symbol,tf,config.sessions[0].name);
            break;
           }
         // Distribution remains possible on the final permitted bar. Once
         // that bar closes without distribution the window has fully elapsed.
         if(i-manipulation>=config.po3ExpiryBars)
           {
            SmcPO3Advance(snapshot,stage,"EXPIRED",closeTime,stage.direction,
                          stage.referencePrice,0,"manipulation_window_elapsed",symbol,tf,config.sessions[0].name);
            break;
           }
        }
      // Time expiry is meaningful even across a market closure with no bar at
      // the next session start. The caller's primary asOf bounds availability.
      if(stage.active && asOf>=nextSessionStart)
         SmcPO3Advance(snapshot,stage,"EXPIRED",nextSessionStart,stage.direction,
                       stage.referencePrice,0,"next_accumulation_session",symbol,tf,config.sessions[0].name);
     }
   string message=ready ? (omitted>0 ? "Unavailable historical accumulation ranges omitted" : "") :
      "Latest completed accumulation requires covered M1 and primary history";
   SmcSetModuleStatus(snapshot,ICT_PO3,ready ? SMC_STATUS_READY : SMC_STATUS_NOT_READY,asOf,false,message);
  }

#endif
