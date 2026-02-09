//+------------------------------------------------------------------+
//|                                              SMC_Sample_EA.mq5  |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#include <SMC/SmcManager.mqh>
#include <Trade/Trade.mqh>
#include <SMC/Utils/TradeUtils.mqh>
#include <SMC/Core/SmcDrawing.mqh>

//+------------------------------------------------------------------+
//| 入力パラメータ                                                     |
//+------------------------------------------------------------------+
input group "=== リスク管理 ==="
input double InpRiskPercent = 1.0;                    // リスク率 (%)
input double InpMaxSpreadPips = 3.0;                  // 最大スプレッド (pips)

input group "=== コンフルエンス設定 ==="
input int    InpMinConfluence = 3;                     // 最小コンフルエンス要因数
input double InpMinScore = 0.5;                        // 最小コンフルエンススコア

input group "=== フィルター設定 ==="
input bool   InpEnableKillZoneFilter = true;           // キルゾーンフィルター有効
input bool   InpEnableCurrencyStrengthFilter = false;  // 通貨強弱フィルター有効
input bool   InpEnableVIXFilter = true;                // VIXフィルター有効

input group "=== その他設定 ==="
input int    InpMagicNumber = 20260209;               // マジックナンバー
input int    InpSwingPeriod = 5;                       // スイング期間
input int    InpGMTOffset = 2;                        // GMTオフセット
input bool   InpEnableDashboard = true;               // ダッシュボード表示

//+------------------------------------------------------------------+
//| グローバル変数                                                     |
//+------------------------------------------------------------------+
CSmcManager *g_smc = NULL;
CTrade       g_trade;
datetime     g_lastBarTime = 0;
string       g_dashboardPrefix = "SMC_EA_DASH_";

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- SMCマネージャー初期化
   g_smc = new CSmcManager();
   if(g_smc == NULL)
     {
      Print("[SMC Sample EA] Failed to create SMC Manager");
      return INIT_FAILED;
     }

   //--- SMCマネージャー設定
   if(!g_smc.Init(_Symbol, PERIOD_CURRENT, false, 
                  InpEnableCurrencyStrengthFilter, InpEnableVIXFilter))
     {
      Print("[SMC Sample EA] Failed to initialize SMC Manager");
      delete g_smc;
      g_smc = NULL;
      return INIT_FAILED;
     }

   //--- スイング期間設定
   if(g_smc.Swing() != NULL)
      g_smc.Swing()->SetSwingPeriod(InpSwingPeriod);

   //--- GMTオフセット設定
   if(g_smc.KZ() != NULL)
      g_smc.KZ()->SetGMTOffset(InpGMTOffset);

   //--- コンフルエンス設定
   if(g_smc.Confluence() != NULL)
     {
      g_smc.Confluence()->SetMinConfluence(InpMinConfluence);
      g_smc.Confluence()->SetMinScore(InpMinScore);
     }

   //--- トレード設定
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   g_trade.SetAsyncMode(false);

   //--- 初期更新
   g_smc.Update();

   Print("[SMC Sample EA] Initialized successfully");
   Print("[SMC Sample EA] Symbol: ", _Symbol, ", Timeframe: ", EnumToString(PERIOD_CURRENT));
   Print("[SMC Sample EA] Risk: ", InpRiskPercent, "%, Max Spread: ", InpMaxSpreadPips, " pips");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- ダッシュボード削除
   if(InpEnableDashboard)
      CSmcDrawing::DeleteObjectsByPrefix(g_dashboardPrefix);

   //--- SMCマネージャークリーンアップ
   if(g_smc != NULL)
     {
      g_smc.Clean();
      delete g_smc;
      g_smc = NULL;
     }

   Print("[SMC Sample EA] Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 新規バーチェック
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool isNewBar = (currentBarTime != g_lastBarTime);
   if(isNewBar)
      g_lastBarTime = currentBarTime;

   //--- SMC更新
   if(g_smc == NULL || !g_smc.IsInitialized())
      return;

   if(isNewBar)
      g_smc.Update();

   //--- フィルターチェック
   if(!CheckFilters())
      return;

   //--- シグナル取得
   ENUM_ENTRY_SIGNAL signal = g_smc.GetSignal();
   if(signal == SIGNAL_WAIT)
     {
      if(InpEnableDashboard)
         DrawDashboard();
      return;
     }

   //--- 既存ポジション確認
   if(PositionSelect(_Symbol))
     {
      if(InpEnableDashboard)
         DrawDashboard();
      return;
     }

   //--- エントリー処理
   if(signal == SIGNAL_BUY)
      OpenBuyTrade();
   else if(signal == SIGNAL_SELL)
      OpenSellTrade();

   //--- ダッシュボード更新
   if(InpEnableDashboard)
      DrawDashboard();
}

