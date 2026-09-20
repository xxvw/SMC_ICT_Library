// Broker-clock sessions, computed from synchronized closed M1 history.
#ifndef __SMC_SESSION_RANGES_MQH__
#define __SMC_SESSION_RANGES_MQH__

#include "../Core/SmcSnapshot.mqh"
#include "ReferenceLevels.mqh"
#include "OpeningGaps.mqh"

struct SmcCompletedSession
  {
   datetime start;
   datetime end;
   double high;
   double low;
   bool available;
   int bars;
  };

datetime SmcBrokerDayStart(const datetime value)
  {
   return (datetime)((long)value - (long)value % 86400);
  }

bool SmcSessionInputsValid(const MqlRates &rates[],const MqlRates &minutes[],
                           const SmcConfig &config,const ENUM_TIMEFRAMES tf)
  {
   string reason;
   if(!config.Validate(reason) || PeriodSeconds(tf)<=0 ||
      ArrayGetAsSeries(rates) || ArrayGetAsSeries(minutes)) return false;
   for(int i=0;i<ArraySize(rates);i++)
      if(rates[i].time<=0 || (i>0 && rates[i].time<=rates[i-1].time)) return false;
   for(int i=0;i<ArraySize(minutes);i++)
      if(minutes[i].time<=0 || (i>0 && minutes[i].time<=minutes[i-1].time) ||
         !MathIsValidNumber(minutes[i].high) || !MathIsValidNumber(minutes[i].low) ||
         minutes[i].high<minutes[i].low) return false;
   return true;
  }

// coverageStart/End attest a successful, synchronized CopyRates time request.
// No-tick minutes inside that interval are allowed. Pure callers are responsible
// for the attestation; with zero values we conservatively use array boundaries.
// Sessions are [start,end), including when the end falls on the next broker day.
void SmcBuildCompletedSessions(const MqlRates &minutes[],const SmcSessionConfig &session,
                              const datetime from,const datetime asOf,
                              SmcCompletedSession &ranges[],
                              const datetime coverageStart=0,const datetime coverageEnd=0)
  {
   ArrayResize(ranges,0);
   int n=ArraySize(minutes);
   if(from<=0 || asOf<=from || session.startMinute<0 || session.startMinute>1439 ||
      session.endMinute<0 || session.endMinute>1439 || session.startMinute==session.endMinute)
      return;
   datetime first=coverageStart;
   datetime last=coverageEnd;
   if(first==0 && n>0) first=minutes[0].time;
   if(last==0)
      for(int i=n-1;i>=0;i--)
         if(minutes[i].time+60<=asOf)
           {
            last=minutes[i].time+60;
            break;
           }
   int cursor=0;
   datetime day=SmcBrokerDayStart(from)-86400;
   for(;day<=asOf;day+=86400)
     {
      datetime start=day+session.startMinute*60;
      datetime end=day+session.endMinute*60;
      if(end<=start) end+=86400;
      if(end<=from || end>asOf) continue;
      while(cursor<n && minutes[cursor].time<start) cursor++;
      SmcCompletedSession range;
      range.start=start;
      range.end=end;
      range.high=0;
      range.low=0;
      range.bars=0;
      range.available=false;
      int current=cursor;
      while(current<n && minutes[current].time<end && minutes[current].time+60<=asOf)
        {
         if(range.bars==0)
           {
            range.high=minutes[current].high;
            range.low=minutes[current].low;
           }
         else
           {
            range.high=MathMax(range.high,minutes[current].high);
            range.low=MathMin(range.low,minutes[current].low);
           }
         range.bars++;
         current++;
        }
      cursor=current;
      range.available=range.bars>0 && first>0 && first<=start && last>=end;
      int count=ArraySize(ranges);
      if(ArrayResize(ranges,count+1)!=count+1) return;
      ranges[count]=range;
     }
  }

void SmcRemoveSessionRecords(SmcSnapshot &snapshot)
  {
   int count=ArraySize(snapshot.records),target=0;
   for(int i=0;i<count;i++)
      if(snapshot.records[i].concept!=ICT_SESSION_HIGH && snapshot.records[i].concept!=ICT_SESSION_LOW)
        {
         if(target!=i) snapshot.records[target]=snapshot.records[i];
         target++;
        }
   ArrayResize(snapshot.records,target);
  }

