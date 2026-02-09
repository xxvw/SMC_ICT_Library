//+------------------------------------------------------------------+
//|                                                     SmcBase.mqh  |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_BASE_MQH__
#define __SMC_BASE_MQH__

#include "SmcTypes.mqh"

//+------------------------------------------------------------------+
//| CSmcBase - 全SMCモジュールの基底クラス                            |
//|                                                                    |
//| 共通機能:                                                          |
//|   - シンボル/タイムフレーム管理                                    |
//|   - Pips ⇔ Price 変換                                             |
//|   - ATR / 平均レンジ計算                                           |
//|   - チャートオブジェクト管理                                       |
//+------------------------------------------------------------------+
class CSmcBase
  {
protected:
   string            m_symbol;        // 対象シンボル
   ENUM_TIMEFRAMES   m_timeframe;     // 対象タイムフレーム
   double            m_point;         // 1ポイントの価格
   int               m_digits;        // 価格桁数
   double            m_pipSize;       // 1Pipの価格サイズ
   int               m_pipDigits;     // Pip桁数 (3桁/5桁通貨用)
   bool              m_enableDraw;    // チャート描画有効化
   string            m_prefix;        // チャートオブジェクト接頭辞
   int               m_atrHandle;     // ATRインジケーターハンドル
   bool              m_initialized;   // 初期化完了フラグ

public:
                     CSmcBase();
                    ~CSmcBase();

   //--- 初期化・更新
   virtual bool      Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false);
   virtual bool      Update() = 0;    // 純粋仮想: 各モジュールで実装
   virtual void      Clean();         // チャートオブジェクトの削除

   //--- アクセサ
   string            Symbol()       const { return m_symbol; }
   ENUM_TIMEFRAMES   Timeframe()    const { return m_timeframe; }
   bool              IsInitialized() const { return m_initialized; }
   bool              IsDrawEnabled() const { return m_enableDraw; }
   void              SetDrawEnabled(const bool enabled) { m_enableDraw = enabled; }

protected:
   //--- Pips変換
   double            PipsToPrice(const double pips) const;
   double            PriceToPips(const double priceDistance) const;
   double            NormalizePrice(const double price) const;

   //--- ボラティリティ
   double            GetATR(const int period = 14, const int shift = 0);
   double            GetAverageRange(const int period = 20, const int shift = 0);
   double            GetAverageCandleBody(const int period = 20, const int shift = 0);

   //--- 価格データアクセス
   double            High(const int shift)  const;
   double            Low(const int shift)   const;
   double            Open(const int shift)  const;
   double            Close(const int shift) const;
   long              Volume(const int shift) const;
   datetime          Time(const int shift)  const;

   //--- ローソク足判定
   bool              IsBullishCandle(const int shift) const;
   bool              IsBearishCandle(const int shift) const;
   double            CandleBody(const int shift) const;
   double            CandleRange(const int shift) const;
   double            UpperWick(const int shift) const;
   double            LowerWick(const int shift) const;

   //--- ユーティリティ
   void              DetectPipSize();
  };

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
CSmcBase::CSmcBase()
   : m_symbol("")
   , m_timeframe(PERIOD_CURRENT)
   , m_point(0)
   , m_digits(0)
   , m_pipSize(0)
   , m_pipDigits(0)
   , m_enableDraw(false)
   , m_prefix("SMC_")
   , m_atrHandle(INVALID_HANDLE)
   , m_initialized(false)
  {
  }

//+------------------------------------------------------------------+
//| Destructor                                                         |
//+------------------------------------------------------------------+
CSmcBase::~CSmcBase()
  {
   if(m_atrHandle != INVALID_HANDLE)
     {
      IndicatorRelease(m_atrHandle);
      m_atrHandle = INVALID_HANDLE;
     }
   Clean();
  }

//+------------------------------------------------------------------+
//| 初期化                                                             |
//+------------------------------------------------------------------+
bool CSmcBase::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                    const bool enableDraw)
  {
   m_symbol     = (symbol == "" || symbol == "0") ? _Symbol : symbol;
   m_timeframe  = (timeframe == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : timeframe;
   m_enableDraw = enableDraw;

//--- シンボル情報取得
   m_point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

   if(m_point == 0)
     {
      Print("[SMC] Error: Invalid symbol - ", m_symbol);
      return false;
     }

//--- Pipサイズ検出
   DetectPipSize();

//--- ATRインジケーター作成
   m_atrHandle = iATR(m_symbol, m_timeframe, 14);
   if(m_atrHandle == INVALID_HANDLE)
     {
      Print("[SMC] Warning: Failed to create ATR indicator for ", m_symbol);
     }

   m_initialized = true;
   return true;
  }

//+------------------------------------------------------------------+
//| チャートオブジェクトの削除                                         |
//+------------------------------------------------------------------+
void CSmcBase::Clean()
  {
   if(!m_enableDraw)
      return;

   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i);
      if(StringFind(name, m_prefix) == 0)
         ObjectDelete(0, name);
     }
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Pips値を価格差に変換                                               |
//+------------------------------------------------------------------+
double CSmcBase::PipsToPrice(const double pips) const
  {
   return NormalizeDouble(pips * m_pipSize, m_digits);
  }

