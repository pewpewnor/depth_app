#!/usr/bin/env python3
"""
Export Depth Anything V3 (DA3METRIC-LARGE) to ONNX for mobile deployment.

DA3METRIC-LARGE outputs metric depth in real-world METERS directly.
No calibration needed for scale — the model is already metric.

Model output:
  - Tensor name : "depth"
  - Shape       : [1, 1, H, W]  (batch, channel, height, width)
  - Value range : float32 meters (typically 0–30 m)

Input:
  - Tensor name : "image"
  - Shape       : [1, 3, H, W]
  - Preprocessing: resize to (TARGET_H, TARGET_W), ImageNet normalisation
                   mean=[0.485,0.456,0.406], std=[0.229,0.224,0.225]

WARNING: DA3METRIC-LARGE is a large model (~1–2 GB ONNX).
  The resulting APK will be very large. Consider downloading the model
  at runtime instead of bundling it in the APK assets.
"""

import json
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
MODEL_VARIANT = "DA3METRIC-LARGE"   # outputs metric depth in metres
TARGET_H = 518                       # must be a multiple of 14 (ViT patch size)
TARGET_W = 518

EXPORT_DIR    = Path(".") / "assets" / "models"
ONNX_PATH     = EXPORT_DIR / "depth_model.onnx"
CALIB_PATH    = EXPORT_DIR / "calibration.json"

DA3_REPO_DIR  = Path("/tmp/depth_anything_3")
DA3_ONNX_DIR  = Path("/tmp/da3_onnx")

DA3_REPO_URL  = "https://github.com/ByteDance-Seed/Depth-Anything-3"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def run(cmd, **kwargs):
    print(f"  $ {' '.join(str(c) for c in cmd)}")
    subprocess.run(cmd, check=True, **kwargs)


def check_cuda():
    try:
        import torch
        if torch.cuda.is_available():
            print(f"CUDA: {torch.cuda.get_device_name(0)}")
            return True
    except ImportError:
        pass
    print("CUDA not available — using CPU (export will be slower)")
    return False


# ---------------------------------------------------------------------------
# Step 1: Clone / update the DA3 repository
# ---------------------------------------------------------------------------

def clone_da3_repo():
    if DA3_REPO_DIR.exists():
        print(f"DA3 repo found at {DA3_REPO_DIR}, pulling latest …")
        subprocess.run(["git", "-C", str(DA3_REPO_DIR), "pull", "--ff-only"],
                       capture_output=True)
    else:
        print(f"Cloning {DA3_REPO_URL} …")
        run(["git", "clone", "--depth=1", DA3_REPO_URL, str(DA3_REPO_DIR)])
    print(f"✓ DA3 repo ready")


# ---------------------------------------------------------------------------
# Step 2: Patch bfloat16 → float16 (ONNX does not support bfloat16)
# ---------------------------------------------------------------------------

def patch_bfloat16():
    candidates = [
        DA3_REPO_DIR / "src" / "depth_anything_3" / "api.py",
        DA3_REPO_DIR / "depth_anything_3" / "api.py",
    ]
    for api_path in candidates:
        if api_path.exists():
            text = api_path.read_text()
            if "bfloat16" in text:
                patched = text.replace(
                    "torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16",
                    "torch.float16",
                )
                api_path.write_text(patched)
                print(f"✓ Patched bfloat16 → float16 in {api_path.name}")
            else:
                print(f"✓ No bfloat16 patch needed in {api_path.name}")
            return
    print("⚠  Could not locate api.py for bfloat16 patch — continuing anyway")


# ---------------------------------------------------------------------------
# Step 3: Install DA3 requirements into the current environment
# ---------------------------------------------------------------------------

def install_requirements():
    req = DA3_REPO_DIR / "requirements.txt"
    if req.exists():
        print("Installing DA3 requirements …")
        run([sys.executable, "-m", "pip", "install", "-r", str(req), "-q"])
        print("✓ Requirements installed")
    else:
        print("⚠  requirements.txt not found — skipping pip install")


# ---------------------------------------------------------------------------
# Step 4: Run DA3's export.py
# ---------------------------------------------------------------------------

def export_onnx():
    export_script = DA3_REPO_DIR / "export.py"
    if not export_script.exists():
        raise FileNotFoundError(
            f"export.py not found at {export_script}\n"
            "The DA3 repo structure may have changed — check the repo."
        )

    DA3_ONNX_DIR.mkdir(parents=True, exist_ok=True)

    print(f"\nExporting {MODEL_VARIANT} → ONNX  ({TARGET_H}×{TARGET_W}) …")
    print("Note: this downloads ~1–2 GB of model weights on first run.\n")

    run(
        [
            sys.executable, str(export_script),
            "--model-dir", MODEL_VARIANT,
            "--height",    str(TARGET_H),
            "--width",     str(TARGET_W),
            "--output-dir", str(DA3_ONNX_DIR),
        ],
        cwd=str(DA3_REPO_DIR),
    )
    print(f"✓ ONNX export complete")