void SmcDetectSessions(const MqlRates &rates[],const MqlRates &minutes[],
                       const SmcConfig &config,const string symbol,const ENUM_TIMEFRAMES tf,
                       SmcSnapshot &snapshot,const datetime coverageStart=0,const datetime coverageEnd=0)
  {
   SmcRemoveSessionRecords(snapshot);
   int n=ArraySize(rates);
   datetime asOf=n>0 ? SmcBarClosedAt(rates[n-1].time,tf) : 0;
   if(!config.enableCalendar)
     {
      SmcSetModuleStatus(snapshot,ICT_SESSION_HIGH,SMC_STATUS_DISABLED,asOf);
      SmcSetModuleStatus(snapshot,ICT_SESSION_LOW,SMC_STATUS_DISABLED,asOf);
      return;
     }
   if(!SmcSessionInputsValid(rates,minutes,config,tf))
     {
      SmcSetModuleStatus(snapshot,ICT_SESSION_HIGH,SMC_STATUS_ERROR,asOf,false,"Invalid session configuration or chronological history");
      SmcSetModuleStatus(snapshot,ICT_SESSION_LOW,SMC_STATUS_ERROR,asOf,false,"Invalid session configuration or chronological history");
      return;
     }
   int ready=0;
   for(int s=0;s<3 && n>0;s++)
     {
      SmcCompletedSession ranges[];
      // Include the preceding broker day even on intraday primary history.
      datetime previousDay=SmcBrokerDayStart(asOf)-86400;
      datetime from=rates[0].time<previousDay ? rates[0].time : previousDay;
      SmcBuildCompletedSessions(minutes,config.sessions[s],from,asOf,ranges,coverageStart,coverageEnd);
      int last=ArraySize(ranges)-1;
      if(last<0 || !ranges[last].available) continue;
      ready++;
      for(int side=0;side<2;side++)
        {
         SmcRecord record;
         record.Init();
         record.concept=side==0 ? ICT_SESSION_HIGH : ICT_SESSION_LOW;
         record.sourceTime=ranges[last].start;
         record.confirmedAt=ranges[last].end;
         record.updatedAt=record.confirmedAt;
         record.periodStart=ranges[last].start;
         record.periodEnd=ranges[last].end;
         record.lower=side==0 ? ranges[last].high : ranges[last].low;
         record.upper=record.lower;
         record.referencePrice=record.lower;
         record.state="COMPLETE";
         record.reason=config.sessions[s].name;
         record.id=SmcRecordId(record.concept,symbol,tf,record.sourceTime,0,config.sessions[s].name);
         SmcAppendRecord(snapshot,record);
        }
     }
   ENUM_SMC_STATUS status=ready==3 ? SMC_STATUS_READY : (ready>0 ? SMC_STATUS_PARTIAL : SMC_STATUS_NOT_READY);
   string message=ready==3 ? "" : "Latest completed session requires covered, nonempty M1 history";
   SmcSetModuleStatus(snapshot,ICT_SESSION_HIGH,status,asOf,false,message);
   SmcSetModuleStatus(snapshot,ICT_SESSION_LOW,status,asOf,false,message);
  }

void SmcDetectCalendar(const MqlRates &rates[],const MqlRates &daily[],const MqlRates &weekly[],
                       const MqlRates &minutes[],const SmcConfig &config,const string symbol,
                       const ENUM_TIMEFRAMES tf,const double tick,SmcSnapshot &snapshot,
                       const datetime coverageStart=0,const datetime coverageEnd=0)
  {
   SmcDetectReferenceLevels(rates,daily,weekly,config,symbol,tf,tick,snapshot);
   SmcDetectOpeningGaps(rates,daily,weekly,config,symbol,tf,tick,snapshot);
   SmcDetectSessions(rates,minutes,config,symbol,tf,snapshot,coverageStart,coverageEnd);
  }

#endif