//+------------------------------------------------------------------+
//| 価格差をPips値に変換                                               |
//+------------------------------------------------------------------+
double CSmcBase::PriceToPips(const double priceDistance) const
  {
   if(m_pipSize == 0)
      return 0;
   return NormalizeDouble(priceDistance / m_pipSize, 1);
  }

//+------------------------------------------------------------------+
//| 価格を正規化                                                       |
//+------------------------------------------------------------------+
double CSmcBase::NormalizePrice(const double price) const
  {
   return NormalizeDouble(price, m_digits);
  }

//+------------------------------------------------------------------+
//| ATR取得                                                            |
//+------------------------------------------------------------------+
double CSmcBase::GetATR(const int period, const int shift)
  {
   if(m_atrHandle == INVALID_HANDLE)
     {
      //--- フォールバック: 手動計算
      return GetAverageRange(period, shift);
     }

   double buffer[];
   ArraySetAsSeries(buffer, true);
   if(CopyBuffer(m_atrHandle, 0, shift, 1, buffer) <= 0)
      return GetAverageRange(period, shift);

   return buffer[0];
  }

//+------------------------------------------------------------------+
//| 平均レンジ (High - Low) 取得                                       |
//+------------------------------------------------------------------+
double CSmcBase::GetAverageRange(const int period, const int shift)
  {
   double sum = 0;
   int count  = 0;

   for(int i = shift; i < shift + period; i++)
     {
      double range = High(i) - Low(i);
      if(range > 0)
        {
         sum += range;
         count++;
        }
     }

   return (count > 0) ? sum / count : 0;
  }

//+------------------------------------------------------------------+
//| 平均ローソク足実体サイズ取得                                       |
//+------------------------------------------------------------------+
double CSmcBase::GetAverageCandleBody(const int period, const int shift)
  {
   double sum = 0;
   int count  = 0;

   for(int i = shift; i < shift + period; i++)
     {
      double body = CandleBody(i);
      if(body > 0)
        {
         sum += body;
         count++;
        }
     }

   return (count > 0) ? sum / count : 0;
  }

//+------------------------------------------------------------------+
//| 各価格データへのアクセス                                           |
//+------------------------------------------------------------------+
double CSmcBase::High(const int shift) const
  {
   return iHigh(m_symbol, m_timeframe, shift);
  }

double CSmcBase::Low(const int shift) const
  {
   return iLow(m_symbol, m_timeframe, shift);
  }

double CSmcBase::Open(const int shift) const
  {
   return iOpen(m_symbol, m_timeframe, shift);
  }

double CSmcBase::Close(const int shift) const
  {
   return iClose(m_symbol, m_timeframe, shift);
  }

long CSmcBase::Volume(const int shift) const
  {
   return iVolume(m_symbol, m_timeframe, shift);
  }

datetime CSmcBase::Time(const int shift) const
  {
   return iTime(m_symbol, m_timeframe, shift);
  }

//+------------------------------------------------------------------+
//| ローソク足判定                                                     |
//+------------------------------------------------------------------+
bool CSmcBase::IsBullishCandle(const int shift) const
  {
   return Close(shift) > Open(shift);
  }

bool CSmcBase::IsBearishCandle(const int shift) const
  {
   return Close(shift) < Open(shift);
  }

double CSmcBase::CandleBody(const int shift) const
  {
   return MathAbs(Close(shift) - Open(shift));
  }

double CSmcBase::CandleRange(const int shift) const
  {
   return High(shift) - Low(shift);
  }

double CSmcBase::UpperWick(const int shift) const
  {
   return High(shift) - MathMax(Open(shift), Close(shift));
  }

double CSmcBase::LowerWick(const int shift) const
  {
   return MathMin(Open(shift), Close(shift)) - Low(shift);
  }

//+------------------------------------------------------------------+
//| Pipサイズ自動検出                                                  |
//|                                                                    |
//| FX 5桁: point=0.00001, pipSize=0.0001                              |
//| FX 3桁: point=0.001,   pipSize=0.01                                |
//| Gold:   point=0.01,    pipSize=0.1 (or 1.0 depending on broker)   |
//| Index:  point=0.01,    pipSize=1.0                                 |
//+------------------------------------------------------------------+
void CSmcBase::DetectPipSize()
  {
//--- FX ペアの場合 (5桁 or 3桁)
   if(m_digits == 5 || m_digits == 3)
     {
      m_pipSize   = m_point * 10;
      m_pipDigits = m_digits - 1;
     }
//--- FX ペア (4桁 or 2桁)
   else if(m_digits == 4 || m_digits == 2)
     {
      m_pipSize   = m_point;
      m_pipDigits = m_digits;
     }
//--- ゴールド / 指数 (1桁 or 0桁)
   else
     {
      m_pipSize   = m_point * 10;
      m_pipDigits = MathMax(0, m_digits - 1);
     }
  }

#endif // __SMC_BASE_MQH__
//+------------------------------------------------------------------+
