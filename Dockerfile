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
    python3 \
    python3-pip \
    python3-venv \
    libssl-dev \
    libffi-dev \
    openjdk-11-jdk-headless \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pubspec.yaml pubspec.lock* ./
COPY requirements.txt export_model.py ./

RUN flutter pub get

RUN mkdir -p assets/models

RUN python3 -m pip install --quiet --no-warn-script-location --break-system-packages --ignore-installed -r requirements.txt

RUN python3 export_model.py

COPY . .

RUN flutter clean && \
    flutter pub get && \
    cd android && ./gradlew clean && cd /app

RUN echo "Building APK..." && \
    flutter build apk \
    --release \
    --target-platform android-arm64 \
    --build-number "$(date +%s)" \
    --split-per-abi \
    --no-tree-shake-icons

RUN echo "Building iOS app..." && \
    flutter build ios --release --no-codesign || echo "iOS build warning: codesigning skipped, app will need to be signed on a Mac."

RUN mkdir -p /output && \
    echo "Copying APK to /output/..." && \
    cp $(find build/app/outputs/flutter-apk -name "*.apk" -type f | head -1) /output/depth_app.apk || echo "Warning: APK not found" && \
    echo "Copying iOS build artifacts to /output/..." && \
    if [ -d "build/ios/iphoneos/Runner.app" ]; then \
        cd build/ios/iphoneos && tar -czf /output/depth_app.app.tar.gz Runner.app && cd /app && \
        echo "iOS app bundle archived to /output/depth_app.app.tar.gz"; \
    else \
        echo "Warning: iOS app bundle not found at build/ios/iphoneos/Runner.app"; \
    fi

RUN echo "Build complete. Artifacts available in /output/:"; ls -lh /output/ 2>/dev/null || echo "No artifacts found"

ENTRYPOINT ["/bin/bash"]
CMD ["-c", "echo 'Build complete. Available outputs:' && ls -lh /output/ && tail -f /dev/null"]
