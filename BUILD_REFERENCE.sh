#!/bin/bash

# Quick Build Commands for Depth App

echo "=========================================="
echo "  Depth App - Quick Build Reference"
echo "=========================================="
echo ""

# Check for device
echo "Available devices:"
flutter devices

echo ""
echo "=========================================="
echo "  BUILD COMMANDS"
echo "=========================================="
echo ""

echo "Android:"
echo "  Debug:   flutter run -d emulator-5554"
echo "  Release: flutter build apk --release"
echo "  APK:     ./build.sh apk-release"
echo ""

echo "iOS:"
echo "  flutter run -d ios"
echo "  flutter build ios --release"
echo ""

echo "Linux:"
echo "  Debug:   flutter run -d linux"
echo "  Release: flutter build linux --release"
echo ""

echo "Windows:"
echo "  Debug:   flutter run -d windows"
echo "  Release: flutter build windows --release"
echo ""

echo "=========================================="
echo "  FIX CAMERA ISSUES"
echo "=========================================="
echo ""

echo "If you see 'MissingPluginException':"
echo "  Step 1: ./fix_camera_plugin.sh"
echo "  Step 2: flutter run"
echo ""

echo "Or manually:"
echo "  flutter clean"
echo "  flutter pub get"
echo "  flutter run"
echo ""

echo "=========================================="
