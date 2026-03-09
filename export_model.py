#!/usr/bin/env python3
import os
import torch
import onnx
from pathlib import Path
from transformers import AutoImageProcessor, AutoModelForDepthEstimation
from transformers.onnx import from_transformers
import numpy as np
from PIL import Image
import onnxruntime as rt

MODEL_NAME = "LiheYoung/depth-anything-small-hf"
EXPORT_DIR = Path(__file__).parent / "assets" / "models"
ONNX_PATH = EXPORT_DIR / "depth_model.onnx"
TFLITE_PATH = EXPORT_DIR / "depth_model.tflite"

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
    image_processor = AutoImageProcessor.from_pretrained(MODEL_NAME)
    model = AutoModelForDepthEstimation.from_pretrained(MODEL_NAME)
    model.to(device)
    model.eval()
    
    print(f"Exporting to ONNX: {ONNX_PATH}")
    onnx_model = from_transformers(
        model,
        model_type="depth-estimation",
        task="depth-estimation",
        opset=14,
    )
    
    dummy_input = {
        "pixel_values": torch.randn(1, 3, 518, 518).to(device)
    }
    
    torch.onnx.export(
        model,
        tuple(dummy_input.values()) if isinstance(dummy_input, dict) else dummy_input,
        str(ONNX_PATH),
        input_names=["pixel_values"],
        output_names=["predicted_depth"],
        opset_version=14,
        do_constant_folding=True,
        verbose=False,
    )
    
    print(f"ONNX model exported successfully to {ONNX_PATH}")
    print(f"Model size: {ONNX_PATH.stat().st_size / 1024 / 1024:.2f} MB")
    
    test_onnx_model(image_processor)

def test_onnx_model(image_processor):
    print("\nTesting ONNX model...")
    
    dummy_image = Image.new('RGB', (518, 518), color='red')
    
    inputs = image_processor(images=dummy_image, return_tensors="np")
    pixel_values = inputs["pixel_values"].astype(np.float32)
    
    sess = rt.InferenceSession(str(ONNX_PATH))
    output_names = [output.name for output in sess.get_outputs()]
    outputs = sess.run(output_names, {"pixel_values": pixel_values})
    
    depth = outputs[0]
    print(f"Depth output shape: {depth.shape}")
    print(f"Depth range: {depth.min():.4f} to {depth.max():.4f}")
    print(f"Depth at center: {depth[0, 0, depth.shape[2]//2, depth.shape[3]//2]:.4f}")
    print("ONNX test successful!")

if __name__ == "__main__":
    download_and_export_model()
