# Architecture & Implementation Guide

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter UI Layer                          │
│  (main.dart - Camera Preview, Bounding Box, Depth Display)  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
            ┌────────────────────────────┐
            │  Method Channel Handler    │
            │ (com.depth.app/depth)      │
            └────────────┬───────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
    ┌────────────┐  ┌────────────┐  ┌────────────┐
    │  Android   │  │    iOS     │  │ Desktop    │
    │  (Kotlin)  │  │  (Swift)   │  │ (C++/FFI)  │
    └────┬───────┘  └────┬───────┘  └────┬───────┘
         │               │               │
         ▼               ▼               ▼
    ┌────────────┐  ┌────────────┐  ┌────────────┐
    │ONNX RT     │  │Vision API  │  │ONNX RT     │
    │+ GPU       │  │(CoreML)    │  │+ CUDA GPU  │
    └────────────┘  └────────────┘  └────────────┘
```

## Component Details

### 1. Flutter Frontend (lib/)

**main.dart - Main Application**
- Initializes camera with `camera` package
- Manages app lifecycle and UI rendering
- Displays real-time camera feed with overlay
- Shows depth value and status messages
- Handles frame extraction and processing

**depth_estimator.dart - Platform Bridge**
- Abstraction layer for native depth estimation
- Implements depth calibration: `depth_m = (raw / 147) * 6`
- Manages model file extraction from assets
- Error handling and device initialization
- Provides single interface for all platforms

### 2. Android Implementation (android/)

**MainActivity.kt**
- Extends FlutterActivity with MethodChannel handler
- Routes "com.depth.app/depth" method calls to Kotlin
- Methods:
  - `initializeModel(modelPath)` - Loads ONNX model
  - `estimateDepth(imageBytes)` - Runs inference
  - `cleanupModel()` - Releases resources

**Inference Pipeline**
```
Raw JPEG Bytes
    ↓
BitmapFactory.decodeByteArray()
    ↓
Resize to 518x518
    ↓
Extract RGB pixels
    ↓
ImageNet normalization
    ↓
Create float array (1, 3, 518, 518)
    ↓
OnnxTensor creation
    ↓
OrtSession.run()
    ↓
Extract max depth value
    ↓
Return to Flutter (via MethodChannel)
```

**Dependencies**
- ONNX Runtime for Android: `com.microsoft.onnxruntime:onnxruntime-android:1.17.1`
- Runs on GPU if available, CPU fallback

### 3. iOS Implementation (ios/)

**AppDelegate.swift**
- Sets up MethodChannel in `application(_:didFinishLaunchingWithOptions:)`
- Uses Vision framework for depth estimation
- Implements:
  - `initializeModel()` - No-op (iOS has built-in depth)
  - `estimateDepth(imageBytes)` - Uses VNEstimateDepthRequest
  - `cleanupModel()` - No-op

**iOS Depth Estimation**
- Uses Apple's Vision framework (Vision API)
- Leverages LiDAR if available (newer iPhones/iPads)
- Falls back to stereo depth computation
- Automatic GPU acceleration through Metal

### 4. macOS Implementation (macos/)

**AppDelegate.swift**
- Similar to iOS implementation
- Uses Vision framework on macOS 11+
- Supports discrete and integrated GPUs
- Placeholder implementation for desktop inference

### 5. Linux/Windows Implementation (linux/, windows/)

**Desktop Implementation**
- Uses C++ with ONNX Runtime through FFI
- Direct CUDA 13.0 support on Linux
- Optional: PyTorch C++ backend via subprocess
- Configurable GPU device selection

## Data Flow

### Camera Frame Processing

```
CameraImage (YUV420 format)
    ↓
Extract center 224x224 region
    ↓
Convert YUV to RGB
    ↓
Encode as JPEG
    ↓
Pass to native code via MethodChannel
    ↓
[Native code runs depth estimation]
    ↓
Return depth value (0-255 raw)
    ↓
Calibrate: depth_m = (raw / 147) * 6
    ↓
Update UI with depth value
```

### Model Inference

```
Input Image (224×224 RGB)
    ↓
Normalize: (pixel - mean) / std
    ↓
Reshape: (1, 3, 224, 224) batch
    ↓
