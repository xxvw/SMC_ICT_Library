//+------------------------------------------------------------------+
//|                                                SMC_Visualizer.mq5 |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, ICT_Library_MQ5     |
//+------------------------------------------------------------------+
#property copyright "ICT_Library_MQ5"
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
datetime g_lastBarTime = 0;
string g_statusObject = "";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   g_statusObject = "SMC_VIS_" + IntegerToString(ChartID()) + "_" +
                    IntegerToString((long)GetMicrosecondCount()) + "_STATUS";
   g_lastBarTime = 0;
   //--- Create and initialize SmcManager
   g_manager = new CSmcManager();
   if(g_manager == NULL)
   {
      Print("Error: Failed to create CSmcManager");
      return INIT_FAILED;
   }
   
   // Each displayed module is enabled explicitly below. This indicator does
   // not display currency-strength or VIX data and need not request them.
   if(!g_manager.Init(_Symbol, _Period, false, false, false))
   {
      Print("Error: Failed to initialize CSmcManager");
      delete g_manager;
      g_manager = NULL;
      return INIT_FAILED;
   }
   
   // Display settings affect rendering only; dependent detectors stay enabled.
   if(g_manager.Swing() != NULL)
     {
      g_manager.Swing().SetSwingPeriod(InpSwingPeriod);
      g_manager.Swing().SetDrawEnabled(InpShowSwingPoints);
     }
   if(g_manager.Structure() != NULL)
      g_manager.Structure().SetDrawEnabled(InpShowStructure);
   if(g_manager.OB() != NULL)
      g_manager.OB().SetDrawEnabled(InpShowOrderBlocks);
   if(g_manager.Liquidity() != NULL)
      g_manager.Liquidity().SetDrawEnabled(InpShowLiquidity);
   if(g_manager.PD() != NULL)
      g_manager.PD().SetDrawEnabled(InpShowPremiumDiscount);
   if(g_manager.OTE() != NULL)
      g_manager.OTE().SetDrawEnabled(InpShowOTE);
   if(g_manager.Breaker() != NULL)
      g_manager.Breaker().SetDrawEnabled(InpShowBreakerBlocks);
   
   if(g_manager.FVG() != NULL)
     {
      g_manager.FVG().SetMinSizePips(InpMinFVGPips);
      g_manager.FVG().SetDrawEnabled(InpShowFVG);
     }
   
   if(g_manager.KZ() != NULL)
     {
      g_manager.KZ().SetGMTOffset(InpGMTOffset);
      g_manager.KZ().SetDrawEnabled(InpShowKillZones);
     }
   
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
   if(g_manager == NULL || !g_manager.IsInitialized())
      return 0;
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime > 0 && prev_calculated > 0 && currentBarTime == g_lastBarTime)
      return rates_total;
   if(currentBarTime <= 0 || !g_manager.Update())
     {
      // Remove stale or partially redrawn results, then retry on the next tick.
      g_manager.Clean();
      CSmcDrawing::DrawLabel(g_statusObject, 10, 20,
                            "SMC: waiting for complete market data", clrOrange, 10);
      g_lastBarTime = 0;
      return 0;
     }
   ObjectDelete(0, g_statusObject);
   g_lastBarTime = currentBarTime;
   return rates_total;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0, g_statusObject);
   //--- Clean up manager
   if(g_manager != NULL)
   {
      g_manager.Clean();
      delete g_manager;
      g_manager = NULL;
   }
}

//+------------------------------------------------------------------+
