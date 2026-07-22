FROM ghcr.io/openclaw/openclaw:latest

USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends unzip xz-utils \
  && rm -rf /var/lib/apt/lists/*
USER node

ENV FLUTTER_HOME=/home/node/flutter
ENV PATH="$FLUTTER_HOME/bin:$PATH"

RUN git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_HOME" \
  && flutter config --enable-web --no-analytics \
  && flutter precache --web

# Informational only — flutter doctor reports on Android/desktop/Chrome
# tooling we deliberately don't install; never fail the build on it.
RUN flutter doctor -v || true
