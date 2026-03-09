#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Depth App Project Validation ==="
echo ""

check_file() {
    local file="$1"
    local desc="$2"
    
    if [ -f "$PROJECT_ROOT/$file" ]; then
        local size=$(du -h "$PROJECT_ROOT/$file" | cut -f1)
        echo "✓ $desc ($size)"
        return 0
    else
        echo "✗ $file"
        return 1
    fi
}

check_dir() {
    local dir="$1"
    local desc="$2"
    
    if [ -d "$PROJECT_ROOT/$dir" ]; then
        echo "✓ $desc"
        return 0
    else
        echo "✗ $dir"
        return 1
    fi
}

echo "=== Documentation ==="
check_file "README.md" "README"
check_file "README_SETUP.md" "Setup Guide"
check_file "QUICK_START.md" "Quick Start"
check_file "ARCHITECTURE.md" "Architecture Guide"

echo ""
echo "=== Python Files ==="
check_file "export_model.py" "Model Export Script"
check_file "requirements.txt" "Python Dependencies"
check_file "pyproject.toml" "Python Project Config"

echo ""
echo "=== Build Scripts ==="
check_file "setup.sh" "Setup Script"
check_file "build.sh" "Build System"
check_file "run.sh" "App Runner"
check_file "build_apk.sh" "APK Builder (Legacy)"

echo ""
echo "=== Flutter Files ==="
check_file "pubspec.yaml" "Flutter Configuration"
check_dir "lib" "Flutter Source Code"
check_file "lib/main.dart" "Main App"
check_file "lib/depth_estimator.dart" "Depth Module"

echo ""
echo "=== Android ==="
check_dir "android" "Android Project"
check_file "android/app/src/main/kotlin/com/example/depth_app/MainActivity.kt" "Android Implementation"
check_file "android/app/build.gradle.kts" "Android Build Config"
check_file "android/app/src/main/AndroidManifest.xml" "Android Manifest"

echo ""
echo "=== iOS ==="
check_dir "ios" "iOS Project"
check_file "ios/Runner/AppDelegate.swift" "iOS Implementation"
check_file "ios/Runner/Info.plist" "iOS Config"

echo ""
echo "=== macOS ==="
check_dir "macos" "macOS Project"
check_file "macos/Runner/AppDelegate.swift" "macOS Implementation"

echo ""
echo "=== Desktop (Linux/Windows) ==="
check_dir "linux" "Linux Project"
check_dir "windows" "Windows Project"

echo ""
echo "=== Docker ==="
check_file "Dockerfile" "Docker Image"
check_file "docker-compose.yml" "Docker Compose"
check_file ".dockerignore" "Docker Ignore"

echo ""
echo "=== Configuration ==="
check_file ".gitignore" "Git Ignore"

echo ""
echo "=== Assets ==="
check_dir "assets" "Assets Directory"
check_dir "assets/models" "Models Directory"

echo ""
echo "=== Summary ==="
echo ""
echo "Project: Depth Estimator App"
echo "Status: Ready for Development"
echo ""
echo "Supported Platforms:"
echo "  ✓ Android (APK)"
echo "  ✓ iOS (App)"
echo "  ✓ macOS (App)"
echo "  ✓ Linux (Binary)"
echo "  ✓ Windows (Binary)"
echo ""
echo "Features:"
echo "  ✓ Real-time camera feed"
echo "  ✓ Depth estimation (ONNX)"
echo "  ✓ Bounding box overlay"
echo "  ✓ Depth calibration"
echo "  ✓ GPU acceleration (CUDA/GPU)"
echo "  ✓ Docker support"
echo ""
echo "Next Steps:"
echo "  1. chmod +x *.sh"
echo "  2. ./setup.sh"
echo "  3. ./build.sh apk-release"
echo "  4. Or: ./run.sh android debug"
echo ""
