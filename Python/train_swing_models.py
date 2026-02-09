"""
train_swing_models.py
======================
SMC_MultiCurrency_Swing EA 用 ONNX モデル 一括学習スクリプト

このスクリプトは以下の処理を順次実行する:
1. トレンド分類モデル (LightGBM) の学習・ONNX エクスポート
2. マーケットレジーム検出モデル (RandomForest) の学習・ONNX エクスポート
3. 出力ファイルを MQL5/Files/models/ にコピー

使い方:
  cd SMC_ICT_OSS_LIB/Python
  pip install -r requirements_swing.txt
  python train_swing_models.py

MT5 が起動している場合は実データを使用し、
起動していない場合は合成データでフォールバックする。
"""
import os
import sys
import shutil
from pathlib import Path
from datetime import datetime

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# MQL5/Files/models/ ディレクトリ（EA が読み込むパス）
SCRIPT_DIR = Path(__file__).resolve().parent
MQL5_FILES_DIR = SCRIPT_DIR.parent / "Files" / "models"

# 学習スクリプトの出力先（学習スクリプト内の output_dir）
TRAINING_OUTPUT_DIR = SCRIPT_DIR / ".." / "Files" / "models"

# 出力ファイル一覧
OUTPUT_FILES = [
    "trend_classifier.onnx",
    "trend_classifier_mean.npy",
    "trend_classifier_scale.npy",
    "market_regime.onnx",
    "market_regime_mean.npy",
    "market_regime_scale.npy",
]


def check_dependencies():
    """必要なパッケージの確認"""
    print("\n[CHECK] Checking dependencies...")
    missing = []
    for pkg in ["numpy", "pandas", "sklearn", "lightgbm", "onnx"]:
        try:
            __import__(pkg)
            print(f"  [OK] {pkg}")
        except ImportError:
            print(f"  [NG] {pkg} - MISSING")
            missing.append(pkg)

    # onnxmltools or skl2onnx
    onnx_converter = False
    for pkg in ["onnxmltools", "skl2onnx"]:
        try:
            __import__(pkg)
            print(f"  [OK] {pkg}")
            onnx_converter = True
            break
        except ImportError:
            pass
    if not onnx_converter:
        print("  [NG] onnxmltools/skl2onnx - MISSING (need at least one)")
        missing.append("onnxmltools or skl2onnx")

    # MT5 (optional)
    try:
        import MetaTrader5
        print(f"  [OK] MetaTrader5 (real data available)")
    except ImportError:
        print(f"  [--] MetaTrader5 not available (will use synthetic data)")

    if missing:
        print(f"\n  !! Missing packages: {', '.join(missing)}")
        print(f"  !! Run: pip install -r requirements_swing.txt")
        return False
    return True


def run_training_script(script_name: str) -> bool:
    """学習スクリプトの実行"""
    script_path = SCRIPT_DIR / script_name
    if not script_path.exists():
        print(f"  ERROR: {script_path} not found")
        return False

    print(f"\n{'='*70}")
    print(f" Running: {script_name}")
    print(f"{'='*70}")

    # サブプロセスではなくモジュールとして実行
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        script_name.replace(".py", ""), str(script_path))
    module = importlib.util.module_from_spec(spec)

    try:
        spec.loader.exec_module(module)
        module.main()
        return True
    except Exception as e:
        print(f"  ERROR during training: {e}")
        import traceback
        traceback.print_exc()
        return False


def verify_outputs():
    """出力ファイルの確認"""
    print(f"\n{'='*70}")
    print(" Verifying output files")
    print(f"{'='*70}")

    output_dir = TRAINING_OUTPUT_DIR.resolve()
    all_ok = True

    for fname in OUTPUT_FILES:
        fpath = output_dir / fname
        if fpath.exists():
            size = fpath.stat().st_size
            print(f"  [OK] {fname} ({size:,} bytes)")
        else:
            print(f"  [NG] {fname} - NOT FOUND")
            all_ok = False

    return all_ok


