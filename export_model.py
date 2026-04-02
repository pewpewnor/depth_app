#!/usr/bin/env python3
import torch
from pathlib import Path
import numpy as np
import json
from datetime import datetime

MODEL_NAME = "depth-anything/Depth-Anything-V2-Small-hf"
EXPORT_DIR = Path(".") / "assets" / "models"
ONNX_PATH = EXPORT_DIR / "depth_model.onnx"
CALIBRATION_PATH = EXPORT_DIR / "calibration.json"

def check_cuda():
    if torch.cuda.is_available():
        device_name = torch.cuda.get_device_name(0)
        print(f"✓ CUDA available. Using device: {device_name}")
        return torch.device("cuda")
    else:
        print("ℹ Using CPU (CUDA not available)")
        return torch.device("cpu")

def create_calibration_file():
    """Create a calibration JSON file with default values and metadata."""
    calibration_data = {
        "version": "1.0",
        "model_name": MODEL_NAME,
        "export_date": datetime.now().isoformat(),
        "model_input_size": 518,
        "model_output_size": 518,
        "calibration": {
            "default_value": 147.0,
            "default_distance_meters": 6.0,
            "description": "Default calibration: raw model output 147.0 corresponds to 6.0 meters (0-255 range)"
        },
        "notes": "This calibration file provides default values for depth-to-meters conversion. Users can capture their own calibration by following the in-app calibration process."
    }
    
    try:
        with open(CALIBRATION_PATH, 'w') as f:
            json.dump(calibration_data, f, indent=2)
        print(f"✓ Calibration file created: {CALIBRATION_PATH}")
        return True
    except Exception as e:
        print(f"✗ Failed to create calibration file: {e}")
        return False

def download_and_export_model():
    device = check_cuda()
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    
    print(f"Downloading model: {MODEL_NAME}")
    from transformers import AutoImageProcessor, AutoModelForDepthEstimation
    
    processor = AutoImageProcessor.from_pretrained(MODEL_NAME)
    model = AutoModelForDepthEstimation.from_pretrained(MODEL_NAME)
    model.to(device)
    model.eval()
    
    print(f"Model loaded successfully")
    
    print(f"Creating dummy input...")
    dummy_input = torch.randn(1, 3, 518, 518).to(device)
    
    print(f"Exporting to ONNX: {ONNX_PATH}")
    try:
        torch.onnx.export(
            model,
            dummy_input,
            str(ONNX_PATH),
            input_names=["pixel_values"],
            output_names=["predicted_depth"],
            opset_version=14,
            do_constant_folding=True,
            dynamic_axes={"pixel_values": {0: "batch_size"}},
            verbose=False,
        )
        print(f"✓ ONNX export successful!")
        
        if ONNX_PATH.exists():
            size_mb = ONNX_PATH.stat().st_size / 1024 / 1024
            print(f"✓ Model size: {size_mb:.2f} MB")
            print(f"✓ Model ready at: {ONNX_PATH}")
            test_onnx_model()
        else:
            print(f"✗ ONNX model not created")
            
    except Exception as e:
        print(f"✗ ONNX export failed: {e}")
        raise

def test_onnx_model():
    try:
        import onnxruntime as rt
        print(f"\n🧪 Testing ONNX model...")
        
        # Use only available providers
        sess = rt.InferenceSession(str(ONNX_PATH), providers=["CPUExecutionProvider"])
        print(f"✓ Inference session created")
        
        dummy_input = np.random.randn(1, 3, 518, 518).astype(np.float32)
        outputs = sess.run(None, {"pixel_values": dummy_input})
        
        print(f"✓ Test inference successful!")
        print(f"✓ Output shape: {outputs[0].shape}")
        min_val = outputs[0].min()
        max_val = outputs[0].max()
        mean_val = outputs[0].mean()
        print(f"✓ Output min: {min_val:.4f}")
        print(f"✓ Output max: {max_val:.4f}")
        print(f"✓ Output mean: {mean_val:.4f}")
        print(f"✓ Output range: {min_val:.4f} to {max_val:.4f}")
        
    except Exception as e:
        print(f"✗ ONNX test failed: {e}")

if __name__ == "__main__":
    download_and_export_model()
    print("\n📋 Creating calibration file...")
    if create_calibration_file():
        print("\n✓ Model export and calibration setup complete!")
        print(f"✓ Files ready for mobile deployment:")
        print(f"   - Model: {ONNX_PATH}")
        print(f"   - Calibration: {CALIBRATION_PATH}")
    else:
        print("\n⚠ Model exported but calibration file creation failed")





