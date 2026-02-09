//+------------------------------------------------------------------+
//|                                                    SmcTypes.mqh  |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//|                         https://github.com/your-repo/SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property link      "https://github.com/your-repo/SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_TYPES_MQH__
#define __SMC_TYPES_MQH__

//+------------------------------------------------------------------+
//| Library version                                                   |
//+------------------------------------------------------------------+
#define SMC_LIB_VERSION     "1.0.0"
#define SMC_LIB_NAME        "SMC/ICT OSS Library"

//+------------------------------------------------------------------+
//| Enumerations - Trend                                              |
//+------------------------------------------------------------------+
enum ENUM_SMC_TREND
  {
   SMC_TREND_BULLISH  = 1,    // 上昇トレンド (Higher Highs & Higher Lows)
   SMC_TREND_BEARISH  = -1,   // 下降トレンド (Lower Highs & Lower Lows)
   SMC_TREND_RANGING  = 0     // レンジ相場
  };

//+------------------------------------------------------------------+
//| Enumerations - Zone State                                         |
//+------------------------------------------------------------------+
enum ENUM_ZONE_STATE
  {
   ZONE_FRESH      = 0,       // 未タッチ (新鮮)
   ZONE_TESTED     = 1,       // テスト済み (一度タッチ)
   ZONE_MITIGATED  = 2,       // ミティゲート済み (部分的に消費)
   ZONE_BROKEN     = 3        // ブレイク済み (無効化)
  };

//+------------------------------------------------------------------+
//| Enumerations - Structure Break Type                               |
//+------------------------------------------------------------------+
enum ENUM_STRUCTURE_TYPE
  {
   STRUCT_NONE   = 0,         // 構造ブレイクなし
   STRUCT_BOS    = 1,         // Break of Structure (トレンド継続)
   STRUCT_CHOCH  = 2          // Change of Character (トレンド転換)
  };

//+------------------------------------------------------------------+
//| Enumerations - Session / Kill Zone                                |
//+------------------------------------------------------------------+
enum ENUM_SMC_SESSION
  {
   SESSION_NONE       = 0,    // セッション外
   SESSION_ASIAN      = 1,    // アジアセッション
   SESSION_LONDON     = 2,    // ロンドンセッション
   SESSION_NEWYORK    = 3,    // ニューヨークセッション
   SESSION_LDN_NY_OL  = 4     // ロンドン-NY オーバーラップ
  };

//+------------------------------------------------------------------+
//| Enumerations - Zone Probability                                   |
//+------------------------------------------------------------------+
enum ENUM_ZONE_PROBABILITY
  {
   PROB_HIGH    = 2,          // 高確率
   PROB_MEDIUM  = 1,          // 中確率
   PROB_LOW     = 0           // 低確率
  };

//+------------------------------------------------------------------+
//| Enumerations - FVG Probability                                    |
//+------------------------------------------------------------------+
enum ENUM_FVG_PROBABILITY
  {
   FVG_HIGH_PROB   = 2,       // 高確率 FVG (トレンド方向一致)
   FVG_LOW_PROB    = 1,       // 低確率 FVG
   FVG_BREAKAWAY   = 0        // ブレイクアウェイ FVG
  };

//+------------------------------------------------------------------+
//| Enumerations - Liquidity Level Type                               |
//+------------------------------------------------------------------+
enum ENUM_LIQUIDITY_TYPE
  {
   LIQ_EQUAL_HIGHS  = 0,     // Equal Highs (売り流動性)
   LIQ_EQUAL_LOWS   = 1,     // Equal Lows (買い流動性)
   LIQ_POOL_HIGH    = 2,     // 流動性プール (高値側)
   LIQ_POOL_LOW     = 3,     // 流動性プール (安値側)
   LIQ_SWEEP_HIGH   = 4,     // 流動性スイープ (高値側)
   LIQ_SWEEP_LOW    = 5      // 流動性スイープ (安値側)
  };

//+------------------------------------------------------------------+
//| Enumerations - VIX Level                                          |
//+------------------------------------------------------------------+
enum ENUM_VIX_LEVEL
  {
   VIX_LOW      = 0,          // 低ボラティリティ (0-15)
   VIX_NORMAL   = 1,          // 通常 (15-25)
   VIX_HIGH     = 2,          // 高ボラティリティ (25-35)
   VIX_EXTREME  = 3           // 極端 (35+)
  };

//+------------------------------------------------------------------+
//| Enumerations - Currency Strength Method                           |
//+------------------------------------------------------------------+
enum ENUM_CS_METHOD
  {
   CS_METHOD_RATE_CHANGE  = 0,  // 価格変化率ベース
   CS_METHOD_RSI          = 1,  // RSIベース
   CS_METHOD_STOCHASTIC   = 2   // ストキャスティクスベース
  };