//+------------------------------------------------------------------+
//| フィルターチェック                                                 |
//+------------------------------------------------------------------+
bool CheckFilters()
{
   //--- スプレッドチェック
   double spreadPips = CSmcTradeUtils::GetSpreadPips(_Symbol);
   if(spreadPips > InpMaxSpreadPips)
     {
      if(InpEnableDashboard)
         DrawDashboard();
      return false;
     }

   //--- VIXフィルター
   if(InpEnableVIXFilter && g_smc.VIX() != NULL)
     {
      if(!g_smc.VIX()->IsEntryAllowed())
         return false;
     }

   //--- キルゾーンフィルター
   if(InpEnableKillZoneFilter && g_smc.KZ() != NULL)
     {
      if(!g_smc.KZ()->IsInKillZone())
         return false;
     }

   //--- 通貨強弱フィルター
   if(InpEnableCurrencyStrengthFilter && g_smc.CurrStr() != NULL)
     {
      // ここでは基本的なチェックのみ
      // より詳細なフィルタリングが必要な場合は追加実装
     }

   return true;
}

//+------------------------------------------------------------------+
//| 買いエントリー処理                                                 |
//+------------------------------------------------------------------+
void OpenBuyTrade()
{
   //--- 最寄りの強気OB検索
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   SmcZone ob;
   if(g_smc.OB() == NULL || !g_smc.OB()->GetNearestBullishOB(currentPrice, ob))
     {
      Print("[SMC Sample EA] No bullish OB found for buy entry");
      return;
     }

   //--- ストップロス計算
   double sl = g_smc.OB()->GetStopLossForBuy(ob);
   double slPips = PriceToPips(currentPrice - sl);

   if(slPips <= 0)
     {
      Print("[SMC Sample EA] Invalid stop loss for buy");
      return;
     }

   //--- ロットサイズ計算
   double lotSize = CSmcTradeUtils::CalcLotByRisk(_Symbol, InpRiskPercent, slPips);
   if(lotSize <= 0)
     {
      Print("[SMC Sample EA] Invalid lot size calculated: ", lotSize);
      return;
     }

   //--- エントリー価格
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   //--- テイクプロフィット計算（リスクリワード比 1:2）
   double tp = entryPrice + (entryPrice - sl) * 2.0;

   //--- 買い注文実行
   if(g_trade.Buy(lotSize, _Symbol, entryPrice, sl, tp, "SMC Buy Signal"))
     {
      Print("[SMC Sample EA] Buy order opened: Lot=", lotSize, 
            ", Entry=", entryPrice, ", SL=", sl, ", TP=", tp);
     }
   else
     {
      Print("[SMC Sample EA] Failed to open buy order. Error: ", GetLastError());
     }
}

