// Inverse FVGs are confirmed once, on the first eligible distal close-through.
#ifndef __SMC_INVERSE_FVG_MQH__
#define __SMC_INVERSE_FVG_MQH__

#include "FvgReplay.mqh"

bool SmcDetectIFVG(const MqlRates &rates[],const SmcConfig &config,
                    const string symbol,const ENUM_TIMEFRAMES timeframe,
                    const double tick,const double pip,SmcSnapshot &out)
  {
   const int count=ArraySize(rates);
   const datetime asOf=count > 0 ? SmcBarClosedAt(rates[count-1].time,timeframe) : 0;
   if(!config.enableIFVG)
      return SmcSetModuleStatus(out,ICT_IFVG,SMC_STATUS_DISABLED,asOf);
   string reason;
   if(!SmcValidateImbalanceInput(rates,config,timeframe,tick,pip,reason))
     {
      SmcSetModuleStatus(out,ICT_IFVG,SMC_STATUS_ERROR,asOf,false,reason);
      return false;
     }
   if(count < 4)
      return SmcSetModuleStatus(out,ICT_IFVG,SMC_STATUS_NOT_READY,asOf,false,"At least four closed bars are required");
   SmcFvgSource sources[];
   if(!SmcCollectFvgSources(rates,config,symbol,timeframe,tick,pip,sources))
     {
      SmcSetModuleStatus(out,ICT_IFVG,SMC_STATUS_ERROR,asOf,false,"Cannot allocate FVG replay sources");
      return false;
     }
   for(int source=0;source<ArraySize(sources);source++)
     {
      const int first=sources[source].confirmedBar+1;
      const int last=(int)MathMin(count-1,sources[source].confirmedBar+config.maxZoneAge);
      for(int i=first;i<=last;i++)
        {
         if(!SmcImbalanceCloseThrough(rates[i].close,sources[source].direction,
                                      sources[source].lower,sources[source].upper,tick))
            continue;
         SmcRecord record;
         record.Init();
         record.concept=ICT_IFVG;
         record.sourceTime=rates[i].time;
         record.confirmedAt=SmcBarClosedAt(rates[i].time,timeframe);
         record.updatedAt=record.confirmedAt;
         record.direction=-sources[source].direction;
         record.lower=sources[source].lower;
         record.upper=sources[source].upper;
         record.relatedId=sources[source].id;
         record.id=SmcRecordId(ICT_IFVG,symbol,timeframe,record.sourceTime,record.direction,record.relatedId);
         SmcReplayImbalanceState(rates,i,timeframe,tick,config.maxZoneAge,record);
         if(!SmcAppendRecord(out,record))
           {
            SmcSetModuleStatus(out,ICT_IFVG,SMC_STATUS_ERROR,asOf,false,"Cannot append inverse FVG");
            return false;
           }
         break; // A source can invert only once; inverse zones never recurse.
        }
     }
   return SmcSetModuleStatus(out,ICT_IFVG,SMC_STATUS_READY,asOf);
  }

#endif // __SMC_INVERSE_FVG_MQH__
