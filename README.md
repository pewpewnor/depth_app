# Depth Estimator App

Real-time depth estimation using Depth-Anything-V2-Small model on mobile and desktop via Flutter.

## Features

- Real-time camera feed with depth estimation
- Works on Android, iOS, Linux, Mac, and Windows
- GPU acceleration (CUDA on desktop, GPU delegates on mobile)
- Live display of estimated depth from center bounding box
- ONNX model export and inference

## Quick Start

```bash
chmod +x setup.sh
./setup.sh
```

Then run the app:

**Desktop:**
```bash
source .venv/bin/activate && python depth_server.py &
./run.sh linux
```

**Android:**
```bash
./run.sh android
```

See [SETUP_GUIDE.md](SETUP_GUIDE.md) for detailed instructions.

## Requirements

- Flutter 3.11+
- Python 3.10+
- uv package manager
- CUDA 13.0 (optional, for desktop GPU acceleration)

## Architecture

- **Flutter UI**: Camera preview with real-time depth overlay
- **Desktop Backend**: Python Flask server with PyTorch inference
- **Mobile Backend**: Native Kotlin (Android) and Swift (iOS) with ONNX Runtime
- **Model**: Depth-Anything-V2-Small (HuggingFace)

## Depth Calibration

Default: 147 (model output) = 6 meters

Edit calibration in:
- `lib/depth_estimator.dart`
- `depth_server.py`

## Build APK

```bash
./build_apk.sh
```

For detailed setup and troubleshooting, see [SETUP_GUIDE.md](SETUP_GUIDE.md).
