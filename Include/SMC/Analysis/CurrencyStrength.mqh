//+------------------------------------------------------------------+
//|                                            CurrencyStrength.mqh  |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_CURRENCY_STRENGTH_MQH__
#define __SMC_CURRENCY_STRENGTH_MQH__

#include "../Core/SmcBase.mqh"

#define CS_CURRENCY_COUNT  8
#define CS_PAIR_COUNT      28

//+------------------------------------------------------------------+
//| CSmcCurrencyStrength - 8通貨の相対強弱分析                         |
//|                                                                    |
//| USD, EUR, GBP, JPY, AUD, CAD, NZD, CHF の28ペアから               |
//| 各通貨の相対強弱を算出。                                           |
//+------------------------------------------------------------------+
class CSmcCurrencyStrength : public CSmcBase
  {
private:
   //--- 通貨リスト
   string            m_currencies[CS_CURRENCY_COUNT];

   //--- ペアリスト
   string            m_pairs[CS_PAIR_COUNT];
   int               m_pairBase[CS_PAIR_COUNT];     // ベース通貨インデックス
   int               m_pairQuote[CS_PAIR_COUNT];    // クォート通貨インデックス
   bool              m_pairAvailable[CS_PAIR_COUNT]; // ブローカーで利用可能か
   string            m_pairSymbol[CS_PAIR_COUNT];    // 実際のシンボル名

   //--- 設定
   ENUM_CS_METHOD    m_method;
   int               m_period;       // 計算期間
   ENUM_TIMEFRAMES   m_calcTF;       // 計算タイムフレーム

   //--- 結果
   SmcCurrencyInfo   m_info[CS_CURRENCY_COUNT];
   double            m_prevStrength[CS_CURRENCY_COUNT]; // 前回の強弱値

public:
                     CSmcCurrencyStrength();
                    ~CSmcCurrencyStrength();

   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false,
                          const ENUM_CS_METHOD method = CS_METHOD_RATE_CHANGE,
                          const int period = 10);
   virtual bool      Update();
   virtual void      Clean();

   //--- 設定変更
   void              SetMethod(const ENUM_CS_METHOD method) { m_method = method; }
   void              SetPeriod(const int period) { m_period = MathMax(1, period); }

   //--- 強弱取得
   double            GetStrength(const string currency) const;
   double            GetMomentum(const string currency) const;
   int               GetRank(const string currency) const;
   bool              GetCurrencyInfo(const string currency, SmcCurrencyInfo &info) const;

   //--- ランキング
   string            GetStrongest() const;
   string            GetWeakest() const;
   string            GetBestPair() const;  // 最強 vs 最弱
   void              GetSortedCurrencies(string &sorted[]) const;

   //--- ダイバージェンス
   bool              IsStrongVsWeak(const string base, const string quote) const;

private:
   void              InitCurrencies();
   void              InitPairs();
   string            FindBrokerSymbol(const string pair) const;
   void              CalcByRateChange();
   void              CalcByRSI();
   void              NormalizeStrengths();
   void              CalcMomentum();
   void              CalcRanks();
   int               FindCurrencyIndex(const string currency) const;
  };

//+------------------------------------------------------------------+
CSmcCurrencyStrength::CSmcCurrencyStrength()
   : m_method(CS_METHOD_RATE_CHANGE)
   , m_period(10)
   , m_calcTF(PERIOD_M5)
  {
   InitCurrencies();
   ArrayInitialize(m_prevStrength, 0);
  }

CSmcCurrencyStrength::~CSmcCurrencyStrength() {}

//+------------------------------------------------------------------+
void CSmcCurrencyStrength::InitCurrencies()
  {
   m_currencies[0] = "USD";
   m_currencies[1] = "EUR";
   m_currencies[2] = "GBP";
   m_currencies[3] = "JPY";
   m_currencies[4] = "AUD";
   m_currencies[5] = "CAD";
   m_currencies[6] = "NZD";
   m_currencies[7] = "CHF";

   for(int i = 0; i < CS_CURRENCY_COUNT; i++)
     {
      m_info[i].Init();
      m_info[i].name = m_currencies[i];
     }
  }