def verify_onnx_models():
    """ONNX モデルの検証"""
    print("\n[VERIFY] Validating ONNX models...")
    try:
        import onnx
        import onnxruntime as ort
        import numpy as np

        output_dir = TRAINING_OUTPUT_DIR.resolve()

        for model_name, n_classes in [("trend_classifier", 3), ("market_regime", 4)]:
            onnx_path = output_dir / f"{model_name}.onnx"
            if not onnx_path.exists():
                print(f"  SKIP: {model_name}.onnx not found")
                continue

            # 1. ONNX 形式の検証
            model = onnx.load(str(onnx_path))
            onnx.checker.check_model(model)
            print(f"  [OK] {model_name}.onnx - valid ONNX format")

            # 2. 推論テスト
            session = ort.InferenceSession(str(onnx_path))
            input_name = session.get_inputs()[0].name
            input_shape = session.get_inputs()[0].shape

            # ダミー入力で推論
            dummy = np.random.randn(1, 30).astype(np.float32)
            result = session.run(None, {input_name: dummy})
            print(f"  [OK] {model_name} inference OK - input: {input_shape}, "
                  f"outputs: {len(result)}")

            # 3. スケーラーファイル検証
            import struct
            mean_path = output_dir / f"{model_name}_mean.npy"
            scale_path = output_dir / f"{model_name}_scale.npy"

            if mean_path.exists() and scale_path.exists():
                with open(mean_path, "rb") as f:
                    mean_data = f.read()
                n_doubles = len(mean_data) // 8
                print(f"  [OK] {model_name} scaler: {n_doubles} features "
                      f"(expected {30})")
            else:
                print(f"  [NG] {model_name} scaler files missing")

    except ImportError:
        print("  SKIP: onnxruntime not installed for validation")
    except Exception as e:
        print(f"  WARNING: Validation error: {e}")


def main():
    start_time = datetime.now()

    print("=" * 70)
    print(" SMC_MultiCurrency_Swing EA - ONNX Model Training Pipeline")
    print(f" {start_time:%Y-%m-%d %H:%M:%S}")
    print("=" * 70)

    # 1. 依存関係チェック
    if not check_dependencies():
        print("\n!! Aborting due to missing dependencies.")
        sys.exit(1)

    # 2. 出力ディレクトリ作成
    MQL5_FILES_DIR.mkdir(parents=True, exist_ok=True)

    # 3. トレンド分類モデルの学習
    success1 = run_training_script("train_swing_trend_classifier.py")

    # 4. マーケットレジーム検出モデルの学習
    success2 = run_training_script("train_swing_market_regime.py")

    # 5. 出力ファイル確認
    all_ok = verify_outputs()

    # 6. ONNX モデル検証
    if all_ok:
        verify_onnx_models()

    # 7. サマリー
    elapsed = (datetime.now() - start_time).total_seconds()
    print(f"\n{'='*70}")
    print(f" Training Pipeline Complete")
    print(f" Time elapsed: {elapsed:.1f}s")
    print(f" Trend Classifier: {'OK' if success1 else 'FAILED'}")
    print(f" Market Regime:    {'OK' if success2 else 'FAILED'}")
    print(f" Files verified:   {'OK' if all_ok else 'INCOMPLETE'}")
    print(f"{'='*70}")

    if all_ok:
        resolved = TRAINING_OUTPUT_DIR.resolve()
        print(f"\n Output files are in: {resolved}")
        print(f"\n EA の入力パラメータ設定例:")
        print(f"   InpTrendModelPath  = models\\\\trend_classifier.onnx")
        print(f"   InpTrendMeanPath   = models\\\\trend_classifier_mean.npy")
        print(f"   InpTrendScalePath  = models\\\\trend_classifier_scale.npy")
        print(f"   InpRegimeModelPath = models\\\\market_regime.onnx")
        print(f"   InpRegimeMeanPath  = models\\\\market_regime_mean.npy")
        print(f"   InpRegimeScalePath = models\\\\market_regime_scale.npy")
    else:
        print("\n !! Some files are missing. Check errors above.")
        sys.exit(1)


if __name__ == "__main__":
    main()
