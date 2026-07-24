FROM ghcr.io/openclaw/openclaw:latest

USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
     unzip xz-utils ffmpeg python3-venv \
     openjdk-17-jdk-headless curl \
  && rm -rf /var/lib/apt/lists/*
USER node

ENV FLUTTER_HOME=/home/node/flutter
ENV ANDROID_SDK_ROOT=/home/node/android-sdk
ENV PATH="$FLUTTER_HOME/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Install Flutter (web + android)
RUN git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_HOME" \
  && flutter config --enable-web --enable-android --no-analytics \
  && flutter precache --web --android

# Install Android command-line tools
RUN mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools" \
  && curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" \
     -o /tmp/cmdline-tools.zip \
  && unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-tmp \
  && mv /tmp/cmdline-tools-tmp/cmdline-tools "$ANDROID_SDK_ROOT/cmdline-tools/latest" \
  && rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools-tmp

# Accept licenses and install SDK components
RUN yes | sdkmanager --licenses > /dev/null 2>&1 \
  && sdkmanager \
     "platform-tools" \
     "build-tools;36.0.0" \
     "platforms;android-36"

RUN flutter doctor -v || true
