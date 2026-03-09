#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

echo "=== Depth App APK Builder ==="
echo "Project root: $PROJECT_ROOT"

BUILD_MODE="${1:-release}"
ANDROID_ARCH="${2:-arm64-v8a}"

if [ "$BUILD_MODE" != "debug" ] && [ "$BUILD_MODE" != "release" ]; then
    echo "Invalid build mode: $BUILD_MODE (use 'debug' or 'release')"
    exit 1
fi

echo "Build mode: $BUILD_MODE"
echo "Android architecture: $ANDROID_ARCH"

cd "$PROJECT_ROOT"

echo ""
echo "=== Step 1: Ensure model is exported ==="
if [ ! -f "assets/models/depth_model.onnx" ]; then
    echo "Model not found. Exporting..."
    python3 export_model.py
else
    echo "Model already exists at assets/models/depth_model.onnx"
fi

echo ""
echo "=== Step 2: Get Flutter dependencies ==="
flutter pub get

echo ""
echo "=== Step 3: Building APK ==="
flutter build apk \
    --"$BUILD_MODE" \
    --target-platform android-arm64 \
    --build-number "$(date +%s)" \
    --split-per-abi

APK_PATH=$(find build/app/outputs/flutter-apk -name "*.apk" -type f | head -1)

if [ -z "$APK_PATH" ]; then
    echo "Error: APK not found after build"
    exit 1
fi

echo ""
echo "=== Build successful! ==="
echo "APK location: $APK_PATH"
echo "APK size: $(du -h "$APK_PATH" | cut -f1)"

if command -v adb &> /dev/null; then
    read -p "Do you want to install the APK to connected device? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Installing APK..."
        adb install -r "$APK_PATH"
        echo "Installation complete!"
    fi
fi