# ---------------------------------------------------------------------------
# Step 5: Copy ONNX to assets
# ---------------------------------------------------------------------------

def copy_onnx() -> float:
    onnx_files = sorted(DA3_ONNX_DIR.glob("*.onnx"))
    if not onnx_files:
        raise FileNotFoundError(
            f"No .onnx files found in {DA3_ONNX_DIR} after export."
        )

    src = onnx_files[0]
    size_mb = src.stat().st_size / 1024 / 1024
    print(f"Found: {src.name}  ({size_mb:.1f} MB)")

    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy(src, ONNX_PATH)
    print(f"✓ Copied → {ONNX_PATH}  ({size_mb:.1f} MB)")

    if size_mb > 300:
        print(
            f"\n⚠  WARNING: model is {size_mb:.0f} MB.  The APK will be very large.\n"
            "   Consider downloading the model at runtime and removing it from\n"
            "   assets/ to keep the APK size manageable."
        )
    return size_mb


# ---------------------------------------------------------------------------
# Step 6: Validate the exported model with onnxruntime
# ---------------------------------------------------------------------------

def test_onnx() -> str:
    """Run a dummy forward pass and return the detected input tensor name."""
    try:
        import numpy as np
        import onnxruntime as rt
    except ImportError:
        print("⚠  onnxruntime not installed — skipping validation test")
        return "image"

    print("\nValidating ONNX model …")
    sess = rt.InferenceSession(str(ONNX_PATH), providers=["CPUExecutionProvider"])

    for inp in sess.get_inputs():
        print(f"  Input : name='{inp.name}', shape={inp.shape}, dtype={inp.type}")
    for out in sess.get_outputs():
        print(f"  Output: name='{out.name}', shape={out.shape}, dtype={out.type}")

    input_name = sess.get_inputs()[0].name

    # Dummy input — random image, ImageNet-normalised
    dummy = np.random.rand(1, 3, TARGET_H, TARGET_W).astype(np.float32)
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)[:, None, None]
    std  = np.array([0.229, 0.224, 0.225], dtype=np.float32)[:, None, None]
    dummy = (dummy - mean) / std

    outputs = sess.run(None, {input_name: dummy})
    depth = outputs[0]   # shape [1, 1, H, W], metres

    print(f"✓ Test inference OK")
    print(f"  depth output shape : {depth.shape}")
    print(f"  depth range (m)    : {depth.min():.3f} – {depth.max():.3f}")
    print(f"  depth mean  (m)    : {depth.mean():.3f}")
    return input_name


# ---------------------------------------------------------------------------
# Step 7: Write calibration.json
# ---------------------------------------------------------------------------

def write_calibration(input_name: str, size_mb: float):
    data = {
        "version": "2.0",
        "model_name": f"Depth Anything V3 {MODEL_VARIANT}",
        "export_date": datetime.now().isoformat(),
        "model_input_h": TARGET_H,
        "model_input_w": TARGET_W,
        "model_input_name": input_name,
        "output_type": "metric_meters",
        "model_size_mb": round(size_mb, 1),
        "calibration": {
            # Identity calibration: (raw / 1.0) * 1.0 = raw metres
            "default_value": 1.0,
            "default_distance_meters": 1.0,
            "description": (
                "DA3METRIC-LARGE outputs metric depth in real-world metres directly. "
                "Default calibration is identity (factor 1.0). "
                "Users may still apply a per-camera correction via the in-app calibration."
            ),
        },
        "preprocessing": {
            "normalize_mean": [0.485, 0.456, 0.406],
            "normalize_std":  [0.229, 0.224, 0.225],
            "note": "Divide pixel values by 255, then subtract mean and divide by std.",
        },
    }
    CALIB_PATH.write_text(json.dumps(data, indent=2))
    print(f"✓ Calibration file written: {CALIB_PATH}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("=== Depth Anything V3 — ONNX Export ===\n")
    check_cuda()

    clone_da3_repo()
    patch_bfloat16()
    install_requirements()
    export_onnx()
    size_mb = copy_onnx()
    input_name = test_onnx()
    write_calibration(input_name, size_mb)

    print(f"\n=== Done ===")
    print(f"  Model      : {ONNX_PATH}")
    print(f"  Calibration: {CALIB_PATH}")
    print(f"\nThe model outputs depth in METRES — no calibration required for scale.")
    print(f"Input tensor : '{input_name}'  shape [1, 3, {TARGET_H}, {TARGET_W}]")
    print(f"Output tensor: 'depth'          shape [1, 1, {TARGET_H}, {TARGET_W}]")
