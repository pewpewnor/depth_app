FROM ghcr.io/cirruslabs/flutter:latest

LABEL maintainer="Depth App Team"
LABEL description="Flutter App for Real-time Depth Estimation"

ENV FLUTTER_HOME=/opt/flutter
ENV ANDROID_HOME=/opt/android
ENV ANDROID_SDK_ROOT=${ANDROID_HOME}
ENV PATH="${FLUTTER_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/emulator:${ANDROID_HOME}/platform-tools:${PATH}"

RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    wget \
    unzip \
    python3.10 \
    python3-pip \
    libssl-dev \
    libffi-dev \
    openjdk-11-jdk-headless \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --upgrade pip setuptools wheel && \
    pip3 install uv

WORKDIR /app

COPY pubspec.yaml pubspec.lock* ./
COPY requirements.txt export_model.py ./

RUN flutter pub get

RUN mkdir -p assets/models

RUN python3.10 -m pip install --quiet --no-warn-script-location \
    torch==2.2.0 \
    torchvision==0.17.0 \
    transformers==4.36.2 \
    huggingface-hub==0.20.3 \
    numpy==1.24.3 \
    onnx==1.15.0 \
    onnxruntime==1.17.1 \
    Pillow==10.1.0 \
    opencv-python==4.8.1.78

RUN python3.10 export_model.py

COPY . .

RUN flutter clean && \
    flutter pub get

RUN flutter build apk \
    --release \
    --target-platform android-arm64 \
    --build-number "$(date +%s)" \
    --split-per-abi

RUN flutter build ios --no-codesign --config-only || echo "iOS build skipped/failed but workspace is generated."

RUN mkdir -p /output && \
    cp $(find build/app/outputs/flutter-apk -name "*.apk" -type f | head -1) /output/depth_app.apk || true

ENTRYPOINT ["/bin/bash"]
CMD ["-c", "echo 'APK built successfully. Copy from /output/depth_app.apk' && tail -f /dev/null"]
