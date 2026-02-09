//+------------------------------------------------------------------+
//|                                                SMC_Visualizer.mq5 |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_plots 0

#include <SMC/SmcManager.mqh>

//--- Input parameters
input bool   InpShowSwingPoints = true;        // Show Swing Points
input bool   InpShowStructure = true;         // Show Structure (BOS/CHoCH)
input bool   InpShowOrderBlocks = true;       // Show Order Blocks
input bool   InpShowFVG = true;               // Show Fair Value Gaps
input bool   InpShowLiquidity = true;         // Show Liquidity
input bool   InpShowPremiumDiscount = true;   // Show Premium/Discount
input bool   InpShowOTE = true;               // Show Optimal Trade Entry
input bool   InpShowKillZones = true;         // Show Kill Zones
input bool   InpShowBreakerBlocks = true;     // Show Breaker Blocks
input int    InpSwingPeriod = 5;             // Swing Period
input int    InpGMTOffset = 2;                // GMT Offset
input double InpMinFVGPips = 2.0;            // Minimum FVG Size (Pips)

//--- Global manager
CSmcManager *g_manager = NULL;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Create and initialize SmcManager
   g_manager = new CSmcManager();
   if(g_manager == NULL)
   {
      Print("Error: Failed to create CSmcManager");
      return INIT_FAILED;
   }
   
   //--- Initialize with symbol, period, and draw enabled
   if(!g_manager.Init(_Symbol, _Period, true))
   {
      Print("Error: Failed to initialize CSmcManager");
      delete g_manager;
      g_manager = NULL;
      return INIT_FAILED;
   }
   
   //--- Configure module settings
   if(g_manager.Swing() != NULL)
      g_manager.Swing().SetSwingPeriod(InpSwingPeriod);
   
   if(g_manager.FVG() != NULL)
      g_manager.FVG().SetMinSizePips(InpMinFVGPips);
   
   if(g_manager.KZ() != NULL)
      g_manager.KZ().SetGMTOffset(InpGMTOffset);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   //--- Only update on new bar
   if(prev_calculated == rates_total)
      return rates_total;
   
   //--- Update manager
   if(g_manager != NULL)
      g_manager.Update();
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Clean up manager
   if(g_manager != NULL)
   {
      g_manager.Clean();
      delete g_manager;
      g_manager = NULL;
   }
}

//+------------------------------------------------------------------+
