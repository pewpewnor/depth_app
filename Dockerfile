FROM ghcr.io/cirruslabs/flutter:latest AS builder

LABEL maintainer="Depth App Team"
LABEL description="Flutter App for Real-time Depth Estimation"

ENV FLUTTER_HOME=/opt/flutter
ENV ANDROID_SDK_ROOT=/opt/android-sdk-linux
ENV ANDROID_HOME=${ANDROID_SDK_ROOT}
ENV PATH="${FLUTTER_HOME}/bin:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_SDK_ROOT}/build-tools/35.0.0:${PATH}"
ENV FLUTTER_ROOT=${FLUTTER_HOME}
ENV PUB_CACHE=/root/.pub-cache

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

RUN flutter config --no-analytics && \
    flutter precache --android

WORKDIR /app

COPY pubspec.yaml pubspec.lock* ./
COPY assets/ ./assets/

RUN flutter pub get

COPY android/ ./android/
COPY lib/ ./lib/
COPY ios/ ./ios/
COPY pubspec.yaml pubspec.lock* ./

RUN flutter clean && flutter pub get

RUN cd android && ./gradlew clean && cd /app

RUN echo "Building APK..." && \
    flutter build apk \
    --release \
    --target-platform android-arm64 \
    --build-number "$(date +%s)" \
    --split-per-abi \
    --no-tree-shake-icons

RUN echo "Building iOS..." && \
    flutter build ios \
    --release \
    --no-codesign || echo "iOS build warning: codesigning skipped"

RUN mkdir -p /output/android /output/ios && \
    find build/app/outputs/flutter-apk -name "*.apk" -type f \
        -exec cp {} /output/android/ \; && \
    echo "APKs copied:" && ls -lh /output/android/ && \
    if [ -d "build/ios/iphoneos/Runner.app" ]; then \
        cd build/ios/iphoneos && \
        tar -czf /output/ios/depth_app.app.tar.gz Runner.app && \
        cd /app && \
        echo "iOS bundle archived"; \
    else \
        echo "Warning: iOS app bundle not found"; \
    fi

RUN echo "=== Build Artifacts ===" && ls -lhR /output/

FROM scratch AS export
COPY --from=builder /output /