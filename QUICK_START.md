# Quick Start Guide

## 5-Minute Setup

### Prerequisites
- Flutter SDK 3.11.1+
- Python 3.10
- Android SDK (for APK building)

### Step 1: Clone & Setup (1 min)
```bash
cd /home/braum/Burn/Git/depth_app
chmod +x *.sh
./setup.sh
```

### Step 2: Export Model (2 min)
```bash
python3.10 export_model.py
```

### Step 3: Build & Run

#### Option A: Android (Quick)
```bash
./run.sh android debug
```

#### Option B: Android APK (Release)
```bash
./build.sh apk-release
```

#### Option C: Docker
```bash
docker-compose build
docker cp $(docker ps -q -f "ancestor=depth-app"):/output/depth_app.apk ./
```

#### Option D: Other Platforms
```bash
./run.sh ios debug
./run.sh linux debug
./run.sh macos debug
./run.sh windows debug
```

## Build Output Locations

| Target | Path |
|--------|------|
| Android APK (Debug) | `build/app/outputs/flutter-apk/` |
| Android APK (Release) | `build/app/outputs/flutter-apk/` |
| AAB (Play Store) | `build/app/outputs/bundle/` |
| iOS | `build/ios/iphoneos/Runner.app` |
| macOS | `build/macos/Build/Products/Release/` |
| Linux | `build/linux/x64/release/bundle/` |
| Windows | `build/windows/x64/runner/Release/` |

## Docker Build

```bash
# Build image
docker build -t depth-app .

# Run and export APK
docker run -v $(pwd)/output:/output depth-app

# Or use docker-compose
docker-compose up -d
docker exec depth_app_builder cat /output/depth_app.apk > ./depth_app.apk
```

## Troubleshooting

### "Model not found" error
```bash
python3.10 export_model.py --verbose
```

### Build cache issues
```bash
./build.sh clean
./build.sh apk-release
```

### Python 3.10 not found
```bash
uv python install 3.10
uv run python export_model.py
```

### CUDA not detected
- The app will fall back to CPU if CUDA is unavailable
- For desktop, install CUDA 13.0 for better performance
- Mobile devices will auto-use GPU acceleration

## Key Features Ready

✓ Real-time camera feed  
✓ Depth estimation (ONNX model)  
✓ Bounding box overlay  
✓ Depth calibration (147 = 6m)  
✓ Cross-platform support (Android, iOS, macOS, Linux, Windows)  
✓ Docker support  
✓ GPU acceleration (CUDA)  

## Next Steps

1. **Run on device**: `./run.sh android debug`
2. **View logs**: Check the app console for depth values
3. **Calibrate depth**: Point at known distances, adjust calibration in `lib/depth_estimator.dart`
4. **Customize UI**: Edit `lib/main.dart`
5. **Add features**: See README_SETUP.md for architecture details

## Directory Structure

```
depth_app/
├── lib/main.dart                 # Main Flutter app
├── android/app/src/.../          # Android native code (Kotlin)
├── ios/Runner/AppDelegate.swift  # iOS native code (Swift)
├── assets/models/                # Model files (auto-generated)
├── export_model.py              # Model downloader/exporter
├── setup.sh                     # Initial setup script
├── build.sh                     # Multi-platform builder
├── run.sh                       # App runner
└── Dockerfile                   # Docker configuration
```

## Performance Tips

- **Desktop**: Uses CUDA if available (fastest)
- **Mobile**: Uses GPU acceleration (fast)
- **CPU Fallback**: Slower but works on all devices
- **Camera Resolution**: Optimized at 224x224 center crop

## Support

- See README_SETUP.md for detailed documentation
- Check individual platform docs: flutter.dev/platform-channels
- Model: github.com/LiheYoung/Depth-Anything-V2
