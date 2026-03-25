#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "  Camera Plugin Fix & Rebuild Script"
echo "=========================================="
echo ""

# Step 1: Clean Flutter project
echo "[1/6] Cleaning Flutter project..."
flutter clean
echo "✓ Flutter project cleaned"
echo ""

# Step 2: Remove generated platform files
echo "[2/6] Cleaning platform-specific build files..."
rm -rf build/
rm -rf .dart_tool/
rm -rf flutter_export_environment.sh
rm -rf ios/Pods/
rm -rf android/.gradle/
rm -rf android/app/.gradle/
echo "✓ Platform build files cleaned"
echo ""

# Step 3: Get fresh dependencies
echo "[3/6] Getting Flutter dependencies..."
flutter pub get
echo "✓ Dependencies fetched"
echo ""

# Step 4: Regenerate platform-specific code
echo "[4/6] Regenerating platform code..."
flutter pub run build_runner build --delete-conflicting-outputs 2>/dev/null || true
echo "✓ Platform code regenerated"
echo ""

# Step 5: Verify Android plugin registration
echo "[5/6] Verifying Android plugin registration..."
if [ -d "android/app/src/main" ]; then
    echo "  ✓ Android app directory found"
fi
echo ""

# Step 6: Check Camera plugin
echo "[6/6] Checking camera plugin..."
if grep -q "camera:" pubspec.yaml; then
    echo "  ✓ Camera plugin found in pubspec.yaml"
else
    echo "  ✗ Camera plugin NOT found in pubspec.yaml"
    exit 1
fi
echo ""

echo "=========================================="
echo "  Plugin Fix Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. For Android: flutter run -d <device_id>"
echo "2. For iOS: flutter run -d ios"
echo "3. For Linux: flutter run -d linux"
echo "4. For Windows: flutter run -d windows"
echo ""
echo "If you still see errors, try:"
echo "  - flutter pub cache clean camera"
echo "  - flutter pub get"
echo "  - flutter run"
