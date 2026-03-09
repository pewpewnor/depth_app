# Depth Estimator App

A real-time depth estimation Flutter application for mobile, tablet, and desktop platforms using the Depth-Anything-V2-Small model from Hugging Face.

## Features

- **Real-time Camera Feed**: Live camera stream on all platforms
- **Depth Estimation**: Shows depth in meters for the center bounding box
- **Cross-Platform**: Supports Android, iOS, macOS, Linux, and Windows
- **GPU Acceleration**: Uses CUDA 13.0 on desktop, GPU on mobile
- **Depth Calibration**: Configured to calibrate depth (147 = 6 meters)

## System Requirements

### Desktop (Linux/macOS)
- Flutter 3.11.1+
- Python 3.10
- CUDA 13.0 (for GPU support on Linux)
- Dart SDK 3.11.1+
- Android SDK (for APK building)
- Java 11+

### Mobile (Android/iOS)
- Android 9+ (API 28+)
- iOS 13+

## Installation

### 1. Install Dependencies

#### Linux/macOS:
```bash
# Install Flutter
flutter --version  # Should show 3.11.1 or higher

# Install Python 3.10
python3.10 --version

# Install uv for Python management
pip install uv

# Set up Python environment
uv python install 3.10
uv pip install -r requirements.txt
```

#### Android Setup:
```bash
flutter doctor -v
# Ensure Android SDK and NDK are installed
```

### 2. Export Depth Model

The model is automatically exported from Hugging Face. You can manually trigger export:

```bash
python3.10 export_model.py
```

This will download `LiheYoung/depth-anything-small-hf` and export it to:
- `assets/models/depth_model.onnx` (for Android/Desktop)

## Building

### Build APK (Android)

#### Using build script:
```bash
# Release build
./build.sh apk-release

# Debug build with model export
./build.sh apk-debug true

# Install to connected device
./build.sh install
```

#### Using Flutter directly:
```bash
flutter build apk --release --split-per-abi
```

#### Using Docker:
```bash
# Build with docker-compose
docker-compose build
docker-compose up -d

# Get APK from output
docker cp depth_app_builder:/output/depth_app.apk ./

# Or use Dockerfile directly
docker build -t depth-app .
docker run -v $(pwd)/build:/app/build -v $(pwd)/output:/output depth-app
```

### Build Android App Bundle (for Play Store):
```bash
./build.sh aab
```

### Build iOS:
```bash
./build.sh ios
flutter build ios --release
```

### Build macOS:
```bash
./build.sh macos
flutter build macos --release
```

### Build Linux:
```bash
./build.sh linux
flutter build linux --release
```

### Build Windows:
```bash
./build.sh windows
flutter build windows --release
```

## Project Structure

```
depth_app/
├── lib/
│   ├── main.dart              # Main Flutter app
│   ├── depth_estimator.dart   # Platform-agnostic depth estimation
│   └── ...
├── android/                   # Android native code (Kotlin)
├── ios/                       # iOS native code (Swift)
├── macos/                     # macOS native code (Swift)
├── linux/                     # Linux native code (C++)
├── windows/                   # Windows native code (C++)
├── assets/
│   └── models/                # Model files (ONNX)
├── export_model.py            # Model download and export script
├── requirements.txt           # Python dependencies
├── build.sh                   # Multi-platform build script
├── build_apk.sh               # Legacy APK build script
├── Dockerfile                 # Docker build configuration
├── docker-compose.yml         # Docker Compose configuration
└── pubspec.yaml              # Flutter dependencies
```

## Architecture

### Backend (Python)
- **Model**: Depth-Anything-V2-Small from Hugging Face
- **Format**: ONNX (Open Neural Network Exchange)
- **Inference**: ONNX Runtime with CUDA support
- **Calibration**: 147 (raw) = 6 meters

### Frontend (Flutter)
- **Camera**: `camera` package for real-time video stream
- **Platform Channels**: Native code bridges for depth computation
- **Rendering**: 224x224 center bounding box display

### Platform Implementations
- **Android**: Kotlin + ONNX Runtime
- **iOS**: Swift + CoreML Vision framework
- **macOS**: Swift + Vision framework
- **Linux**: C++ + ONNX Runtime
- **Windows**: C++ + ONNX Runtime

## Camera Permissions

### Android
- `android.permission.CAMERA`
- `android.permission.READ_EXTERNAL_STORAGE`
- `android.permission.WRITE_EXTERNAL_STORAGE`

### iOS
- Camera usage description in `Info.plist`
- Photo library access

## Depth Calibration

The app calibrates depth using:
```
depth_meters = (raw_depth_value / 147) * 6
```

To adjust calibration:
1. Measure an object at known distance
2. Note the raw depth value displayed
3. Update calibration in `lib/depth_estimator.dart`:
   ```dart
   const double calibrationValue = YOUR_RAW_VALUE;
   const double calibrationDistance = YOUR_DISTANCE_IN_METERS;
   ```

## Performance Notes

- **Desktop**: GPU inference via CUDA (significantly faster)
- **Mobile**: Uses on-device GPU acceleration
- **Camera Resolution**: 224x224 center bounding box
- **Input Resolution**: 518x518 for model
- **Output**: Depth in 0-255 range, converted to meters

## Troubleshooting

### APK Build Fails
```bash
# Clean and retry
./build.sh clean
./build.sh apk-release
```

### Model Export Error
```bash
# Check Python environment
python3.10 -c "import torch; print(torch.cuda.is_available())"

# Manually export
python3.10 export_model.py --verbose
```

### Camera Permissions (Android)
- Grant camera permission in app settings
- Ensure Android API 28+

### Docker Build Issues
```bash
# Use verbose logging
docker build --progress=plain -t depth-app .

# Check available disk space
docker system prune  # Clean unused images
```

## Dependencies

### Flutter
- `camera: ^0.10.5+5` - Real-time camera access
- `image: ^4.1.7` - Image processing
- `path_provider: ^2.1.2` - File system access
- `tflite_flutter: ^0.13.1` - Optional TensorFlow Lite support
- `ffi: ^2.1.1` - Native FFI bindings

### Python
- `torch==2.2.0` - PyTorch (with CUDA 11.8 support)
- `torchvision==0.17.0` - Computer vision utilities
- `transformers==4.36.2` - Hugging Face transformers
- `onnxruntime==1.17.1` - ONNX model inferencing
- `opencv-python==4.8.1.78` - Image processing

### Android
- `onnxruntime-android:1.17.1` - ONNX Runtime for Android

## License

This project uses:
- Depth-Anything-V2-Small (License: MIT)
- Flutter (License: BSD 3-Clause)
- PyTorch (License: BSD)
- ONNX Runtime (License: Apache 2.0)

## Contributing

1. Create a branch for your feature
2. Make changes with minimal comments
3. Test on target platforms
4. Submit PR with description

## Support

For issues or questions:
1. Check troubleshooting section
2. Review platform-specific documentation
3. Check model export logs
4. Verify system requirements
