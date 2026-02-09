//+------------------------------------------------------------------+
//|                                                  SwingPoints.mqh |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_SWING_POINTS_MQH__
#define __SMC_SWING_POINTS_MQH__

#include "Core/SmcDrawing.mqh"

//+------------------------------------------------------------------+
//| CSmcSwingPoints - スイングポイント検出                             |
//|                                                                    |
//| 両側確認方式でスイングハイ/ローを検出する。                        |
//| 全SMCモジュールの基盤となるクラス。                                |
//+------------------------------------------------------------------+
class CSmcSwingPoints : public CSmcBase
  {
private:
   //--- 設定
   int               m_swingPeriod;    // 左右確認バー数 (default: 5)
   int               m_maxPoints;      // 最大保持ポイント数
   int               m_lookbackBars;   // 検索範囲バー数

   //--- データ
   SmcSwingPoint     m_swingHighs[];   // スイングハイ配列 (新しい順)
   SmcSwingPoint     m_swingLows[];    // スイングロー配列 (新しい順)
   int               m_highCount;      // 有効スイングハイ数
   int               m_lowCount;       // 有効スイングロー数

   //--- 描画色
   color             m_colorHigh;
   color             m_colorLow;

public:
                     CSmcSwingPoints();
                    ~CSmcSwingPoints();

   //--- 初期化
   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false,
                          const int swingPeriod = 5,
                          const int maxPoints = 50,
                          const int lookbackBars = 500);
   virtual bool      Update();
   virtual void      Clean();

   //--- 設定変更
   void              SetSwingPeriod(const int period) { m_swingPeriod = MathMax(1, period); }
   void              SetColors(const color highClr, const color lowClr)
     { m_colorHigh = highClr; m_colorLow = lowClr; }

   //--- スイングハイ取得
   int               GetHighCount() const { return m_highCount; }
   bool              GetSwingHigh(const int index, SmcSwingPoint &point) const;
   double            GetHighPrice(const int index) const;

   //--- スイングロー取得
   int               GetLowCount() const { return m_lowCount; }
   bool              GetSwingLow(const int index, SmcSwingPoint &point) const;
   double            GetLowPrice(const int index) const;

   //--- トレンド判定
   ENUM_SMC_TREND    GetTrendDirection() const;

   //--- ブレイク判定
   bool              IsHighBroken(const int index) const;
   bool              IsLowBroken(const int index) const;

   //--- 直近スイング取得 (ショートカット)
   double            LastSwingHigh()  const { return GetHighPrice(0); }
   double            LastSwingLow()   const { return GetLowPrice(0); }
   double            PrevSwingHigh()  const { return GetHighPrice(1); }
   double            PrevSwingLow()   const { return GetLowPrice(1); }

private:
   //--- 検出ロジック
   void              DetectSwingPoints();
   bool              IsSwingHigh(const int barIndex) const;
   bool              IsSwingLow(const int barIndex) const;
   int               CalcStrength(const int barIndex, const bool isHigh) const;

   //--- ブレイク状態更新
   void              UpdateBreakStatus();

   //--- ソート
   void              SortByBarIndex(SmcSwingPoint &arr[], const int count);

   //--- 描画
   void              DrawSwingPoints();
  };

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
CSmcSwingPoints::CSmcSwingPoints()
   : m_swingPeriod(5)
   , m_maxPoints(50)
   , m_lookbackBars(500)
   , m_highCount(0)
   , m_lowCount(0)
   , m_colorHigh(clrDeepPink)
   , m_colorLow(clrDodgerBlue)
  {
  }

//+------------------------------------------------------------------+
//| Destructor                                                         |
//+------------------------------------------------------------------+
CSmcSwingPoints::~CSmcSwingPoints()
  {
   ArrayFree(m_swingHighs);
   ArrayFree(m_swingLows);
  }

//+------------------------------------------------------------------+
//| 初期化                                                             |
//+------------------------------------------------------------------+
bool CSmcSwingPoints::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                           const bool enableDraw, const int swingPeriod,
                           const int maxPoints, const int lookbackBars)
  {
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   m_prefix       = "SMC_SW_";
   m_swingPeriod  = MathMax(1, swingPeriod);
   m_maxPoints    = MathMax(10, maxPoints);
   m_lookbackBars = MathMax(50, lookbackBars);

   ArrayResize(m_swingHighs, m_maxPoints);
   ArrayResize(m_swingLows, m_maxPoints);

   m_highCount = 0;
   m_lowCount  = 0;

   return true;
  }

//+------------------------------------------------------------------+
//| 更新                                                               |
//+------------------------------------------------------------------+
bool CSmcSwingPoints::Update()
  {
   if(!m_initialized)
      return false;

   m_highCount = 0;
   m_lowCount  = 0;

   DetectSwingPoints();
   UpdateBreakStatus();

   if(m_enableDraw)
      DrawSwingPoints();

   return true;
  }