//+------------------------------------------------------------------+
//| 売りエントリー処理                                                 |
//+------------------------------------------------------------------+
void OpenSellTrade()
{
   //--- 最寄りの弱気OB検索
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   SmcZone ob;
   if(g_smc.OB() == NULL || !g_smc.OB()->GetNearestBearishOB(currentPrice, ob))
     {
      Print("[SMC Sample EA] No bearish OB found for sell entry");
      return;
     }

   //--- ストップロス計算
   double sl = g_smc.OB()->GetStopLossForSell(ob);
   double slPips = PriceToPips(sl - currentPrice);

   if(slPips <= 0)
     {
      Print("[SMC Sample EA] Invalid stop loss for sell");
      return;
     }

   //--- ロットサイズ計算
   double lotSize = CSmcTradeUtils::CalcLotByRisk(_Symbol, InpRiskPercent, slPips);
   if(lotSize <= 0)
     {
      Print("[SMC Sample EA] Invalid lot size calculated: ", lotSize);
      return;
     }

   //--- エントリー価格
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- テイクプロフィット計算（リスクリワード比 1:2）
   double tp = entryPrice - (sl - entryPrice) * 2.0;

   //--- 売り注文実行
   if(g_trade.Sell(lotSize, _Symbol, entryPrice, sl, tp, "SMC Sell Signal"))
     {
      Print("[SMC Sample EA] Sell order opened: Lot=", lotSize, 
            ", Entry=", entryPrice, ", SL=", sl, ", TP=", tp);
     }
   else
     {
      Print("[SMC Sample EA] Failed to open sell order. Error: ", GetLastError());
     }
}

