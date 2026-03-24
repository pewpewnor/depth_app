#!/usr/bin/env python3
import torch
from pathlib import Path
import numpy as np

MODEL_NAME = "LiheYoung/depth-anything-small-hf"
EXPORT_DIR = Path(".") / "assets" / "models"
ONNX_PATH = EXPORT_DIR / "depth_model.onnx"

def check_cuda():
    if torch.cuda.is_available():
        device_name = torch.cuda.get_device_name(0)
        print(f"✓ CUDA available. Using device: {device_name}")
        return torch.device("cuda")
    else:
        print("ℹ Using CPU (CUDA not available)")
        return torch.device("cpu")

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
        print(f"✓ Output range: {outputs[0].min():.4f} to {outputs[0].max():.4f}")
        
    except Exception as e:
        print(f"✗ ONNX test failed: {e}")

if __name__ == "__main__":
    download_and_export_model()
    print("\n✓ Model export complete! Ready for mobile deployment.")




