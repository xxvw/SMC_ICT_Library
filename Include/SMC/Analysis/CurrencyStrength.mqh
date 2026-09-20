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
   bool              m_hasResult;
   datetime          m_resultTime;

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
   void              SetMethod(const ENUM_CS_METHOD method)
     { if(m_method != method) { m_method = method; ClearResults(); } }
   void              SetPeriod(const int period)
     { if(m_period != MathMax(1, period)) { m_period = MathMax(1, period); ClearResults(); } }

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
   void              ClearResults();
   string            FindBrokerSymbol(const string pair) const;
   bool              ReadPairRates(const int pair, const datetime anchor, MqlRates &rates[]) const;
   void              AddContribution(const int pair, const double value, int &coverage[]);
   void              CalcByRateChange(const datetime anchor, int &coverage[]);
   void              CalcByRSI(const datetime anchor, int &coverage[]);
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
   , m_hasResult(false)
   , m_resultTime(0)
  {
   InitCurrencies();
   ArrayInitialize(m_prevStrength, 0);
  }

CSmcCurrencyStrength::~CSmcCurrencyStrength() {}

// No valid ranking is published until every currency has at least one
// usable closed pair contribution. Missing broker pairs are permitted;
// a currency without coverage invalidates the whole relative ranking.
void CSmcCurrencyStrength::ClearResults()
  {
   m_hasResult = false;
   m_resultTime = 0;
   ArrayInitialize(m_prevStrength, 0);
   for(int i = 0; i < CS_CURRENCY_COUNT; i++)
     {
      m_info[i].Init();
      m_info[i].name = m_currencies[i];
     }
  }

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
// Prefer the host FX symbol's suffix, including custom/offline symbols.
// Existence and selection are separate from data readiness: a zero BID
// must not prevent an otherwise usable historical symbol from being read.
   string suffixes[] = {"", "m", ".ecn", ".pro", ".raw", ".", "_", ".i", "pro", ".std"};
   string reverse = StringSubstr(pair, 3, 3) + StringSubstr(pair, 0, 3);
   bool custom = false;
   if(StringLen(m_symbol) >= 6 &&
      FindCurrencyIndex(StringSubstr(m_symbol, 0, 3)) >= 0 &&
      FindCurrencyIndex(StringSubstr(m_symbol, 3, 3)) >= 0)
     {
      bool customHost = false;
      SymbolExist(m_symbol, customHost);
      string suffix = StringSubstr(m_symbol, 6);
      string preferred = pair + suffix;
      if(SymbolExist(preferred, custom) && SymbolSelect(preferred, true))
         return preferred;
      preferred = reverse + suffix;
      if(SymbolExist(preferred, custom) && SymbolSelect(preferred, true))
         return preferred;
      // A custom feed is an isolated universe; do not silently mix it with
      // unrelated live broker pairs when one custom cross is unavailable.
      if(customHost)
         return "";
     }

// Try the conventional direct and reversed broker names if needed.
   for(int i = 0; i < ArraySize(suffixes); i++)
     {
      string testSymbol = pair + suffixes[i];
      if(SymbolExist(testSymbol, custom) && SymbolSelect(testSymbol, true))
         return testSymbol;
     }
   for(int i = 0; i < ArraySize(suffixes); i++)
     {
      string testSymbol = reverse + suffixes[i];
      if(SymbolExist(testSymbol, custom) && SymbolSelect(testSymbol, true))
         return testSymbol;
     }

   return "";
  }

//+------------------------------------------------------------------+
bool CSmcCurrencyStrength::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                                const bool enableDraw, const ENUM_CS_METHOD method,
                                const int period)
  {
   ClearResults();
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   SetModulePrefix("CS");
   m_method = method;
   m_period = MathMax(1, period);
   m_calcTF = m_timeframe;

   InitPairs();
   return true;
  }

//+------------------------------------------------------------------+
bool CSmcCurrencyStrength::Update()
  {
   if(!m_initialized || m_period >= 2147483647 || !PrepareRates(2))
     {
      ClearResults();
      return false;
     }

   datetime anchor = Time(1);
   if(anchor <= 0 || Time(0) <= anchor)
     {
      ClearResults();
      return false;
     }

   // Repeated updates of one closed bar keep the same momentum baseline.
   // The first usable observation (including recovery) has zero momentum.
   bool firstResult = !m_hasResult || anchor < m_resultTime;
   if(!firstResult && anchor > m_resultTime)
      for(int i = 0; i < CS_CURRENCY_COUNT; i++)
         m_prevStrength[i] = m_info[i].strength;

//--- 強弱値リセット
   for(int i = 0; i < CS_CURRENCY_COUNT; i++)
      m_info[i].strength = 0;

   int coverage[CS_CURRENCY_COUNT];
   ArrayInitialize(coverage, 0);
   // Rediscover symbols so symbols added after Init can become ready.
   InitPairs();
   switch(m_method)
     {
      case CS_METHOD_RATE_CHANGE:
         CalcByRateChange(anchor, coverage);
         break;
      case CS_METHOD_RSI:
         CalcByRSI(anchor, coverage);
         break;
      default:
         CalcByRateChange(anchor, coverage);
         break;
     }

   for(int i = 0; i < CS_CURRENCY_COUNT; i++)
      if(coverage[i] == 0 || !MathIsValidNumber(m_info[i].strength))
        {
         ClearResults();
         return false;
        }

   NormalizeStrengths();
   if(firstResult)
      for(int i = 0; i < CS_CURRENCY_COUNT; i++)
         m_prevStrength[i] = m_info[i].strength;
   CalcMomentum();
   CalcRanks();
   m_hasResult = true;
   m_resultTime = anchor;
   return true;
  }