//+------------------------------------------------------------------+
void CSmcCurrencyStrength::InitPairs()
  {
   int idx = 0;
   for(int i = 0; i < CS_CURRENCY_COUNT; i++)
     {
      for(int j = i + 1; j < CS_CURRENCY_COUNT; j++)
        {
         m_pairs[idx]       = m_currencies[i] + m_currencies[j];
         m_pairBase[idx]    = i;
         m_pairQuote[idx]   = j;
         m_pairSymbol[idx]  = FindBrokerSymbol(m_pairs[idx]);
         m_pairAvailable[idx] = (m_pairSymbol[idx] != "");
         idx++;
        }
     }
  }

//+------------------------------------------------------------------+
string CSmcCurrencyStrength::FindBrokerSymbol(const string pair) const
  {
//--- 様々なブローカーの命名規則を試行
   string suffixes[] = {"", "m", ".ecn", ".pro", ".raw", ".", "_", ".i", "pro", ".std"};

   for(int i = 0; i < ArraySize(suffixes); i++)
     {
      string testSymbol = pair + suffixes[i];
      if(SymbolInfoDouble(testSymbol, SYMBOL_BID) > 0)
         return testSymbol;
     }

//--- 逆ペアも試行
   string reverse = StringSubstr(pair, 3, 3) + StringSubstr(pair, 0, 3);
   for(int i = 0; i < ArraySize(suffixes); i++)
     {
      string testSymbol = reverse + suffixes[i];
      if(SymbolInfoDouble(testSymbol, SYMBOL_BID) > 0)
         return testSymbol;
     }

   return "";
  }

//+------------------------------------------------------------------+
bool CSmcCurrencyStrength::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                                const bool enableDraw, const ENUM_CS_METHOD method,
                                const int period)
  {
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   m_prefix = "SMC_CS_";
   m_method = method;
   m_period = MathMax(1, period);
   m_calcTF = timeframe;

   InitPairs();
   return true;
  }

//+------------------------------------------------------------------+
bool CSmcCurrencyStrength::Update()
  {
   if(!m_initialized)
      return false;

//--- 前回値を保存
   for(int i = 0; i < CS_CURRENCY_COUNT; i++)
      m_prevStrength[i] = m_info[i].strength;

//--- 強弱値リセット
   for(int i = 0; i < CS_CURRENCY_COUNT; i++)
      m_info[i].strength = 0;

//--- 計算
   switch(m_method)
     {
      case CS_METHOD_RATE_CHANGE:
         CalcByRateChange();
         break;
      case CS_METHOD_RSI:
         CalcByRSI();
         break;
      default:
         CalcByRateChange();
         break;
     }

   NormalizeStrengths();
   CalcMomentum();
   CalcRanks();

   return true;
  }

void CSmcCurrencyStrength::Clean()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   CSmcDrawing::Redraw();
  }

//+------------------------------------------------------------------+
//| 価格変化率ベースの計算                                             |
//+------------------------------------------------------------------+
void CSmcCurrencyStrength::CalcByRateChange()
  {
   for(int p = 0; p < CS_PAIR_COUNT; p++)
     {
      if(!m_pairAvailable[p])
         continue;

      double close0 = iClose(m_pairSymbol[p], m_calcTF, 0);
      double closeN = iClose(m_pairSymbol[p], m_calcTF, m_period);

      if(close0 == 0 || closeN == 0)
         continue;

      double change = ((close0 - closeN) / closeN) * 100.0;

      //--- ベース通貨に加算、クォート通貨から減算
      //--- ペアが逆の場合（ブローカーシンボル名で判定）
      string actualBase = StringSubstr(m_pairSymbol[p], 0, 3);
      if(actualBase == m_currencies[m_pairBase[p]])
        {
         m_info[m_pairBase[p]].strength  += change;
         m_info[m_pairQuote[p]].strength -= change;
        }
      else
        {
         m_info[m_pairBase[p]].strength  -= change;
         m_info[m_pairQuote[p]].strength += change;
        }
     }
  }

//+------------------------------------------------------------------+
//| RSIベースの計算                                                    |
//+------------------------------------------------------------------+
void CSmcCurrencyStrength::CalcByRSI()
  {
   for(int p = 0; p < CS_PAIR_COUNT; p++)
     {
      if(!m_pairAvailable[p])
         continue;

      int handle = iRSI(m_pairSymbol[p], m_calcTF, m_period, PRICE_CLOSE);
      if(handle == INVALID_HANDLE)
         continue;

      double rsi[];
      ArraySetAsSeries(rsi, true);
      if(CopyBuffer(handle, 0, 0, 1, rsi) > 0)
        {
         double rsiVal = rsi[0] - 50.0;  // 中心を0に
         m_info[m_pairBase[p]].strength  += rsiVal;
         m_info[m_pairQuote[p]].strength -= rsiVal;
        }
      IndicatorRelease(handle);
     }
  }

