FROM ghcr.io/openclaw/openclaw:latest

# Copy pocket-dev orchestration files into the image
COPY pocketdev.yaml /pocket-dev/pocketdev.yaml
COPY stacks/ /pocket-dev/stacks/
COPY extensions/ /pocket-dev/extensions/
COPY .openclaw/orchestrate.sh /pocket-dev/orchestrate.sh

USER root
# ffmpeg is required by the whisper extension (faster-whisper transcription
# fails without it) but extensions run at container start as the non-root
# "node" user and can't apt-get their own packages, so it has to live here.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/* \
    && chmod +x /pocket-dev/orchestrate.sh \
    && find /pocket-dev/stacks -name "install.sh" -exec chmod +x {} \; \
    && find /pocket-dev/extensions -name "install.sh" -exec chmod +x {} \; \
    && /pocket-dev/orchestrate.sh
USER node