//+------------------------------------------------------------------+
//| クリーンアップ                                                     |
//+------------------------------------------------------------------+
void CSmcSwingPoints::Clean()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   CSmcDrawing::Redraw();
  }

//+------------------------------------------------------------------+
//| スイングハイ取得                                                   |
//+------------------------------------------------------------------+
bool CSmcSwingPoints::GetSwingHigh(const int index, SmcSwingPoint &point) const
  {
   if(index < 0 || index >= m_highCount)
      return false;
   point = m_swingHighs[index];
   return true;
  }

double CSmcSwingPoints::GetHighPrice(const int index) const
  {
   if(index < 0 || index >= m_highCount)
      return 0;
   return m_swingHighs[index].price;
  }

//+------------------------------------------------------------------+
//| スイングロー取得                                                   |
//+------------------------------------------------------------------+
bool CSmcSwingPoints::GetSwingLow(const int index, SmcSwingPoint &point) const
  {
   if(index < 0 || index >= m_lowCount)
      return false;
   point = m_swingLows[index];
   return true;
  }

double CSmcSwingPoints::GetLowPrice(const int index) const
  {
   if(index < 0 || index >= m_lowCount)
      return 0;
   return m_swingLows[index].price;
  }

//+------------------------------------------------------------------+
//| トレンド方向判定                                                   |
//|                                                                    |
//| HH + HL = Bullish                                                  |
//| LH + LL = Bearish                                                  |
//| Otherwise = Ranging                                                |
//+------------------------------------------------------------------+
ENUM_SMC_TREND CSmcSwingPoints::GetTrendDirection() const
  {
   if(m_highCount < 2 || m_lowCount < 2)
      return SMC_TREND_RANGING;

   bool isHH = m_swingHighs[0].price > m_swingHighs[1].price;
   bool isHL = m_swingLows[0].price > m_swingLows[1].price;
   bool isLH = m_swingHighs[0].price < m_swingHighs[1].price;
   bool isLL = m_swingLows[0].price < m_swingLows[1].price;

   if(isHH && isHL)
      return SMC_TREND_BULLISH;
   if(isLH && isLL)
      return SMC_TREND_BEARISH;

   return SMC_TREND_RANGING;
  }

//+------------------------------------------------------------------+
//| スイングハイがブレイクされたか                                     |
//+------------------------------------------------------------------+
bool CSmcSwingPoints::IsHighBroken(const int index) const
  {
   if(index < 0 || index >= m_highCount)
      return false;
   return m_swingHighs[index].isBroken;
  }

//+------------------------------------------------------------------+
//| スイングローがブレイクされたか                                     |
//+------------------------------------------------------------------+
bool CSmcSwingPoints::IsLowBroken(const int index) const
  {
   if(index < 0 || index >= m_lowCount)
      return false;
   return m_swingLows[index].isBroken;
  }

//+------------------------------------------------------------------+
//| スイングポイント検出 (両側確認方式)                                |
//+------------------------------------------------------------------+
void CSmcSwingPoints::DetectSwingPoints()
  {
   int limit = MathMin(m_lookbackBars, iBars(m_symbol, m_timeframe) - m_swingPeriod - 1);

   for(int i = m_swingPeriod; i < limit; i++)
     {
      //--- スイングハイ検出
      if(IsSwingHigh(i) && m_highCount < m_maxPoints)
        {
         m_swingHighs[m_highCount].price    = High(i);
         m_swingHighs[m_highCount].time     = Time(i);
         m_swingHighs[m_highCount].barIndex = i;
         m_swingHighs[m_highCount].isHigh   = true;
         m_swingHighs[m_highCount].strength = CalcStrength(i, true);
         m_swingHighs[m_highCount].isBroken = false;
         m_swingHighs[m_highCount].isValid  = true;
         m_highCount++;
        }

      //--- スイングロー検出
      if(IsSwingLow(i) && m_lowCount < m_maxPoints)
        {
         m_swingLows[m_lowCount].price    = Low(i);
         m_swingLows[m_lowCount].time     = Time(i);
         m_swingLows[m_lowCount].barIndex = i;
         m_swingLows[m_lowCount].isHigh   = false;
         m_swingLows[m_lowCount].strength = CalcStrength(i, false);
         m_swingLows[m_lowCount].isBroken = false;
         m_swingLows[m_lowCount].isValid  = true;
         m_lowCount++;
        }
     }

//--- バーインデックスでソート (小さい=新しい順)
   SortByBarIndex(m_swingHighs, m_highCount);
   SortByBarIndex(m_swingLows, m_lowCount);
  }

