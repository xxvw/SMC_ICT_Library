//+------------------------------------------------------------------+
//|                                                   MathUtils.mqh  |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_MATH_UTILS_MQH__
#define __SMC_MATH_UTILS_MQH__

#include "../Core/SmcTypes.mqh"

//+------------------------------------------------------------------+
//| CSmcMathUtils - Mathematical utility functions                    |
//|                                                                    |
//| Static utility methods for:                                      |
//|   - Statistical calculations                                      |
//|   - Regression analysis                                            |
//|   - Normalization functions                                        |
//|   - Activation functions                                           |
//+------------------------------------------------------------------+
class CSmcMathUtils
  {
public:
   //--- Statistical Methods / 統計メソッド
   
   //+------------------------------------------------------------------+
   //| Calculate standard deviation                                     |
   //| 標準偏差を計算                                                   |
   //+------------------------------------------------------------------+
   static double StandardDeviation(double &arr[], const int count)
     {
      if(count <= 1 || count > ArraySize(arr))
         return 0.0;
      
      // Calculate mean
      // 平均を計算
      double sum = 0.0;
      for(int i = 0; i < count; i++)
         sum += arr[i];
      double mean = sum / count;
      
      // Calculate variance
      // 分散を計算
      double variance = 0.0;
      for(int i = 0; i < count; i++)
        {
         double diff = arr[i] - mean;
         variance += diff * diff;
        }
      variance /= (count - 1);
      
      // Return standard deviation
      // 標準偏差を返す
      return MathSqrt(variance);
     }
   
   //+------------------------------------------------------------------+
   //| Calculate Z-score (standard score)                               |
   //| Zスコア（標準スコア）を計算                                     |
   //+------------------------------------------------------------------+
   static double ZScore(const double value, double &arr[], const int count)
     {
      if(count <= 1 || count > ArraySize(arr))
         return 0.0;
      
      double mean = 0.0;
      for(int i = 0; i < count; i++)
         mean += arr[i];
      mean /= count;
      
      double stdDev = StandardDeviation(arr, count);
      if(stdDev == 0.0)
         return 0.0;
      
      return (value - mean) / stdDev;
     }
   
   //+------------------------------------------------------------------+
   //| Calculate correlation coefficient between two arrays             |
   //| 2つの配列間の相関係数を計算                                     |
   //+------------------------------------------------------------------+
   static double Correlation(double &x[], double &y[], const int count)
     {
      if(count <= 1 || count > ArraySize(x) || count > ArraySize(y))
         return 0.0;
      
      // Calculate means
      // 平均を計算
      double meanX = 0.0, meanY = 0.0;
      for(int i = 0; i < count; i++)
        {
         meanX += x[i];
         meanY += y[i];
        }
      meanX /= count;
      meanY /= count;
      
      // Calculate covariance and variances
      // 共分散と分散を計算
      double covXY = 0.0, varX = 0.0, varY = 0.0;
      for(int i = 0; i < count; i++)
        {
         double diffX = x[i] - meanX;
         double diffY = y[i] - meanY;
         covXY += diffX * diffY;
         varX += diffX * diffX;
         varY += diffY * diffY;
        }
      
      double denominator = MathSqrt(varX * varY);
      if(denominator == 0.0)
         return 0.0;
      
      return covXY / denominator;
     }
   
   //--- Regression Methods / 回帰メソッド
   
   //+------------------------------------------------------------------+
   //| Calculate linear regression (slope and intercept)               |
   //| 線形回帰を計算（傾きと切片）                                     |
   //+------------------------------------------------------------------+
   static bool LinearRegression(double &arr[], const int count, double &slope, double &intercept)
     {
      if(count <= 1 || count > ArraySize(arr))
        {
         slope = 0.0;
         intercept = 0.0;
         return false;
        }
      
      // Calculate sums for linear regression
      // 線形回帰用の合計を計算
      double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0;
      
      for(int i = 0; i < count; i++)
        {
         double x = (double)i;
         double y = arr[i];
         sumX += x;
         sumY += y;
         sumXY += x * y;
         sumX2 += x * x;
        }
      
      // Calculate slope and intercept
      // 傾きと切片を計算
      double denominator = count * sumX2 - sumX * sumX;
      if(denominator == 0.0)
        {
         slope = 0.0;
         intercept = 0.0;
         return false;
        }
      
      slope = (count * sumXY - sumX * sumY) / denominator;
      intercept = (sumY - slope * sumX) / count;
      
      return true;
     }
   
   //--- Percentile Methods / パーセンタイルメソッド
   
   //+------------------------------------------------------------------+
   //| Calculate percentile value from sorted array                    |
   //| ソート済み配列からパーセンタイル値を計算                         |
   //+------------------------------------------------------------------+
   static double Percentile(double &arr[], const int count, const double pct)
     {
      if(count <= 0 || count > ArraySize(arr) || pct < 0.0 || pct > 1.0)
         return 0.0;
      
      // Create a copy and sort it
      // コピーを作成してソート
      double sorted[];
      ArrayResize(sorted, count);
      ArrayCopy(sorted, arr, 0, 0, count);
      ArraySort(sorted);
      
      // Calculate index
      // インデックスを計算
      double index = pct * (count - 1);
      int lowerIndex = (int)MathFloor(index);
      int upperIndex = (int)MathCeil(index);
      
      if(lowerIndex == upperIndex)
         return sorted[lowerIndex];
      
      // Linear interpolation
      // 線形補間
      double weight = index - lowerIndex;
      return sorted[lowerIndex] * (1.0 - weight) + sorted[upperIndex] * weight;
     }
   
   //--- EMA Methods / EMAメソッド
   
   //+------------------------------------------------------------------+
   //| Calculate Exponential Moving Average                            |
   //| 指数移動平均を計算                                               |
   //+------------------------------------------------------------------+
   static double EMA(const double value, const double prev, const int period)
     {
      if(period <= 0)
         return value;
      
      double multiplier = 2.0 / (period + 1.0);
      return (value - prev) * multiplier + prev;
     }
   
   //--- Normalization Methods / 正規化メソッド
   
   //+------------------------------------------------------------------+
   //| Normalize value to range [0, 1] using min and max               |
   //| 最小値と最大値を使用して値を範囲[0, 1]に正規化                   |
   //+------------------------------------------------------------------+
   static double NormalizeMinMax(const double value, const double min, const double max)
     {
      if(max == min)
         return 0.5; // Return middle value if range is zero
                     // 範囲がゼロの場合は中間値を返す
      
      double normalized = (value - min) / (max - min);
      
      // Clamp to [0, 1]
      // [0, 1]にクランプ
      if(normalized < 0.0)
         normalized = 0.0;
      if(normalized > 1.0)
         normalized = 1.0;
      
      return normalized;
     }
   
   //--- Activation Functions / 活性化関数
   
   //+------------------------------------------------------------------+
   //| Sigmoid activation function                                      |
   //| シグモイド活性化関数                                             |
   //+------------------------------------------------------------------+
   static double Sigmoid(const double x)
     {
      return 1.0 / (1.0 + MathExp(-x));
     }
   
   //+------------------------------------------------------------------+
   //| ReLU (Rectified Linear Unit) activation function                |
   //| ReLU（正規化線形ユニット）活性化関数                             |
   //+------------------------------------------------------------------+
   static double ReLU(const double x)
     {
      return (x > 0.0) ? x : 0.0;
     }
  };

#endif // __SMC_MATH_UTILS_MQH__
//+------------------------------------------------------------------+
