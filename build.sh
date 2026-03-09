#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

echo "=== Depth App Build System ==="
echo "Project root: $PROJECT_ROOT"

TARGET="${1:-apk-release}"
EXPORT_MODEL="${2:-auto}"

setup_python_env() {
    echo "=== Setting up Python environment ==="
    
    if ! command -v uv &> /dev/null; then
        echo "uv not found. Installing..."
        pip install uv
    fi
    
    echo "Using Python 3.10..."
    uv python install 3.10
    
    echo "Installing dependencies..."
    uv pip install -r requirements.txt
}

export_model() {
    if [ "$EXPORT_MODEL" = "auto" ] || [ "$EXPORT_MODEL" = "true" ]; then
        if [ ! -f "assets/models/depth_model.onnx" ]; then
            echo "=== Exporting Depth Model ==="
            uv run python export_model.py
        fi
    fi
}

setup_flutter() {
    echo "=== Setting up Flutter ==="
    flutter clean
    flutter pub get
}

build_apk() {
    local mode="${1:-release}"
    echo "=== Building APK ($mode) ==="
    
    flutter build apk \
        --"$mode" \
        --target-platform android-arm64 \
        --split-per-abi \
        --build-number "$(date +%s)"
    
    local apk_path=$(find "$PROJECT_ROOT/build/app/outputs/flutter-apk" -name "*.apk" -type f | head -1)
    if [ -z "$apk_path" ]; then
        echo "Error: APK build failed"
        return 1
    fi
    
    echo "APK created: $apk_path"
    echo "Size: $(du -h "$apk_path" | cut -f1)"
    
    return 0
}

build_aab() {
    echo "=== Building Android App Bundle ==="
    
    flutter build appbundle \
        --release \
        --target-platform android-arm64,android-arm,android-x86_64 \
        --build-number "$(date +%s)"
    
    local aab_path=$(find "$PROJECT_ROOT/build/app/outputs/bundle" -name "*.aab" -type f | head -1)
    if [ -z "$aab_path" ]; then
        echo "Error: AAB build failed"
        return 1
    fi
    
    echo "AAB created: $aab_path"
    echo "Size: $(du -h "$aab_path" | cut -f1)"
    
    return 0
}

build_ios() {
    echo "=== Building iOS App ==="
    
    flutter build ios \
        --release \
        --build-number "$(date +%s)"
    
    echo "iOS build complete. Output in: build/ios/iphoneos/Runner.app"
}

build_linux() {
    echo "=== Building Linux App ==="
    
    flutter build linux \
        --release
    
    echo "Linux build complete. Output in: build/linux/x64/release/bundle/"
}

build_windows() {
    echo "=== Building Windows App ==="
    
    flutter build windows \
        --release
    
    echo "Windows build complete. Output in: build/windows/x64/runner/Release/"
}

build_macos() {
    echo "=== Building macOS App ==="
    
    flutter build macos \
        --release
    
    echo "macOS build complete. Output in: build/macos/Build/Products/Release/"
}

install_apk() {
    if ! command -v adb &> /dev/null; then
        echo "Error: adb not found. Please install Android SDK tools."
        return 1
    fi
    
    local apk_path=$(find "$PROJECT_ROOT/build/app/outputs/flutter-apk" -name "*.apk" -type f | head -1)
    if [ -z "$apk_path" ]; then
        echo "Error: No APK found"
        return 1
    fi
    
    echo "=== Installing APK to device ==="
    adb install -r "$apk_path"
    
    echo "Installation complete!"
}

show_help() {
    cat << EOF
Depth App Build System

Usage: ./build.sh [target] [export-model]

Targets:
  apk-debug       Build debug APK
  apk-release     Build release APK (default)
  apk             Alias for apk-release
  aab             Build Android App Bundle (Play Store)
  ios             Build iOS app  
  linux           Build Linux app
  windows         Build Windows app
  macos           Build macOS app
  install         Install APK to connected device
  clean           Clean build artifacts
  help            Show this message

Options:
  export-model    Export model before building (auto/true/false, default: auto)

Examples:
  ./build.sh apk-release
  ./build.sh apk-debug true
  ./build.sh ios false
  ./build.sh install

EOF
}

case "$TARGET" in
    apk-debug)
        setup_flutter
        export_model
        build_apk debug
        ;;
    apk-release|apk)
        setup_flutter
        export_model
        build_apk release
        ;;
    aab)
        setup_flutter
        export_model
        build_aab
        ;;
    ios)
        setup_flutter
        export_model
        build_ios
        ;;
    linux)
        setup_flutter
        export_model
        build_linux
        ;;
    windows)
        setup_flutter
        export_model
        build_windows
        ;;
    macos)
        setup_flutter
        export_model
        build_macos
        ;;
    install)
        install_apk
        ;;
    clean)
        echo "Cleaning build artifacts..."
        flutter clean
        rm -rf build/
        echo "Clean complete!"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown target: $TARGET"
        echo "Use './build.sh help' for usage information"
        exit 1
        ;;
esac

echo ""
echo "=== Build script completed ==="
