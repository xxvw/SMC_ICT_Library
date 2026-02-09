//+------------------------------------------------------------------+
//|                                                  SmcDrawing.mqh  |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_DRAWING_MQH__
#define __SMC_DRAWING_MQH__

#include "SmcBase.mqh"

//+------------------------------------------------------------------+
//| CSmcDrawing - チャート描画ユーティリティ                           |
//|                                                                    |
//| SMCゾーン、ライン、ラベルの描画を管理する静的ユーティリティクラス  |
//+------------------------------------------------------------------+
class CSmcDrawing
  {
public:
   //--- ゾーン描画 (矩形)
   static bool       DrawZone(const string name, const datetime time1,
                              const double price1, const datetime time2,
                              const double price2, const color clr,
                              const int opacity = 30, const bool fill = true,
                              const ENUM_LINE_STYLE style = STYLE_SOLID,
                              const int width = 1);

   //--- ゾーン拡張 (右端を現在時刻まで延長)
   static void       ExtendZone(const string name, const datetime time2);

   //--- 水平ライン
   static bool       DrawHLine(const string name, const double price,
                               const color clr, const int width = 1,
                               const ENUM_LINE_STYLE style = STYLE_SOLID);

   //--- トレンドライン
   static bool       DrawTrendLine(const string name, const datetime time1,
                                   const double price1, const datetime time2,
                                   const double price2, const color clr,
                                   const int width = 1,
                                   const ENUM_LINE_STYLE style = STYLE_SOLID,
                                   const bool ray = false);

   //--- 矢印マーカー
   static bool       DrawArrow(const string name, const datetime time,
                               const double price, const int code,
                               const color clr, const int size = 2);

   //--- テキストラベル (チャート上の価格/時間位置)
   static bool       DrawText(const string name, const datetime time,
                              const double price, const string text,
                              const color clr, const int fontSize = 8,
                              const string font = "Arial",
                              const ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT);

   //--- スクリーンラベル (固定位置テキスト)
   static bool       DrawLabel(const string name, const int x, const int y,
                               const string text, const color clr,
                               const int fontSize = 10,
                               const string font = "Arial",
                               const ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER,
                               const ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER);

   //--- パネル背景 (ダッシュボード用)
   static bool       DrawPanel(const string name, const int x, const int y,
                               const int width, const int height,
                               const color bgColor, const color borderColor,
                               const int borderWidth = 1);

   //--- オブジェクト削除
   static void       DeleteObject(const string name);
   static void       DeleteObjectsByPrefix(const string prefix);

   //--- チャート再描画
   static void       Redraw() { ChartRedraw(0); }

private:
   //--- アルファ値付きカラー生成
   static color      ApplyOpacity(const color clr, const int opacity);
  };

//+------------------------------------------------------------------+
//| ゾーン (矩形) 描画                                                |
//+------------------------------------------------------------------+
bool CSmcDrawing::DrawZone(const string name, const datetime time1,
                           const double price1, const datetime time2,
                           const double price2, const color clr,
                           const int opacity, const bool fill,
                           const ENUM_LINE_STYLE style,
                           const int width)
  {
   if(ObjectFind(0, name) >= 0)
     {
      //--- 既存オブジェクト更新
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, time1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price1);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, time2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price2);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      return true;
     }

   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2))
      return false;

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_FILL, fill);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   return true;
  }

//+------------------------------------------------------------------+
//| ゾーン右端を延長                                                   |
//+------------------------------------------------------------------+
void CSmcDrawing::ExtendZone(const string name, const datetime time2)
  {
   if(ObjectFind(0, name) >= 0)
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, time2);
  }

//+------------------------------------------------------------------+
//| 水平ライン描画                                                     |
//+------------------------------------------------------------------+
bool CSmcDrawing::DrawHLine(const string name, const double price,
                            const color clr, const int width,
                            const ENUM_LINE_STYLE style)
  {
   if(ObjectFind(0, name) >= 0)
     {
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      return true;
     }

   if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price))
      return false;

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   return true;
  }

//+------------------------------------------------------------------+
//| トレンドライン描画                                                 |
//+------------------------------------------------------------------+
bool CSmcDrawing::DrawTrendLine(const string name, const datetime time1,
                                const double price1, const datetime time2,
                                const double price2, const color clr,
                                const int width, const ENUM_LINE_STYLE style,
                                const bool ray)
  {
   if(ObjectFind(0, name) >= 0)
     {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, time1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price1);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, time2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price2);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      return true;
     }

   if(!ObjectCreate(0, name, OBJ_TREND, 0, time1, price1, time2, price2))
      return false;

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, ray);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   return true;
  }

//+------------------------------------------------------------------+
//| 矢印マーカー描画                                                   |
//+------------------------------------------------------------------+
bool CSmcDrawing::DrawArrow(const string name, const datetime time,
                            const double price, const int code,
                            const color clr, const int size)
  {
   if(ObjectFind(0, name) >= 0)
     {
      ObjectSetInteger(0, name, OBJPROP_TIME, time);
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      return true;
     }

   if(!ObjectCreate(0, name, OBJ_ARROW, 0, time, price))
      return false;

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, code);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, size);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   return true;
  }

//+------------------------------------------------------------------+
//| チャート上テキスト描画                                             |
//+------------------------------------------------------------------+
bool CSmcDrawing::DrawText(const string name, const datetime time,
                           const double price, const string text,
                           const color clr, const int fontSize,
                           const string font,
                           const ENUM_ANCHOR_POINT anchor)
  {
   if(ObjectFind(0, name) >= 0)
     {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_TIME, time);
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      return true;
     }

   if(!ObjectCreate(0, name, OBJ_TEXT, 0, time, price))
      return false;

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   return true;
  }

//+------------------------------------------------------------------+
//| スクリーンラベル描画                                               |
//+------------------------------------------------------------------+
bool CSmcDrawing::DrawLabel(const string name, const int x, const int y,
                            const string text, const color clr,
                            const int fontSize, const string font,
                            const ENUM_ANCHOR_POINT anchor,
                            const ENUM_BASE_CORNER corner)
  {
   if(ObjectFind(0, name) >= 0)
     {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      return true;
     }

   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
      return false;

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   return true;
  }

//+------------------------------------------------------------------+
//| ダッシュボード用パネル背景                                         |
//+------------------------------------------------------------------+
bool CSmcDrawing::DrawPanel(const string name, const int x, const int y,
                            const int width, const int height,
                            const color bgColor, const color borderColor,
                            const int borderWidth)
  {
   if(ObjectFind(0, name) >= 0)
     {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
      return true;
     }

   if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
      return false;

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, borderColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, borderWidth);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   return true;
  }

//+------------------------------------------------------------------+
//| オブジェクト削除                                                   |
//+------------------------------------------------------------------+
void CSmcDrawing::DeleteObject(const string name)
  {
   ObjectDelete(0, name);
  }

//+------------------------------------------------------------------+
//| プレフィックス一致のオブジェクト一括削除                           |
//+------------------------------------------------------------------+
void CSmcDrawing::DeleteObjectsByPrefix(const string prefix)
  {
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
     }
  }

//+------------------------------------------------------------------+
//| アルファ値適用 (現在のMQL5ではフル対応なし、参考実装)               |
//+------------------------------------------------------------------+
color CSmcDrawing::ApplyOpacity(const color clr, const int opacity)
  {
//--- MQL5では矩形のFILLプロパティで半透明効果を実現
//--- 実際のアルファブレンドはCanvas等が必要
   return clr;
  }

#endif // __SMC_DRAWING_MQH__
//+------------------------------------------------------------------+
