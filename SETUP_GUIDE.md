# Depth Estimator App Setup Guide

## Prerequisites

- Flutter 3.11+
- Python 3.10+
- uv (Python package manager)
- CUDA 13.0 (optional, for GPU acceleration)
- Android SDK (for Android development)
- Xcode (for iOS development)

## Initial Setup

### 1. Install Python Dependencies

```bash
chmod +x setup.sh
./setup.sh
```

This will:
- Set up a Python 3.10 virtual environment using uv
- Install all Python dependencies from requirements.txt
- Export the Depth-Anything-V2-Small model to ONNX format (downloads ~350MB)

The exported model will be saved to `assets/models/depth_model.onnx`.

### 2. Flutter Dependencies

```bash
flutter pub get
```

## Running the App

### Desktop (Linux/Mac/Windows)

The app requires a Python inference server on desktop:

**Terminal 1** - Start the inference server:
```bash
source .venv/bin/activate
python depth_server.py
```

**Terminal 2** - Run the Flutter app:
```bash
./run.sh linux
```

Or manually:
```bash
flutter run -d linux
```

### Android

1. Connect an Android device or start an emulator
2. Run:
```bash
./run.sh android
```

Or build APK:
```bash
./build_apk.sh
```

### iOS

1. Connect an iPhone or start a simulator
2. Run:
```bash
flutter run -d ios
```

## Architecture

- **Desktop (Linux/Mac/Windows)**: Uses Python Flask server with PyTorch inference
- **Android**: Uses native Kotlin with ONNX Runtime
- **iOS**: Uses native Swift with ONNX Runtime

## How It Works

1. **Model Export**: `export_model.py` downloads Depth-Anything-V2-Small from HuggingFace and exports to ONNX
2. **Camera Input**: Real-time camera feed with 224x224 center bounding box
3. **Depth Estimation**: Process frame through model in center bbox region
4. **Calibration**: Raw depth output (0-255) converted to meters (calibration: 147=6m)
5. **Display**: Shows real-time depth value, camera preview, and bbox

## Configuration

### Depth Calibration

Edit the calibration values in:
- `lib/depth_estimator.dart` (main calibration)
- `depth_server.py` (Python server calibration)

Change:
```python
CALIBRATION_VALUE = 147.0  # Raw model output at reference distance
CALIBRATION_DISTANCE = 6.0  # Reference distance in meters
```

### Server Port

Edit `depth_server.py` and `lib/depth_estimator.dart`:
```python
app.run(host='127.0.0.1', port=5000)
```

## Troubleshooting

### App shows "Running in demo mode"
- Python server not running
- Run server in separate terminal: `python depth_server.py`
- Check server is accessible: `curl http://127.0.0.1:5000/health`

### Camera not available (desktop)
- Camera is only supported on mobile (Android/iOS)
- Desktop will show demo mode with mock depth values

### ONNX export fails
- Ensure CUDA drivers are installed (if using GPU)
- Run with verbose mode: `python export_model.py`

### Model not found for Android
- Ensure `assets/models/depth_model.onnx` exists
- Run `./setup.sh` again

## Building for Production

### Android Release APK

```bash
./build_apk.sh release
```

### iOS Release

```bash
flutter build ios --release
```

## Performance Notes

- GPU acceleration: Enabled on desktop (CUDA) and Android (GPU delegates)
- Model: Depth-Anything-V2-Small (~25M parameters)
- Input resolution: 518x518 (internally resized)
- Bbox processing: 224x224 center region
- Model inference: ~100-500ms depending on device

## File Structure

```
depth_app/
├── lib/
│   ├── main.dart           # Flutter app UI
│   └── depth_estimator.dart # Depth estimation logic
├── android/
│   └── app/src/main/kotlin/com/example/depth_app/
│       └── MainActivity.kt  # Android native code (ONNX Runtime)
├── ios/
│   └── Runner/             # iOS native code
├── depth_server.py         # Python Flask server for desktop
├── export_model.py         # Model export script
├── setup.sh                # Initial setup script
├── run.sh                  # Run script for different platforms
└── build_apk.sh           # APK build script
```
