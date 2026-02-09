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
   bool            m_probaChecked;    // Whether PredictProba has been tested
   bool            m_probaSupported;  // Whether PredictProba works (zipmap=False)
   bool            m_labelDirectOk;   // Whether PredictLabelDirect works (ZipMap fallback)

   //+------------------------------------------------------------------+
   //| Check if value is NaN or Inf / NaNまたはInfかチェック           |
   //+------------------------------------------------------------------+
   static bool IsValidValue(const double value)
     {
      return MathIsValidNumber(value);
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
      m_probaChecked = false;
      m_probaSupported = false;
      m_labelDirectOk = false;
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
   //| Tries MQL5/Files/ first, then Common/Files/ (for Tester)        |
   //| まず MQL5/Files/ を試し、失敗時は Common/Files/ にフォールバック   |
   //+------------------------------------------------------------------+
   bool LoadFromFile(const string modelPath)
     {
      if(m_isLoaded)
         Release();
      
      // Try terminal-specific folder first (MQL5/Files/)
      m_handle = OnnxCreate(modelPath, ONNX_DEFAULT);
      if(m_handle == INVALID_HANDLE)
        {
         // Fallback to common folder (Terminal/Common/Files/) for Strategy Tester
         ResetLastError();
         m_handle = OnnxCreate(modelPath, ONNX_COMMON_FOLDER);
         if(m_handle == INVALID_HANDLE)
           {
            Print("Failed to load ONNX model from: ", modelPath);
            Print("Error: ", GetLastError());
            return false;
           }
         Print("ONNX model loaded from Common folder: ", modelPath);
        }
      else
         Print("ONNX model loaded successfully: ", modelPath);
      
      m_isLoaded = true;
      m_predCount = 0;
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
   //| Load scaler parameters from binary files                         |
   //| バイナリファイルからスケーラーパラメータを読み込み                 |
   //| Files must be placed in MQL5/Files/ (same as ONNX models)       |
   //| ファイルは MQL5/Files/ に配置（ONNXモデルと同じ場所）            |
   //+------------------------------------------------------------------+
   bool LoadScaler(const string meanFile, const string scaleFile)
     {
      // Load mean values / 平均値を読み込み
      int meanHandle = FileOpen(meanFile, FILE_READ | FILE_BIN);
      if(meanHandle == INVALID_HANDLE)
        {
         // Fallback: try FILE_COMMON for backward compatibility
         meanHandle = FileOpen(meanFile, FILE_READ | FILE_BIN | FILE_COMMON);
         if(meanHandle == INVALID_HANDLE)
           {
            Print("Failed to open mean file: ", meanFile, " (error: ", GetLastError(), ")");
            return false;
           }
        }
      
      ulong fileSize = FileSize(meanHandle);
      int count = (int)(fileSize / sizeof(double));
      
      ArrayResize(m_scalerMean, count);
      FileReadArray(meanHandle, m_scalerMean, 0, count);
      FileClose(meanHandle);
      
      // Load scale values / スケール値を読み込み
      int scaleHandle = FileOpen(scaleFile, FILE_READ | FILE_BIN);
      if(scaleHandle == INVALID_HANDLE)
        {
         // Fallback: try FILE_COMMON for backward compatibility
         scaleHandle = FileOpen(scaleFile, FILE_READ | FILE_BIN | FILE_COMMON);
         if(scaleHandle == INVALID_HANDLE)
           {
            Print("Failed to open scale file: ", scaleFile, " (error: ", GetLastError(), ")");
            ArrayResize(m_scalerMean, 0);
            return false;
           }
        }
      
      fileSize = FileSize(scaleHandle);
      int scaleCount = (int)(fileSize / sizeof(double));
      
      if(scaleCount != count)
        {
         Print("Mean and scale arrays have different sizes: ", count, " vs ", scaleCount);
         FileClose(scaleHandle);
         ArrayResize(m_scalerMean, 0);
         return false;
        }
      
      ArrayResize(m_scalerScale, count);
      FileReadArray(scaleHandle, m_scalerScale, 0, count);
      FileClose(scaleHandle);
      
      m_scalerLoaded = true;
      Print("Scaler loaded: ", count, " features from ", meanFile);
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
   //| Run prediction (single-output model) / 予測を実行（単一出力モデル）|
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
      
      m_predCount++;
      if(m_predCount >= REINIT_INTERVAL)
         m_predCount = 0;
      
      // Prepare input array / 入力配列を準備
      float featInput[];
      ArrayResize(featInput, m_numFeatures);
      ArrayCopy(featInput, features);
      
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
      if(!OnnxRun(m_handle, ONNX_NO_CONVERSION, featInput, output))
        {
         Print("ONNX inference failed, error: ", GetLastError());
         return false;
        }
      
      // Validate output / 出力を検証
      int outputSize = ArraySize(output);
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
   //| Run prediction for tree-based classifiers (2-output ONNX)        |
   //| sklearn/LightGBM ONNX モデル用の予測実行                         |
   //|   output 0 = predicted labels (int64)                             |
   //|   output 1 = class probabilities (float, shape [1, num_classes]) |
   //+------------------------------------------------------------------+
   bool PredictProba(const float &features[], long &labelOut[], float &probaOut[])
     {
      if(!m_isLoaded || m_handle == INVALID_HANDLE)
         return false;
      
      // Already tested and failed → skip immediately
      if(m_probaChecked && !m_probaSupported)
         return false;
      
      if(!ValidateFeatures(features))
         return false;
      
      m_predCount++;
      if(m_predCount >= REINIT_INTERVAL)
         m_predCount = 0;
      
      // Prepare input array / 入力配列を準備
      float featInput[];
      ArrayResize(featInput, m_numFeatures);
      ArrayCopy(featInput, features);
      
      // Set input shape / 入力形状を設定
      long inputShape[] = {1, m_numFeatures};
      if(!OnnxSetInputShape(m_handle, 0, inputShape))
        {
         Print("PredictProba: Failed to set input shape, error: ", GetLastError());
         return false;
        }
      
      // Output 0: label shape [1] / ラベル出力 [1]
      ArrayResize(labelOut, 1);
      long labelShape[] = {1};
      if(!OnnxSetOutputShape(m_handle, 0, labelShape))
        {
         Print("PredictProba: Failed to set label output shape, error: ", GetLastError());
         return false;
        }
      
      // Output 1: probability shape [1, num_classes] / 確率出力 [1, num_classes]
      ArrayResize(probaOut, m_numOutputs);
      long probaShape[] = {1, m_numOutputs};
      if(!OnnxSetOutputShape(m_handle, 1, probaShape))
        {
         // ZipMap model detected - mark as unsupported (log once)
         if(!m_probaChecked)
           {
            Print("ONNX INFO: Model uses ZipMap (sequence/map) output. ",
                  "Switching to label-only mode. ",
                  "For full probability support, re-export with zipmap=False.");
            m_probaChecked  = true;
            m_probaSupported = false;
           }
         ResetLastError();
         return false;
        }
      
      // Run inference with 2 outputs / 2出力で推論を実行
      if(!OnnxRun(m_handle, ONNX_NO_CONVERSION, featInput, labelOut, probaOut))
        {
         Print("PredictProba: ONNX inference failed, error: ", GetLastError());
         return false;
        }
      
      // Mark as supported
      if(!m_probaChecked)
        {
         m_probaChecked  = true;
         m_probaSupported = true;
        }
      
      return true;
     }

   //+------------------------------------------------------------------+
   //| Predict label only using ONNX_DEFAULT (ZipMap fallback)          |
   //| ZipMapモデル用フォールバック: ラベルのみ取得                       |
   //| Uses ONNX_DEFAULT flag to auto-convert map outputs               |
   //+------------------------------------------------------------------+
   bool PredictLabelDirect(const float &features[], long &labelOut[])
     {
      if(!m_isLoaded || m_handle == INVALID_HANDLE)
         return false;
      
      if(!ValidateFeatures(features))
         return false;
      
      float featInput[];
      ArrayResize(featInput, m_numFeatures);
      ArrayCopy(featInput, features);
      
      // Set input shape
      long inputShape[] = {1, m_numFeatures};
      if(!OnnxSetInputShape(m_handle, 0, inputShape))
         return false;
      
      // Output 0: label shape [1]
      ArrayResize(labelOut, 1);
      long labelShape[] = {1};
      if(!OnnxSetOutputShape(m_handle, 0, labelShape))
         return false;
      
      // Output 1: don't set shape (let runtime auto-handle ZipMap)
      // Provide a dummy buffer for the map output
      float dummyProba[];
      ArrayResize(dummyProba, m_numOutputs);
      
      ResetLastError();
      
      // Try ONNX_DEFAULT for auto-conversion of ZipMap outputs
      if(OnnxRun(m_handle, ONNX_DEFAULT, featInput, labelOut, dummyProba))
         return true;
      
      ResetLastError();
      return false;
     }

   //+------------------------------------------------------------------+
   //| Predict class and get probabilities for tree-based classifiers   |
   //| ツリーベース分類器のクラス予測 + 確率取得                         |
   //| Returns: predicted class index, fills proba[] with probabilities |
   //+------------------------------------------------------------------+
   int PredictClassProba(const float &features[], float &proba[])
     {
      long labels[];
      float probaOut[];
      
      // --- Try 1: Full 2-output prediction (zipmap=False models)
      if(PredictProba(features, labels, probaOut))
        {
         int probaSize = ArraySize(probaOut);
         ArrayResize(proba, probaSize);
         ArrayCopy(proba, probaOut);
         
         if(ArraySize(labels) > 0)
            return (int)labels[0];
         
         // Fallback: argmax on probabilities
         int maxIdx = 0;
         float maxVal = proba[0];
         for(int i = 1; i < probaSize; i++)
           {
            if(proba[i] > maxVal)
              { maxVal = proba[i]; maxIdx = i; }
           }
         return maxIdx;
        }
      
      // --- Try 2: Label-only (ZipMap fallback with ONNX_DEFAULT)
      if(PredictLabelDirect(features, labels))
        {
         if(ArraySize(labels) > 0)
           {
            int cls = (int)labels[0];
            // Generate synthetic probability array (label has no proba info)
            ArrayResize(proba, m_numOutputs);
            ArrayInitialize(proba, 0.0f);
            if(cls >= 0 && cls < m_numOutputs)
               proba[cls] = 0.70f;   // Default confidence for ZipMap mode
            if(!m_labelDirectOk)
              {
               Print("ONNX INFO: PredictLabelDirect succeeded (ZipMap mode). ",
                     "Confidence values are synthetic (0.70).");
               m_labelDirectOk = true;
              }
            return cls;
           }
        }
      
      return -1;
     }

   //+------------------------------------------------------------------+
   //| Predict and return class index (argmax)                           |
   //| 予測してクラスインデックスを返す（argmax）                       |
   //| Tries PredictProba → PredictLabelDirect → Predict                |
   //+------------------------------------------------------------------+
   int PredictClass(const float &features[])
     {
      // Try 1: tree-based classifier (2 outputs, zipmap=False)
      long labels[];
      float probaOut[];
      
      if(PredictProba(features, labels, probaOut))
        {
         if(ArraySize(labels) > 0)
            return (int)labels[0];
        }
      
      // Try 2: label-only (ZipMap fallback)
      if(PredictLabelDirect(features, labels))
        {
         if(ArraySize(labels) > 0)
            return (int)labels[0];
        }
      
      // Try 3: single-output format fallback
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
      
      return (double)maxVal;
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
      m_probaChecked = false;
      m_probaSupported = false;
      m_labelDirectOk = false;
      ArrayResize(m_scalerMean, 0);
      ArrayResize(m_scalerScale, 0);
     }
  };

// Initialize static constant / 静的定数を初期化
const int CSmcOnnxWrapper::REINIT_INTERVAL = 1000;

#endif // __SMC_ONNX_WRAPPER_MQH__
//+------------------------------------------------------------------+
