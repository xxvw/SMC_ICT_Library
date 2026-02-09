//+------------------------------------------------------------------+
//|                                                  ArrayUtils.mqh  |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_ARRAY_UTILS_MQH__
#define __SMC_ARRAY_UTILS_MQH__

#include "../Core/SmcTypes.mqh"

//+------------------------------------------------------------------+
//| Template Array Utility Functions                                  |
//|                                                                    |
//| Generic array manipulation functions using templates              |
//| Note: MQL5 has limited template support, so we use function     |
//| templates for common operations                                   |
//+------------------------------------------------------------------+

//--- Generic Template Functions / 汎用テンプレート関数

//+------------------------------------------------------------------+
//| Append value to end of array                                     |
//| 配列の末尾に値を追加                                              |
//+------------------------------------------------------------------+
template<typename T>
void SmcArrayPush(T &arr[], const T value)
  {
   int size = ArraySize(arr);
   ArrayResize(arr, size + 1);
   arr[size] = value;
  }

//+------------------------------------------------------------------+
//| Remove and return last element from array                        |
//| 配列の最後の要素を削除して返す                                    |
//+------------------------------------------------------------------+
template<typename T>
bool SmcArrayPop(T &arr[], T &value)
  {
   int size = ArraySize(arr);
   if(size == 0)
     {
      value = (T)0;
      return false;
     }
   
   value = arr[size - 1];
   ArrayResize(arr, size - 1);
   return true;
  }

//+------------------------------------------------------------------+
//| Remove element at specified index                                |
//| 指定されたインデックスの要素を削除                                |
//+------------------------------------------------------------------+
template<typename T>
bool SmcArrayRemoveAt(T &arr[], const int index)
  {
   int size = ArraySize(arr);
   if(index < 0 || index >= size)
      return false;
   
   // Shift elements left
   // 要素を左にシフト
   for(int i = index; i < size - 1; i++)
      arr[i] = arr[i + 1];
   
   ArrayResize(arr, size - 1);
   return true;
  }

//+------------------------------------------------------------------+
//| Insert value at specified index                                  |
//| 指定されたインデックスに値を挿入                                  |
//+------------------------------------------------------------------+
template<typename T>
bool SmcArrayInsertAt(T &arr[], const int index, const T value)
  {
   int size = ArraySize(arr);
   if(index < 0 || index > size)
      return false;
   
   ArrayResize(arr, size + 1);
   
   // Shift elements right
   // 要素を右にシフト
   for(int i = size; i > index; i--)
      arr[i] = arr[i - 1];
   
   arr[index] = value;
   return true;
  }

//--- Specialized Double Array Functions / 専用double配列関数

//+------------------------------------------------------------------+
//| Find maximum value in double array                                |
//| double配列の最大値を検索                                          |
//+------------------------------------------------------------------+
double SmcArrayMax(double &arr[], const int count = WHOLE_ARRAY)
  {
   int size = (count == WHOLE_ARRAY) ? ArraySize(arr) : count;
   if(size == 0)
      return 0.0;
   
   double maxVal = arr[0];
   for(int i = 1; i < size; i++)
     {
      if(arr[i] > maxVal)
         maxVal = arr[i];
     }
   
   return maxVal;
  }

//+------------------------------------------------------------------+
//| Find minimum value in double array                                |
//| double配列の最小値を検索                                          |
//+------------------------------------------------------------------+
double SmcArrayMin(double &arr[], const int count = WHOLE_ARRAY)
  {
   int size = (count == WHOLE_ARRAY) ? ArraySize(arr) : count;
   if(size == 0)
      return 0.0;
   
   double minVal = arr[0];
   for(int i = 1; i < size; i++)
     {
      if(arr[i] < minVal)
         minVal = arr[i];
     }
   
   return minVal;
  }

//+------------------------------------------------------------------+
//| Calculate sum of double array                                     |
//| double配列の合計を計算                                            |
//+------------------------------------------------------------------+
double SmcArraySum(double &arr[], const int count = WHOLE_ARRAY)
  {
   int size = (count == WHOLE_ARRAY) ? ArraySize(arr) : count;
   double sum = 0.0;
   
   for(int i = 0; i < size; i++)
      sum += arr[i];
   
   return sum;
  }

//+------------------------------------------------------------------+
//| Reverse order of elements in double array                         |
//| double配列の要素の順序を逆にする                                  |
//+------------------------------------------------------------------+
void SmcArrayReverse(double &arr[], const int count = WHOLE_ARRAY)
  {
   int size = (count == WHOLE_ARRAY) ? ArraySize(arr) : count;
   int half = size / 2;
   
   for(int i = 0; i < half; i++)
     {
      int j = size - 1 - i;
      double temp = arr[i];
      arr[i] = arr[j];
      arr[j] = temp;
     }
  }

//+------------------------------------------------------------------+
//| Extract slice of array (creates new array)                        |
//| 配列のスライスを抽出（新しい配列を作成）                         |
//+------------------------------------------------------------------+
bool SmcArraySlice(double &arr[], double &result[], const int start, const int end)
  {
   int size = ArraySize(arr);
   if(start < 0 || end > size || start >= end)
      return false;
   
   int sliceSize = end - start;
   ArrayResize(result, sliceSize);
   
   for(int i = 0; i < sliceSize; i++)
      result[i] = arr[start + i];
   
   return true;
  }

#endif // __SMC_ARRAY_UTILS_MQH__
//+------------------------------------------------------------------+
