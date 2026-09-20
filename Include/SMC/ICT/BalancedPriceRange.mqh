// BPR is the intersection of two opposite original FVGs, never derived zones.
#ifndef __SMC_BALANCED_PRICE_RANGE_MQH__
#define __SMC_BALANCED_PRICE_RANGE_MQH__

#include "FvgReplay.mqh"

bool SmcDetectBPR(const MqlRates &rates[],const SmcConfig &config,
                   const string symbol,const ENUM_TIMEFRAMES timeframe,
                   const double tick,const double pip,SmcSnapshot &out)
  {
   const int count=ArraySize(rates);
   const datetime asOf=count > 0 ? SmcBarClosedAt(rates[count-1].time,timeframe) : 0;
   if(!config.enableBPR)
      return SmcSetModuleStatus(out,ICT_BPR,SMC_STATUS_DISABLED,asOf);
   string reason;
   if(!SmcValidateImbalanceInput(rates,config,timeframe,tick,pip,reason))
     {
      SmcSetModuleStatus(out,ICT_BPR,SMC_STATUS_ERROR,asOf,false,reason);
      return false;
     }
   if(count < 4)
      return SmcSetModuleStatus(out,ICT_BPR,SMC_STATUS_NOT_READY,asOf,false,"At least four closed bars are required");
   SmcFvgSource sources[];
   if(!SmcCollectFvgSources(rates,config,symbol,timeframe,tick,pip,sources))
     {
      SmcSetModuleStatus(out,ICT_BPR,SMC_STATUS_ERROR,asOf,false,"Cannot allocate FVG replay sources");
      return false;
     }
   for(int newer=1;newer<ArraySize(sources);newer++)
     {
      for(int older=newer-1;older>=0;older--)
        {
         if(sources[newer].confirmedBar-sources[older].confirmedBar > config.bprMaxSeparation)
            break;
         if(sources[newer].direction == sources[older].direction) continue;
         double lower=MathMax(sources[older].lower,sources[newer].lower);
         double upper=MathMin(sources[older].upper,sources[newer].upper);
         if(!SmcImbalanceAtLeast(upper-lower,tick,tick)) continue;
         SmcRecord record;
         record.Init();
         record.concept=ICT_BPR;
         record.sourceTime=sources[newer].sourceTime;
         record.confirmedAt=sources[newer].confirmedAt;
         record.updatedAt=record.confirmedAt;
         record.direction=sources[newer].direction;
         record.lower=lower;
         record.upper=upper;
         record.relatedId=sources[older].id;
         record.secondaryId=sources[newer].id;
         // The newer FVG's time and direction identify one side of the pair;
         // length-prefixed older ID identifies the other, without collisions.
         record.id=SmcRecordId(ICT_BPR,symbol,timeframe,record.sourceTime,record.direction,record.relatedId);
         SmcReplayImbalanceState(rates,sources[newer].confirmedBar,timeframe,tick,config.maxZoneAge,record);
         if(!SmcAppendRecord(out,record))
           {
            SmcSetModuleStatus(out,ICT_BPR,SMC_STATUS_ERROR,asOf,false,"Cannot append balanced price range");
            return false;
           }
        }
     }
   return SmcSetModuleStatus(out,ICT_BPR,SMC_STATUS_READY,asOf);
  }

#endif // __SMC_BALANCED_PRICE_RANGE_MQH__