//+------------------------------------------------------------------+
//| Enumerations - Log Level                                          |
//+------------------------------------------------------------------+
enum ENUM_LOG_LEVEL
  {
   LOG_DEBUG  = 0,            // デバッグ
   LOG_INFO   = 1,            // 情報
   LOG_WARN   = 2,            // 警告
   LOG_ERROR  = 3             // エラー
  };

//+------------------------------------------------------------------+
//| Enumerations - Entry Signal                                       |
//+------------------------------------------------------------------+
enum ENUM_ENTRY_SIGNAL
  {
   SIGNAL_BUY   = 1,          // 買いシグナル
   SIGNAL_SELL  = -1,         // 売りシグナル
   SIGNAL_WAIT  = 0           // 待機
  };

//+------------------------------------------------------------------+
//| Structure - Swing Point                                           |
//+------------------------------------------------------------------+
struct SmcSwingPoint
  {
   double            price;          // スイング価格
   datetime          time;           // 発生時刻
   int               barIndex;       // バーインデックス
   bool              isHigh;         // true=スイングハイ, false=スイングロー
   int               strength;       // 強度 (左右何本で確認)
   bool              isBroken;       // ブレイクされたか
   bool              isValid;        // 有効フラグ

   void              Init()
     {
      price    = 0;
      time     = 0;
      barIndex = 0;
      isHigh   = false;
      strength = 0;
      isBroken = false;
      isValid  = false;
     }

   double            GetPrice()    const { return price; }
   bool              IsPushLow()   const { return !isHigh && !isBroken; }
   bool              IsPullHigh()  const { return isHigh && !isBroken; }
  };

//+------------------------------------------------------------------+
//| Structure - Zone (OB / FVG / Breaker 共通)                        |
//+------------------------------------------------------------------+
struct SmcZone
  {
   double            topPrice;       // ゾーン上端
   double            bottomPrice;    // ゾーン下端
   datetime          formationTime;  // 形成時刻
   int               formationBar;   // 形成バーインデックス
   ENUM_ZONE_STATE   state;          // ゾーン状態
   ENUM_ZONE_PROBABILITY probability; // 確率分類
   bool              isBullish;      // true=強気ゾーン
   int               age;            // 経過バー数
   double            score;          // スコア (0.0-1.0)
   int               candleCount;    // 構成ローソク足数
   bool              isValid;        // 有効フラグ

   void              Init()
     {
      topPrice      = 0;
      bottomPrice   = 0;
      formationTime = 0;
      formationBar  = 0;
      state         = ZONE_FRESH;
      probability   = PROB_MEDIUM;
      isBullish     = false;
      age           = 0;
      score         = 0;
      candleCount   = 1;
      isValid       = false;
     }

   double            GetCenter()    const { return (topPrice + bottomPrice) / 2.0; }
   double            GetSize()      const { return topPrice - bottomPrice; }
   bool              IsFresh()      const { return state == ZONE_FRESH; }
   bool              IsActive()     const { return state != ZONE_BROKEN && isValid; }
  };

//+------------------------------------------------------------------+
//| Structure - Structure Break (BOS / CHoCH)                         |
//+------------------------------------------------------------------+
struct SmcStructureBreak
  {
   ENUM_STRUCTURE_TYPE type;         // BOS or CHoCH
   double            breakPrice;     // ブレイク価格
   double            swingPrice;     // ブレイクされたスイングの価格
   datetime          time;           // 発生時刻
   int               barIndex;       // バーインデックス
   bool              isBullish;      // true=上方ブレイク
   bool              isValid;        // 有効フラグ

   void              Init()
     {
      type       = STRUCT_NONE;
      breakPrice = 0;
      swingPrice = 0;
      time       = 0;
      barIndex   = 0;
      isBullish  = false;
      isValid    = false;
     }

   bool              IsBOS()   const { return type == STRUCT_BOS; }
   bool              IsCHoCH() const { return type == STRUCT_CHOCH; }
  };

//+------------------------------------------------------------------+
//| Structure - Liquidity Level                                       |
//+------------------------------------------------------------------+
struct SmcLiquidityLevel
  {
   double            price;          // 流動性レベル価格
   datetime          firstTime;      // 最初のタッチ時刻
   datetime          lastTime;       // 最後のタッチ時刻
   int               touchCount;     // タッチ回数
   bool              isSweep;        // スイープされたか
   datetime          sweepTime;      // スイープ時刻
   ENUM_LIQUIDITY_TYPE type;         // 流動性タイプ
   bool              isValid;        // 有効フラグ

   void              Init()
     {
      price      = 0;
      firstTime  = 0;
      lastTime   = 0;
      touchCount = 0;
      isSweep    = false;
      sweepTime  = 0;
      type       = LIQ_EQUAL_HIGHS;
      isValid    = false;
     }

   bool              IsEqualHL()  const { return type == LIQ_EQUAL_HIGHS || type == LIQ_EQUAL_LOWS; }
   bool              IsPool()     const { return type == LIQ_POOL_HIGH || type == LIQ_POOL_LOW; }
   bool              IsHighSide() const { return type == LIQ_EQUAL_HIGHS || type == LIQ_POOL_HIGH || type == LIQ_SWEEP_HIGH; }
  };

