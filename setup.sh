#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

echo "=== Depth App Setup Script ==="
echo "Project: $PROJECT_ROOT"

SKIP_PYTHON="${1:-false}"

setup_python() {
    echo ""
    echo "=== Setting up Python 3.10 environment ==="
    
    if command -v uv &> /dev/null; then
        echo "uv found"
    else
        echo "Installing uv..."
        pip3 install --user uv
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    if ! command -v python3.10 &> /dev/null; then
        echo "Python 3.10 not found. Attempting to install..."
        uv python install 3.10
    fi
    
    echo "Installing Python dependencies..."
    uv pip install -r "$PROJECT_ROOT/requirements.txt"
    
    echo "Python environment ready!"
}

setup_flutter() {
    echo ""
    echo "=== Setting up Flutter ==="
    
    if ! command -v flutter &> /dev/null; then
        echo "Error: Flutter not found in PATH"
        echo "Please install Flutter from https://flutter.dev/get-started"
        exit 1
    fi
    
    FLUTTER_VERSION=$(flutter --version | grep "Flutter" | awk '{print $2}')
    echo "Flutter version: $FLUTTER_VERSION"
    
    flutter pub get
    
    echo "Flutter setup complete!"
}

check_dependencies() {
    echo ""
    echo "=== Checking dependencies ==="
    
    local missing=0
    
    if ! command -v flutter &> /dev/null; then
        echo "✗ Flutter not found"
        missing=$((missing + 1))
    else
        echo "✓ Flutter installed"
    fi
    
    if ! command -v python3.10 &> /dev/null && ! command -v python3 &> /dev/null; then
        echo "✗ Python 3 not found"
        missing=$((missing + 1))
    else
        echo "✓ Python installed"
    fi
    
    if ! command -v adb &> /dev/null; then
        echo "⚠ adb not found (Android development tools)"
    else
        echo "✓ adb installed"
    fi
    
    if ! command -v git &> /dev/null; then
        echo "✗ Git not found"
        missing=$((missing + 1))
    else
        echo "✓ Git installed"
    fi
    
    if [ $missing -gt 0 ]; then
        echo ""
        echo "Warning: Some dependencies are missing!"
        return 1
    else
        echo ""
        echo "All dependencies satisfied!"
        return 0
    fi
}

export_model() {
    if [ "$SKIP_PYTHON" != "true" ]; then
        if [ ! -f "$PROJECT_ROOT/assets/models/depth_model.onnx" ]; then
            echo ""
            echo "=== Exporting Depth Model ==="
            python3.10 "$PROJECT_ROOT/export_model.py"
        else
            echo ""
            echo "Model already exported at $PROJECT_ROOT/assets/models/depth_model.onnx"
        fi
    else
        echo ""
        echo "Skipping model export (use --skip-python false to export)"
    fi
}

show_next_steps() {
    echo ""
    echo "=== Setup Complete! ==="
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. For Desktop (Linux/Mac/Windows):"
    echo "   Terminal 1: source .venv/bin/activate && python depth_server.py"
    echo "   Terminal 2: flutter run -d linux"
    echo ""
    echo "2. For Android development:"
    echo "   flutter run -d <device_id>"
    echo "   ./build_apk.sh"
    echo ""
    echo "3. For iOS development:"
    echo "   flutter run ios"
    echo ""
    echo "For more info, see README_SETUP.md"
}

main() {
    check_dependencies || true
    
    setup_flutter
    
    if [ "$SKIP_PYTHON" != "true" ]; then
        setup_python
        export_model
    else
        echo ""
        echo "Python setup skipped (--skip-python flag used)"
    fi
    
    show_next_steps
}

main