//+------------------------------------------------------------------+
void CSmcCurrencyStrength::NormalizeStrengths()
  {
   double maxAbs = 0;
   for(int i = 0; i < CS_CURRENCY_COUNT; i++)
      maxAbs = MathMax(maxAbs, MathAbs(m_info[i].strength));

   if(maxAbs > 0)
     {
      for(int i = 0; i < CS_CURRENCY_COUNT; i++)
         m_info[i].strength = (m_info[i].strength / maxAbs) * 100.0;
     }
  }

void CSmcCurrencyStrength::CalcMomentum()
  {
   for(int i = 0; i < CS_CURRENCY_COUNT; i++)
      m_info[i].momentum = m_info[i].strength - m_prevStrength[i];
  }

void CSmcCurrencyStrength::CalcRanks()
  {
//--- ランク計算 (強弱値降順)
   int indices[];
   ArrayResize(indices, CS_CURRENCY_COUNT);
   for(int i = 0; i < CS_CURRENCY_COUNT; i++)
      indices[i] = i;

//--- バブルソート
   for(int i = 0; i < CS_CURRENCY_COUNT - 1; i++)
      for(int j = i + 1; j < CS_CURRENCY_COUNT; j++)
         if(m_info[indices[j]].strength > m_info[indices[i]].strength)
           {
            int tmp = indices[i]; indices[i] = indices[j]; indices[j] = tmp;
           }

   for(int i = 0; i < CS_CURRENCY_COUNT; i++)
      m_info[indices[i]].rank = i + 1;
  }

//+------------------------------------------------------------------+
int CSmcCurrencyStrength::FindCurrencyIndex(const string currency) const
  {
   for(int i = 0; i < CS_CURRENCY_COUNT; i++)
      if(m_currencies[i] == currency)
         return i;
   return -1;
  }

double CSmcCurrencyStrength::GetStrength(const string currency) const
  {
   int idx = FindCurrencyIndex(currency);
   return (idx >= 0) ? m_info[idx].strength : 0;
  }

double CSmcCurrencyStrength::GetMomentum(const string currency) const
  {
   int idx = FindCurrencyIndex(currency);
   return (idx >= 0) ? m_info[idx].momentum : 0;
  }

int CSmcCurrencyStrength::GetRank(const string currency) const
  {
   int idx = FindCurrencyIndex(currency);
   return (idx >= 0) ? m_info[idx].rank : 0;
  }

bool CSmcCurrencyStrength::GetCurrencyInfo(const string currency, SmcCurrencyInfo &info) const
  {
   int idx = FindCurrencyIndex(currency);
   if(idx < 0) return false;
   info = m_info[idx];
   return true;
  }

string CSmcCurrencyStrength::GetStrongest() const
  {
   for(int i = 0; i < CS_CURRENCY_COUNT; i++)
      if(m_info[i].rank == 1) return m_info[i].name;
   return "";
  }

string CSmcCurrencyStrength::GetWeakest() const
  {
   for(int i = 0; i < CS_CURRENCY_COUNT; i++)
      if(m_info[i].rank == CS_CURRENCY_COUNT) return m_info[i].name;
   return "";
  }

string CSmcCurrencyStrength::GetBestPair() const
  {
   return GetStrongest() + GetWeakest();
  }

void CSmcCurrencyStrength::GetSortedCurrencies(string &sorted[]) const
  {
   ArrayResize(sorted, CS_CURRENCY_COUNT);
   for(int rank = 1; rank <= CS_CURRENCY_COUNT; rank++)
      for(int i = 0; i < CS_CURRENCY_COUNT; i++)
         if(m_info[i].rank == rank)
            sorted[rank - 1] = m_info[i].name;
  }

bool CSmcCurrencyStrength::IsStrongVsWeak(const string base, const string quote) const
  {
   return (GetStrength(base) > 0 && GetStrength(quote) < 0);
  }

#endif // __SMC_CURRENCY_STRENGTH_MQH__
//+------------------------------------------------------------------+