ONNX Model: Depth-Anything-V2-Small
    ↓
Output: Depth map (1, 1, 518, 518)
    ↓
Extract center pixel depth
    ↓
Scale to 0-255 range
```

## File Locations

| Platform | Key Files |
|----------|-----------|
| **Android** | `android/app/src/main/kotlin/com/example/depth_app/MainActivity.kt` |
| | `android/app/build.gradle.kts` |
| | `android/app/src/main/AndroidManifest.xml` |
| **iOS** | `ios/Runner/AppDelegate.swift` |
| | `ios/Runner/Info.plist` |
| **macOS** | `macos/Runner/AppDelegate.swift` |
| **Linux** | `linux/runner/my_application.cc` (future) |
| **Windows** | `windows/runner/main.cpp` (future) |
| **Python** | `export_model.py` |
| | `requirements.txt` |
| | `pyproject.toml` |
| **Build** | `build.sh` (all platforms) |
| | `Dockerfile` (Docker) |
| | `docker-compose.yml` (Docker Compose) |

## Model Specifications

**Name**: Depth-Anything-V2-Small  
**Source**: huggingface.co/LiheYoung/depth-anything-small-hf  
**Format**: ONNX (exported via transformers.onnx)  
**Input**: RGB image, 518×518 pixels  
**Output**: Depth map, 518×518 values (0-255)  
**Size**: ~20-30 MB (depending on quantization)  
**Inference Time**: 
- Desktop (GPU): ~50-100ms
- Mobile (GPU): ~200-500ms
- CPU: ~2-5 seconds

## Depth Calibration

The calibration maps raw model output to real-world distances:

```
Raw Value → Calibrated Distance

Known Reference: 147 (raw) = 6 (meters)

Formula: distance_m = (raw_value / 147) × 6

To recalibrate:
1. Measure an object at exact distance (e.g., 3 meters)
2. Point camera at object, read raw value from logs
3. Update in lib/depth_estimator.dart:
   const double calibrationValue = <new_raw_value>;
   const double calibrationDistance = <new_distance>;
```

## Performance Optimization Tips

1. **GPU Selection**
   - Android: GPU acceleration automatic
   - iOS: LiDAR if available
   - Desktop: CUDA 13.0 for best performance

2. **Batch Processing**
   - Current: Single frame processing
   - Could optimize: Process every Nth frame

3. **Model Quantization**
   - Current: Full precision ONNX
   - Could optimize: INT8 or FP16 quantization

4. **Resolution Scaling**
   - Current: 224×224 center crop
   - Could optimize: Dynamic resolution based on device

## Debugging

### Android Debug Build
```bash
./build.sh apk-debug true
adb shell setprop debug.atrace.tags.enableflags 1
adb logcat | grep "depth"
```

### iOS Debug Build
```bash
./run.sh ios debug
# View Xcode console for logs
```

### Log Depth Values
```dart
// In lib/depth_estimator.dart or lib/main.dart
print('Raw depth: $rawDepth');
print('Calibrated depth: $_depthMeters m');
```

## Platform-Specific Considerations

### Android
- Camera permission required at runtime
- ONNX Runtime handles GPU/CPU automatically
- Large models require sufficient heap size
- APK size ~100-150MB with model

### iOS
- Camera permission via Info.plist
- Vision framework automatic optimization
- LiDAR support for newer devices
- Lightning sensor interference consideration

### macOS
- No special permissions needed
- Full desktop hardware access
- Can use discrete GPU
- Largest APK due to full toolchain

## Future Enhancements

1. **Multi-model Support**
   - Add model selection in UI
   - Load different model sizes dynamically

2. **Export Options**
   - Save depth maps as images
   - Export calibration data
   - Share measurements

3. **Advanced Features**
   - Depth-based object detection
   - Measurement tools
   - 3D point cloud generation
   - Recording depth video

4. **Performance**
   - Model quantization
   - Batch processing
   - Caching optimizations

## References

- Flutter Platform Channels: flutter.dev/platform-channels
- ONNX Runtime: onnxruntime.ai
- Depth-Anything-V2: github.com/LiheYoung/Depth-Anything-V2
- Model Card: huggingface.co/LiheYoung/depth-anything-small-hf
