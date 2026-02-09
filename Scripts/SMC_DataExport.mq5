//+------------------------------------------------------------------+
//|                                            SMC_DataExport.mq5    |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property script_show_inputs

#include <SMC/Utils/DataExporter.mqh>

//--- Input parameters
input string InpSymbol = "";                    // Symbol (empty = current)
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5; // Timeframe
input int InpBars = 50000;                      // Number of bars to export
input bool InpExportOHLCV = true;               // Export OHLCV data
input bool InpExportIndicators = true;          // Export with indicators
input bool InpExportSmcFeatures = true;         // Export SMC features
input string InpOutputFolder = "SMC_Export";    // Output folder name

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
   // Determine symbol
   string symbol = (InpSymbol == "") ? _Symbol : InpSymbol;
   
   // Validate symbol
   if(!SymbolInfoInteger(symbol, SYMBOL_SELECT))
     {
      Print("Error: Symbol '", symbol, "' not found or not available");
      return;
     }
   
   // Create output folder path (using FILE_COMMON)
   string folderPath = InpOutputFolder;
   
   // Track export results
   int filesCreated = 0;
   int totalRows = 0;
   bool success = true;
   
   Print("=== SMC Data Export Started ===");
   Print("Symbol: ", symbol);
   Print("Timeframe: ", EnumToString(InpTimeframe));
   Print("Bars: ", InpBars);
   Print("Output Folder: ", folderPath);
   Print("--------------------------------");
   
   // Export OHLCV data
   if(InpExportOHLCV)
     {
      string filenameOHLCV = folderPath + "\\" + symbol + "_" + 
                             IntegerToString(InpTimeframe) + "_OHLCV.csv";
      
      Print("Exporting OHLCV data to: ", filenameOHLCV);
      
      if(CSmcDataExporter::ExportOHLCV(symbol, InpTimeframe, InpBars, filenameOHLCV))
        {
         filesCreated++;
         totalRows += InpBars;
         Print("  ✓ OHLCV export completed: ", InpBars, " rows");
        }
      else
        {
         Print("  ✗ OHLCV export failed");
         success = false;
        }
     }
   
   // Export with indicators
   if(InpExportIndicators)
     {
      string filenameIndicators = folderPath + "\\" + symbol + "_" + 
                                  IntegerToString(InpTimeframe) + "_Indicators.csv";
      
      Print("Exporting data with indicators to: ", filenameIndicators);
      
      if(CSmcDataExporter::ExportWithIndicators(symbol, InpTimeframe, InpBars, filenameIndicators))
        {
         filesCreated++;
         totalRows += InpBars;
         Print("  ✓ Indicators export completed: ", InpBars, " rows");
        }
      else
        {
         Print("  ✗ Indicators export failed");
         success = false;
        }
     }
   
   // Export SMC features
   if(InpExportSmcFeatures)
     {
      string filenameSmcFeatures = folderPath + "\\" + symbol + "_" + 
                                   IntegerToString(InpTimeframe) + "_SMCFeatures.csv";
      
      Print("Exporting SMC features to: ", filenameSmcFeatures);
      
      if(CSmcDataExporter::ExportSmcFeatures(symbol, InpTimeframe, InpBars, filenameSmcFeatures))
        {
         filesCreated++;
         totalRows += InpBars;
         Print("  ✓ SMC features export completed: ", InpBars, " rows");
        }
      else
        {
         Print("  ✗ SMC features export failed");
         success = false;
        }
     }
   
   // Print summary
   Print("--------------------------------");
   Print("=== Export Summary ===");
   Print("Files created: ", filesCreated);
   Print("Total rows exported: ", totalRows);
   
   if(success)
      Print("Status: All exports completed successfully");
   else
      Print("Status: Some exports failed - check errors above");
   
   Print("=== Export Finished ===");
  }
//+------------------------------------------------------------------+
