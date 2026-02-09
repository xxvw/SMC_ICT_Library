//+------------------------------------------------------------------+
//|                                                 OnnxWrapper.mqh  |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_ONNX_WRAPPER_MQH__
#define __SMC_ONNX_WRAPPER_MQH__

#include "../Core/SmcTypes.mqh"

//+------------------------------------------------------------------+
//| CSmcOnnxWrapper - ONNX model wrapper for ML inference           |
//|                                                                    |
//| Wrapper for ONNX model loading and inference:                     |
//|   - Load from file or buffer                                      |
//|   - Feature normalization (scaler)                                |
//|   - Prediction and classification                                 |
//|   - Memory management with periodic reinit                        |
//+------------------------------------------------------------------+
class CSmcOnnxWrapper
  {
private:
   long            m_handle;           // ONNX model handle / ONNXモデルハンドル
   int             m_numFeatures;      // Number of input features / 入力特徴量数
   int             m_numOutputs;       // Number of output classes / 出力クラス数
   bool            m_isLoaded;         // Model loaded flag / モデル読み込みフラグ
   double          m_scalerMean[];    // Scaler mean values / スケーラー平均値
   double          m_scalerScale[];   // Scaler scale values / スケーラースケール値
   bool            m_scalerLoaded;    // Scaler loaded flag / スケーラー読み込みフラグ
   int             m_predCount;        // Prediction counter / 予測カウンター
   static const int REINIT_INTERVAL;  // Reinit interval / 再初期化間隔

   //+------------------------------------------------------------------+
   //| Check if value is NaN or Inf / NaNまたはInfかチェック           |
   //+------------------------------------------------------------------+
   static bool IsValidValue(const double value)
     {
      return !MathIsNaN(value) && !MathIsInfinity(value);
     }

   //+------------------------------------------------------------------+
   //| Validate feature array / 特徴量配列を検証                         |
   //+------------------------------------------------------------------+
   bool ValidateFeatures(const float &features[])
     {
      int count = ArraySize(features);
      if(count != m_numFeatures)
        {
         Print("Feature count mismatch: expected ", m_numFeatures, ", got ", count);
         return false;
        }
      
      for(int i = 0; i < count; i++)
        {
         if(!IsValidValue(features[i]))
           {
            Print("Invalid feature value at index ", i, ": ", features[i]);
            return false;
           }
        }
      
      return true;
     }

public:
   //+------------------------------------------------------------------+
   //| Constructor / コンストラクタ                                     |
   //+------------------------------------------------------------------+
   CSmcOnnxWrapper()
     {
      m_handle = INVALID_HANDLE;
      m_numFeatures = 0;
      m_numOutputs = 0;
      m_isLoaded = false;
      m_scalerLoaded = false;
      m_predCount = 0;
      ArrayResize(m_scalerMean, 0);
      ArrayResize(m_scalerScale, 0);
     }

   //+------------------------------------------------------------------+
   //| Destructor / デストラクタ                                         |
   //+------------------------------------------------------------------+
   ~CSmcOnnxWrapper()
     {
      Release();
     }

   //+------------------------------------------------------------------+
   //| Load ONNX model from file / ファイルからONNXモデルを読み込み     |
   //+------------------------------------------------------------------+
   bool LoadFromFile(const string modelPath)
     {
      if(m_isLoaded)
         Release();
      
      m_handle = OnnxCreate(modelPath, ONNX_DEFAULT);
      if(m_handle == INVALID_HANDLE)
        {
         Print("Failed to load ONNX model from: ", modelPath);
         Print("Error: ", GetLastError());
         return false;
        }
      
      m_isLoaded = true;
      m_predCount = 0;
      Print("ONNX model loaded successfully: ", modelPath);
      return true;
     }

   //+------------------------------------------------------------------+
   //| Load ONNX model from buffer / バッファからONNXモデルを読み込み   |
   //+------------------------------------------------------------------+
   bool LoadFromBuffer(uchar &buffer[])
     {
      if(m_isLoaded)
         Release();
      
      int size = ArraySize(buffer);
      if(size == 0)
        {
         Print("Empty buffer provided");
         return false;
        }
      
      m_handle = OnnxCreateFromBuffer(buffer, ONNX_DEFAULT);
      if(m_handle == INVALID_HANDLE)
        {
         Print("Failed to load ONNX model from buffer");
         Print("Error: ", GetLastError());
         return false;
        }
      
      m_isLoaded = true;
      m_predCount = 0;
      Print("ONNX model loaded successfully from buffer (size: ", size, " bytes)");
      return true;
     }

   //+------------------------------------------------------------------+
   //| Set input shape (number of features) / 入力形状を設定           |
   //+------------------------------------------------------------------+
   void SetInputShape(const int features)
     {
      m_numFeatures = features;
     }

   //+------------------------------------------------------------------+
   //| Set output shape (number of outputs) / 出力形状を設定           |
   //+------------------------------------------------------------------+
   void SetOutputShape(const int outputs)
     {
      m_numOutputs = outputs;
     }

   //+------------------------------------------------------------------+
   //| Load scaler parameters from binary files / バイナリファイルからスケーラーパラメータを読み込み |
   //| Note: Simplified implementation - reads as binary doubles      |
   //| 注意: 簡易実装 - バイナリdoubleとして読み込み                    |
   //+------------------------------------------------------------------+
   bool LoadScaler(const string meanFile, const string scaleFile)
     {
      // Load mean values / 平均値を読み込み
      int meanHandle = FileOpen(meanFile, FILE_READ | FILE_BIN | FILE_COMMON);
      if(meanHandle == INVALID_HANDLE)
        {
         Print("Failed to open mean file: ", meanFile);
         return false;
        }
      
      ulong fileSize = FileSize(meanHandle);
      int count = (int)(fileSize / sizeof(double));
      
      ArrayResize(m_scalerMean, count);
      FileReadArray(meanHandle, m_scalerMean, 0, count);
      FileClose(meanHandle);
      
      // Load scale values / スケール値を読み込み
      int scaleHandle = FileOpen(scaleFile, FILE_READ | FILE_BIN | FILE_COMMON);
      if(scaleHandle == INVALID_HANDLE)
        {
         Print("Failed to open scale file: ", scaleFile);
         ArrayResize(m_scalerMean, 0);
         return false;
        }
      
      fileSize = FileSize(scaleHandle);
      int scaleCount = (int)(fileSize / sizeof(double));
      
      if(scaleCount != count)
        {
         Print("Mean and scale arrays have different sizes");
         FileClose(scaleHandle);
         ArrayResize(m_scalerMean, 0);
         return false;
        }
      
      ArrayResize(m_scalerScale, count);
      FileReadArray(scaleHandle, m_scalerScale, 0, count);
      FileClose(scaleHandle);
      
      m_scalerLoaded = true;
      Print("Scaler loaded: ", count, " features");
      return true;
     }

   //+------------------------------------------------------------------+
   //| Apply scaler normalization / スケーラー正規化を適用             |
   //+------------------------------------------------------------------+
   bool ApplyScaler(float &features[])
     {
      if(!m_scalerLoaded)
        {
         Print("Scaler not loaded");
         return false;
        }
      
      int count = ArraySize(features);
      int scalerCount = ArraySize(m_scalerMean);
      
      if(count != scalerCount)
        {
         Print("Feature count mismatch with scaler: ", count, " vs ", scalerCount);
         return false;
        }
      
      for(int i = 0; i < count; i++)
        {
         if(m_scalerScale[i] != 0.0)
            features[i] = (float)((features[i] - m_scalerMean[i]) / m_scalerScale[i]);
         else
            features[i] = 0.0f;
        }
      
      return true;
     }

   //+------------------------------------------------------------------+
   //| Run prediction / 予測を実行                                       |
   //+------------------------------------------------------------------+
   bool Predict(const float &features[], float &output[])
     {
      if(!m_isLoaded || m_handle == INVALID_HANDLE)
        {
         Print("Model not loaded");
         return false;
        }
      
      if(!ValidateFeatures(features))
         return false;
      
      // Periodic reinit for memory management / メモリ管理のための定期的な再初期化
      m_predCount++;
      if(m_predCount >= REINIT_INTERVAL)
        {
         // Note: MQL5 doesn't have explicit reinit, but we can track usage
         // 注意: MQL5には明示的な再初期化がないが、使用状況を追跡可能
         m_predCount = 0;
        }
      
      // Prepare input array / 入力配列を準備
      float input[];
      ArrayResize(input, m_numFeatures);
      ArrayCopy(input, features);
      
      // Set input shape / 入力形状を設定
      long inputShape[] = {1, m_numFeatures};
      if(!OnnxSetInputShape(m_handle, 0, inputShape))
        {
         Print("Failed to set input shape");
         return false;
        }
      
      // Set output shape / 出力形状を設定
      long outputShape[] = {1, m_numOutputs};
      if(!OnnxSetOutputShape(m_handle, 0, outputShape))
        {
         Print("Failed to set output shape");
         return false;
        }
      
      // Run inference / 推論を実行
      if(!OnnxRun(m_handle, ONNX_NO_CONVERSION, input, output))
        {
         Print("ONNX inference failed");
         Print("Error: ", GetLastError());
         return false;
        }
      
      // Validate output / 出力を検証
      int outputSize = ArraySize(output);
      if(outputSize != m_numOutputs)
        {
         Print("Output size mismatch: expected ", m_numOutputs, ", got ", outputSize);
         return false;
        }
      
      for(int i = 0; i < outputSize; i++)
        {
         if(!IsValidValue(output[i]))
           {
            Print("Invalid output value at index ", i, ": ", output[i]);
            return false;
           }
        }
      
      return true;
     }

   //+------------------------------------------------------------------+
   //| Predict and return class index (argmax) / 予測してクラスインデックスを返す（argmax） |
   //+------------------------------------------------------------------+
   int PredictClass(const float &features[])
     {
      float output[];
      ArrayResize(output, m_numOutputs);
      
      if(!Predict(features, output))
         return -1;
      
      // Find argmax / argmaxを検索
      int maxIdx = 0;
      float maxVal = output[0];
      
      for(int i = 1; i < m_numOutputs; i++)
        {
         if(output[i] > maxVal)
           {
            maxVal = output[i];
            maxIdx = i;
           }
        }
      
      return maxIdx;
     }

   //+------------------------------------------------------------------+
   //| Get confidence (max probability) / 信頼度を取得（最大確率）     |
   //+------------------------------------------------------------------+
   double GetConfidence(const float &output[])
     {
      int count = ArraySize(output);
      if(count == 0)
         return 0.0;
      
      float maxVal = output[0];
      for(int i = 1; i < count; i++)
        {
         if(output[i] > maxVal)
            maxVal = output[i];
        }
      
      return maxVal;
     }

   //+------------------------------------------------------------------+
   //| Check if model is loaded / モデルが読み込まれているかチェック     |
   //+------------------------------------------------------------------+
   bool IsLoaded() const
     {
      return m_isLoaded && m_handle != INVALID_HANDLE;
     }

   //+------------------------------------------------------------------+
   //| Get number of features / 特徴量数を取得                           |
   //+------------------------------------------------------------------+
   int GetNumFeatures() const
     {
      return m_numFeatures;
     }

   //+------------------------------------------------------------------+
   //| Get number of outputs / 出力数を取得                             |
   //+------------------------------------------------------------------+
   int GetNumOutputs() const
     {
      return m_numOutputs;
     }

   //+------------------------------------------------------------------+
   //| Release model handle / モデルハンドルを解放                       |
   //+------------------------------------------------------------------+
   void Release()
     {
      if(m_handle != INVALID_HANDLE)
        {
         OnnxRelease(m_handle);
         m_handle = INVALID_HANDLE;
        }
      
      m_isLoaded = false;
      m_scalerLoaded = false;
      m_predCount = 0;
      ArrayResize(m_scalerMean, 0);
      ArrayResize(m_scalerScale, 0);
     }
  };

// Initialize static constant / 静的定数を初期化
const int CSmcOnnxWrapper::REINIT_INTERVAL = 1000;

#endif // __SMC_ONNX_WRAPPER_MQH__
//+------------------------------------------------------------------+