//+------------------------------------------------------------------+
//| スイングハイ判定                                                   |
//+------------------------------------------------------------------+
bool CSmcSwingPoints::IsSwingHigh(const int barIndex) const
  {
   double high = High(barIndex);
   if(high == 0)
      return false;

//--- 左側チェック
   for(int i = 1; i <= m_swingPeriod; i++)
     {
      if(High(barIndex + i) >= high)
         return false;
     }

//--- 右側チェック
   for(int i = 1; i <= m_swingPeriod; i++)
     {
      if(High(barIndex - i) >= high)
         return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| スイングロー判定                                                   |
//+------------------------------------------------------------------+
bool CSmcSwingPoints::IsSwingLow(const int barIndex) const
  {
   double low = Low(barIndex);
   if(low == 0)
      return false;

//--- 左側チェック
   for(int i = 1; i <= m_swingPeriod; i++)
     {
      if(Low(barIndex + i) <= low)
         return false;
     }

//--- 右側チェック
   for(int i = 1; i <= m_swingPeriod; i++)
     {
      if(Low(barIndex - i) <= low)
         return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| スイング強度計算 (どれだけ広いレンジで確認されているか)            |
//+------------------------------------------------------------------+
int CSmcSwingPoints::CalcStrength(const int barIndex, const bool isHigh) const
  {
   int str = m_swingPeriod;

//--- 追加確認 (swingPeriod を超えてもまだ有効な場合は強度UP)
   int maxExtra = MathMin(m_swingPeriod * 2, 20);

   if(isHigh)
     {
      double high = High(barIndex);
      for(int i = m_swingPeriod + 1; i <= maxExtra; i++)
        {
         if(barIndex + i >= iBars(m_symbol, m_timeframe))
            break;
         if(High(barIndex + i) >= high)
            break;
         str++;
        }
     }
   else
     {
      double low = Low(barIndex);
      for(int i = m_swingPeriod + 1; i <= maxExtra; i++)
        {
         if(barIndex + i >= iBars(m_symbol, m_timeframe))
            break;
         if(Low(barIndex + i) <= low)
            break;
         str++;
        }
     }

   return str;
  }

//+------------------------------------------------------------------+
//| ブレイク状態更新                                                   |
//+------------------------------------------------------------------+
void CSmcSwingPoints::UpdateBreakStatus()
  {
   double currentHigh = High(0);
   double currentLow  = Low(0);

//--- スイングハイのブレイク判定
   for(int i = 0; i < m_highCount; i++)
     {
      if(!m_swingHighs[i].isBroken)
        {
         //--- 現在の高値がスイングハイを上回ったらブレイク
         for(int j = 0; j < m_swingHighs[i].barIndex; j++)
           {
            if(High(j) > m_swingHighs[i].price)
              {
               m_swingHighs[i].isBroken = true;
               break;
              }
           }
        }
     }

//--- スイングローのブレイク判定
   for(int i = 0; i < m_lowCount; i++)
     {
      if(!m_swingLows[i].isBroken)
        {
         for(int j = 0; j < m_swingLows[i].barIndex; j++)
           {
            if(Low(j) < m_swingLows[i].price)
              {
               m_swingLows[i].isBroken = true;
               break;
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| バーインデックス昇順ソート (新しい順)                              |
//+------------------------------------------------------------------+
void CSmcSwingPoints::SortByBarIndex(SmcSwingPoint &arr[], const int count)
  {
   for(int i = 0; i < count - 1; i++)
     {
      for(int j = i + 1; j < count; j++)
        {
         if(arr[j].barIndex < arr[i].barIndex)
           {
            SmcSwingPoint temp = arr[i];
            arr[i] = arr[j];
            arr[j] = temp;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| スイングポイント描画                                               |
//+------------------------------------------------------------------+
void CSmcSwingPoints::DrawSwingPoints()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);

   for(int i = 0; i < m_highCount; i++)
     {
      string name = m_prefix + "H_" + IntegerToString(i);
      CSmcDrawing::DrawArrow(name, m_swingHighs[i].time,
                             m_swingHighs[i].price, 159,
                             m_swingHighs[i].isBroken ? clrGray : m_colorHigh, 1);

      string label = m_prefix + "HL_" + IntegerToString(i);
      CSmcDrawing::DrawText(label, m_swingHighs[i].time,
                            m_swingHighs[i].price, "SH",
                            m_swingHighs[i].isBroken ? clrGray : m_colorHigh,
                            7, "Arial", ANCHOR_LOWER);
     }

   for(int i = 0; i < m_lowCount; i++)
     {
      string name = m_prefix + "L_" + IntegerToString(i);
      CSmcDrawing::DrawArrow(name, m_swingLows[i].time,
                             m_swingLows[i].price, 159,
                             m_swingLows[i].isBroken ? clrGray : m_colorLow, 1);

      string label = m_prefix + "LL_" + IntegerToString(i);
      CSmcDrawing::DrawText(label, m_swingLows[i].time,
                            m_swingLows[i].price, "SL",
                            m_swingLows[i].isBroken ? clrGray : m_colorLow,
                            7, "Arial", ANCHOR_UPPER);
     }

   CSmcDrawing::Redraw();
  }

#endif // __SMC_SWING_POINTS_MQH__
//+------------------------------------------------------------------+