//+------------------------------------------------------------------+
//| ダッシュボード描画                                                 |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   if(g_smc == NULL || !g_smc.IsInitialized())
      return;

   int x = 10;
   int y = 30;
   int lineHeight = 18;
   int panelWidth = 300;
   int panelHeight = 350;
   color bgColor = C'30,30,30';
   color borderColor = clrGray;
   color textColor = clrWhite;

   //--- パネル背景
   CSmcDrawing::DrawPanel(g_dashboardPrefix + "BG", x, y, panelWidth, panelHeight, 
                          bgColor, borderColor, 1);

   int currentY = y + 10;
   string text = "";
   color signalColor = clrGray;

   //--- タイトル
   CSmcDrawing::DrawLabel(g_dashboardPrefix + "Title", x + 10, currentY, 
                          "=== SMC Sample EA ===", clrYellow, 11);
   currentY += lineHeight + 5;

   //--- トレンド
   ENUM_SMC_TREND trend = g_smc.GetTrend();
   string trendText = "Trend: ";
   color trendColor = clrGray;
   switch(trend)
     {
      case SMC_TREND_BULLISH:
         trendText += "BULLISH";
         trendColor = clrLime;
         break;
      case SMC_TREND_BEARISH:
         trendText += "BEARISH";
         trendColor = clrRed;
         break;
      case SMC_TREND_RANGING:
         trendText += "RANGING";
         trendColor = clrYellow;
         break;
     }
   CSmcDrawing::DrawLabel(g_dashboardPrefix + "Trend", x + 10, currentY, 
                          trendText, trendColor, 10);
   currentY += lineHeight;

   //--- BOS/CHoCH状態
   string bosChochText = "BOS/CHoCH: ";
   if(g_smc.Structure() != NULL)
     {
      if(g_smc.Structure()->HasRecentBOS(10))
         bosChochText += "BOS ";
      if(g_smc.Structure()->HasRecentCHoCH(10))
         bosChochText += "CHoCH";
      if(!g_smc.Structure()->HasRecentBOS(10) && !g_smc.Structure()->HasRecentCHoCH(10))
         bosChochText += "None";
     }
   else
      bosChochText += "N/A";
   CSmcDrawing::DrawLabel(g_dashboardPrefix + "BOSCHoCH", x + 10, currentY, 
                          bosChochText, textColor, 9);
   currentY += lineHeight;

   //--- OB数
   int obCount = 0;
   if(g_smc.OB() != NULL)
      obCount = g_smc.OB()->GetBullishCount() + g_smc.OB()->GetBearishCount();
   CSmcDrawing::DrawLabel(g_dashboardPrefix + "OB", x + 10, currentY, 
                          "OB Count: " + IntegerToString(obCount), textColor, 9);
   currentY += lineHeight;

   //--- FVG数
   int fvgCount = 0;
   if(g_smc.FVG() != NULL)
      fvgCount = g_smc.FVG()->GetBullishCount() + g_smc.FVG()->GetBearishCount();
   CSmcDrawing::DrawLabel(g_dashboardPrefix + "FVG", x + 10, currentY, 
                          "FVG Count: " + IntegerToString(fvgCount), textColor, 9);
   currentY += lineHeight;

   //--- VIXレベル
   string vixText = "VIX: ";
   if(g_smc.VIX() != NULL)
     {
      double vix = g_smc.VIX()->GetVIX();
      vixText += DoubleToString(vix, 2) + " (" + g_smc.VIX()->GetVIXLevelName() + ")";
     }
   else
      vixText += "N/A";
   CSmcDrawing::DrawLabel(g_dashboardPrefix + "VIX", x + 10, currentY, 
                          vixText, textColor, 9);
   currentY += lineHeight;

   //--- 通貨強弱 Top 3
   string csText = "CS Top 3: ";
   if(g_smc.CurrStr() != NULL)
     {
      string sorted[];
      g_smc.CurrStr()->GetSortedCurrencies(sorted);
      if(ArraySize(sorted) >= 3)
         csText += sorted[0] + " " + sorted[1] + " " + sorted[2];
      else
         csText += "N/A";
     }
   else
      csText += "N/A";
   CSmcDrawing::DrawLabel(g_dashboardPrefix + "CS", x + 10, currentY, 
                          csText, textColor, 9);
   currentY += lineHeight;

   //--- シグナル
   ENUM_ENTRY_SIGNAL signal = g_smc.GetSignal();
   string signalText = "Signal: ";
   switch(signal)
     {
      case SIGNAL_BUY:
         signalText += "BUY";
         signalColor = clrLime;
         break;
      case SIGNAL_SELL:
         signalText += "SELL";
         signalColor = clrRed;
         break;
      case SIGNAL_WAIT:
         signalText += "WAIT";
         signalColor = clrGray;
         break;
     }
   CSmcDrawing::DrawLabel(g_dashboardPrefix + "Signal", x + 10, currentY, 
                          signalText, signalColor, 10);
   currentY += lineHeight;

   //--- コンフルエンススコア
   string scoreText = "Score: ";
   double score = 0.0;
   if(g_smc.Confluence() != NULL)
     {
      SmcConfluenceZone zone;
      if(signal == SIGNAL_BUY && g_smc.Confluence()->GetBuyZone(zone))
         score = zone.totalScore;
      else if(signal == SIGNAL_SELL && g_smc.Confluence()->GetSellZone(zone))
         score = zone.totalScore;
     }
   scoreText += DoubleToString(score, 2);
   CSmcDrawing::DrawLabel(g_dashboardPrefix + "Score", x + 10, currentY, 
                          scoreText, textColor, 9);
   currentY += lineHeight;

   //--- スプレッド
   double spread = CSmcTradeUtils::GetSpreadPips(_Symbol);
   string spreadText = "Spread: " + DoubleToString(spread, 1) + " pips";
   color spreadColor = (spread <= InpMaxSpreadPips) ? clrLime : clrRed;
   CSmcDrawing::DrawLabel(g_dashboardPrefix + "Spread", x + 10, currentY, 
                          spreadText, spreadColor, 9);
   currentY += lineHeight;

   //--- キルゾーン状態
   string kzText = "Kill Zone: ";
   if(g_smc.KZ() != NULL)
     {
      if(g_smc.KZ()->IsInKillZone())
         kzText += "YES";
      else
         kzText += "NO";
     }
   else
      kzText += "N/A";
   CSmcDrawing::DrawLabel(g_dashboardPrefix + "KZ", x + 10, currentY, 
                          kzText, textColor, 9);

   //--- チャート再描画
   CSmcDrawing::Redraw();
}

//+------------------------------------------------------------------+
//| 価格をピップに変換                                                 |
//+------------------------------------------------------------------+
double PriceToPips(const double priceDistance)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0)
      return 0;

   //--- JPYペアまたはXAUの場合は1ポイント=1ピップ
   if(StringFind(_Symbol, "JPY") >= 0 || StringFind(_Symbol, "XAU") >= 0)
      return priceDistance / point;

   //--- その他の通貨ペアは10ポイント=1ピップ
   return priceDistance / (point * 10.0);
}
//+------------------------------------------------------------------+
