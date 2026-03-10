#!/usr/bin/env python3
import torch
from pathlib import Path
from PIL import Image
import numpy as np

MODEL_NAME = "LiheYoung/depth-anything-small-hf"
EXPORT_DIR = Path(".") / "assets" / "models"
ONNX_PATH = EXPORT_DIR / "depth_model.onnx"

def check_cuda():
    if torch.cuda.is_available():
        print(f"CUDA available. Using device: {torch.cuda.get_device_name(0)}")
        return torch.device("cuda")
    else:
        print("CUDA not available. Using CPU")
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
        print(f"ONNX export successful!")
    except Exception as e:
        print(f"ONNX export failed: {e}")
        print(f"Using pipeline interface instead (model cached in huggingface)")
        return
    
    if ONNX_PATH.exists():
        size_mb = ONNX_PATH.stat().st_size / 1024 / 1024
        print(f"Model size: {size_mb:.2f} MB")
        print(f"ONNX model ready at: {ONNX_PATH}")
        test_onnx_model()
    else:
        print(f"ONNX model not created")

def test_onnx_model():
    try:
        import onnxruntime as rt
        print(f"\nTesting ONNX model...")
        
        sess = rt.InferenceSession(str(ONNX_PATH), providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
        print(f"Inference session created")
        
        dummy_input = np.random.randn(1, 3, 518, 518).astype(np.float32)
        outputs = sess.run(None, {"pixel_values": dummy_input})
        
        print(f"Test inference successful!")
        print(f"Output shape: {outputs[0].shape}")
        print(f"Output range: {outputs[0].min():.4f} to {outputs[0].max():.4f}")
        
    except Exception as e:
        print(f"ONNX test failed: {e}")

if __name__ == "__main__":
    download_and_export_model()


