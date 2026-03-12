FROM ghcr.io/cirruslabs/flutter:latest

LABEL maintainer="Depth App Team"
LABEL description="Flutter App for Real-time Depth Estimation"

ENV FLUTTER_HOME=/opt/flutter
ENV ANDROID_HOME=/opt/android
ENV ANDROID_SDK_ROOT=${ANDROID_HOME}
ENV PATH="${FLUTTER_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/emulator:${ANDROID_HOME}/platform-tools:${PATH}"

USER root

WORKDIR /app

COPY pubspec.yaml pubspec.lock* ./

RUN flutter pub get

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
