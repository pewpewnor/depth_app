#!/bin/bash
set -e

TARGET="${1:-android}"
FLAVOR="${2:-debug}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Depth App Runner ==="
echo "Target: $TARGET"
echo "Flavor: $FLAVOR"

case "$TARGET" in
    android|a)
        echo "Building and running on Android..."
        cd "$PROJECT_ROOT"
        flutter run --"$FLAVOR" -t lib/main.dart --verbose
        ;;
    ios|i)
        echo "Building and running on iOS..."
        cd "$PROJECT_ROOT"
        flutter run --"$FLAVOR" -t lib/main.dart --verbose
        ;;
    linux|l)
        echo "Building and running on Linux..."
        cd "$PROJECT_ROOT"
        flutter run --"$FLAVOR" -t lib/main.dart
        ;;
    macos|m)
        echo "Building and running on macOS..."
        cd "$PROJECT_ROOT"
        flutter run --"$FLAVOR" -t lib/main.dart
        ;;
    windows|w)
        echo "Building and running on Windows..."
        cd "$PROJECT_ROOT"
        flutter run --"$FLAVOR" -t lib/main.dart
        ;;
    *)
        echo "Usage: ./run.sh [target] [flavor]"
        echo ""
        echo "Targets:"
        echo "  android, a    Android"
        echo "  ios, i        iOS"
        echo "  linux, l      Linux"
        echo "  macos, m      macOS"
        echo "  windows, w    Windows"
        echo ""
        echo "Flavors:"
        echo "  debug         Debug build (default)"
        echo "  release       Release build"
        echo "  profile       Profile build (performance analysis)"
        echo ""
        echo "Examples:"
        echo "  ./run.sh android debug"
        echo "  ./run.sh ios release"
        echo "  ./run.sh linux"
        exit 1
        ;;
esac