//+------------------------------------------------------------------+
//| Structure - Confluence Entry Zone                                  |
//+------------------------------------------------------------------+
struct SmcConfluenceZone
  {
   double            topPrice;       // ゾーン上端
   double            bottomPrice;    // ゾーン下端
   double            centerPrice;    // ゾーン中心
   bool              isBullish;      // 方向
   double            totalScore;     // 合計スコア (0.0-1.0)
   int               factorCount;    // コンフルエンス要素数
   string            factors[];      // 要素説明配列
   double            factorScores[]; // 各要素スコア
   bool              isValid;        // 有効フラグ

   void              Init()
     {
      topPrice    = 0;
      bottomPrice = 0;
      centerPrice = 0;
      isBullish   = false;
      totalScore  = 0;
      factorCount = 0;
      ArrayResize(factors, 0);
      ArrayResize(factorScores, 0);
      isValid     = false;
     }

   double            GetSize()   const { return topPrice - bottomPrice; }
   bool              IsStrong()  const { return factorCount >= 3 && totalScore >= 0.6; }
  };

//+------------------------------------------------------------------+
//| Structure - Range Info                                             |
//+------------------------------------------------------------------+
struct SmcRangeInfo
  {
   double            highPrice;      // レンジ高値
   double            lowPrice;       // レンジ安値
   datetime          startTime;      // 開始時刻
   datetime          breakTime;      // ブレイク時刻
   int               startBar;       // 開始バー
   int               duration;       // 継続バー数
   bool              isBroken;       // ブレイクされたか
   bool              isBullishBreak; // 上方ブレイクか
   bool              isValid;        // 有効フラグ

   void              Init()
     {
      highPrice      = 0;
      lowPrice       = 0;
      startTime      = 0;
      breakTime      = 0;
      startBar       = 0;
      duration       = 0;
      isBroken       = false;
      isBullishBreak = false;
      isValid        = false;
     }

   double            GetSize()   const { return highPrice - lowPrice; }
   double            GetCenter() const { return (highPrice + lowPrice) / 2.0; }
  };

//+------------------------------------------------------------------+
//| Structure - Currency Strength Entry                                |
//+------------------------------------------------------------------+
struct SmcCurrencyInfo
  {
   string            name;           // 通貨名 (e.g. "USD")
   double            strength;       // 強弱値 (-100 ~ +100)
   double            momentum;       // モメンタム (変化速度)
   int               rank;           // ランク (1=最強, 8=最弱)

   void              Init()
     {
      name     = "";
      strength = 0;
      momentum = 0;
      rank     = 0;
     }
  };

//+------------------------------------------------------------------+
//| Structure - OTE (Optimal Trade Entry) Zone                         |
//+------------------------------------------------------------------+
struct SmcOTEZone
  {
   double            fibLevel618;    // 0.618 レベル価格
   double            fibLevel705;    // 0.705 レベル (OTEスイートスポット)
   double            fibLevel786;    // 0.786 レベル価格
   double            fibLevel50;     // 0.5 レベル (Equilibrium)
   double            swingHigh;      // スイングハイ
   double            swingLow;       // スイングロー
   bool              isBullish;      // true=上昇リトレース (買いOTE)
   bool              isValid;        // 有効フラグ

   void              Init()
     {
      fibLevel618 = 0;
      fibLevel705 = 0;
      fibLevel786 = 0;
      fibLevel50  = 0;
      swingHigh   = 0;
      swingLow    = 0;
      isBullish   = false;
      isValid     = false;
     }

   double            GetOTETop()    const { return isBullish ? fibLevel618 : fibLevel786; }
   double            GetOTEBottom() const { return isBullish ? fibLevel786 : fibLevel618; }
   double            GetOTECenter() const { return fibLevel705; }
  };

//+------------------------------------------------------------------+
//| Structure - Kill Zone Session                                      |
//+------------------------------------------------------------------+
struct SmcSessionInfo
  {
   ENUM_SMC_SESSION  session;        // セッション種別
   int               startHourGMT;   // 開始時 (GMT)
   int               startMinGMT;    // 開始分 (GMT)
   int               endHourGMT;     // 終了時 (GMT)
   int               endMinGMT;      // 終了分 (GMT)
   double            sessionHigh;    // セッション中高値
   double            sessionLow;     // セッション中安値
   double            sessionOpen;    // セッション始値
   bool              isActive;       // 現在アクティブか

   void              Init()
     {
      session      = SESSION_NONE;
      startHourGMT = 0;
      startMinGMT  = 0;
      endHourGMT   = 0;
      endMinGMT    = 0;
      sessionHigh  = 0;
      sessionLow   = 0;
      sessionOpen  = 0;
      isActive     = false;
     }

   double            GetRange() const { return sessionHigh - sessionLow; }
  };

#endif // __SMC_TYPES_MQH__
//+------------------------------------------------------------------+