void CSmcCurrencyStrength::Clean()
  {
   CSmcBase::Clean();
  }

//+------------------------------------------------------------------+
//| 価格変化率ベースの計算                                             |
//+------------------------------------------------------------------+
bool CSmcCurrencyStrength::ReadPairRates(const int pair, const datetime anchor,
                                        MqlRates &rates[]) const
  {
   ArrayFree(rates);
   ArraySetAsSeries(rates, false);
   if(!m_pairAvailable[pair])
      return false;

   // CopyRates starts history loading if needed. Exact anchoring prevents
   // a missing pair candle from substituting an older bar.
   int requested = m_period + 1;
   if(CopyRates(m_pairSymbol[pair], m_calcTF, anchor, requested, rates) != requested ||
      ArraySize(rates) != requested || rates[requested - 1].time != anchor)
      return false;
   // Shift >= 1 excludes that symbol's own unfinished candle.
   if(iBarShift(m_pairSymbol[pair], m_calcTF, anchor, true) < 1)
      return false;
   for(int i = 0; i < requested; i++)
     {
      if(rates[i].time <= 0 || (i > 0 && rates[i].time <= rates[i - 1].time) ||
         !MathIsValidNumber(rates[i].open) || !MathIsValidNumber(rates[i].high) ||
         !MathIsValidNumber(rates[i].low) || !MathIsValidNumber(rates[i].close) ||
         rates[i].open <= 0 || rates[i].high <= 0 || rates[i].low <= 0 || rates[i].close <= 0 ||
         rates[i].high < MathMax(rates[i].open, rates[i].close) ||
         rates[i].low > MathMin(rates[i].open, rates[i].close))
         return false;
     }
   return true;
  }

void CSmcCurrencyStrength::AddContribution(const int pair, const double value, int &coverage[])
  {
   if(!MathIsValidNumber(value))
      return;
   double oriented = value;
   if(StringSubstr(m_pairSymbol[pair], 0, 3) != m_currencies[m_pairBase[pair]])
      oriented = -value;
   m_info[m_pairBase[pair]].strength += oriented;
   m_info[m_pairQuote[pair]].strength -= oriented;
   coverage[m_pairBase[pair]]++;
   coverage[m_pairQuote[pair]]++;
  }

void CSmcCurrencyStrength::CalcByRateChange(const datetime anchor, int &coverage[])
  {
   for(int p = 0; p < CS_PAIR_COUNT; p++)
     {
      MqlRates rates[];
      if(!ReadPairRates(p, anchor, rates))
         continue;
      double change = ((rates[m_period].close - rates[0].close) / rates[0].close) * 100.0;
      AddContribution(p, change, coverage);
     }
  }

//+------------------------------------------------------------------+
//| RSIベースの計算                                                    |
//+------------------------------------------------------------------+
void CSmcCurrencyStrength::CalcByRSI(const datetime anchor, int &coverage[])
  {
   for(int p = 0; p < CS_PAIR_COUNT; p++)
     {
      MqlRates rates[];
      if(!ReadPairRates(p, anchor, rates))
         continue;

      int handle = iRSI(m_pairSymbol[p], m_calcTF, m_period, PRICE_CLOSE);
      if(handle == INVALID_HANDLE)
         continue;

      double rsi[];
      int copied = CopyBuffer(handle, 0, anchor, 1, rsi);
      IndicatorRelease(handle);
      if(copied != 1 || ArraySize(rsi) != 1 ||
         !MathIsValidNumber(rsi[0]) || rsi[0] == EMPTY_VALUE || rsi[0] < 0 || rsi[0] > 100)
         continue;
      AddContribution(p, rsi[0] - 50.0, coverage);
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
   info.Init();
   int idx = FindCurrencyIndex(currency);
   if(idx < 0 || !m_hasResult) return false;
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
   // Never free a caller's fixed-size string array. Clear stale names in
   // place; only dynamic arrays can represent an unavailable empty result.
   for(int i = 0; i < ArraySize(sorted); i++)
      sorted[i] = "";
   bool dynamic = ArrayIsDynamic(sorted);
   if(dynamic)
      ArrayResize(sorted, 0);
   if(!m_hasResult)
      return;
   if(dynamic && ArrayResize(sorted, CS_CURRENCY_COUNT) != CS_CURRENCY_COUNT)
      return;
   if(ArraySize(sorted) < CS_CURRENCY_COUNT)
      return;
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
