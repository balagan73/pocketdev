# Pinned, not :latest — see update-openclaw.sh for the safe way to bump
# this. An unpinned tag can silently jump several releases on a rebuild,
# which can break externally-installed (ClawHub/npm) plugins and require
# a state migration; see .openclaw/README.md's "Updating OpenClaw" section.
FROM ghcr.io/openclaw/openclaw:2026.9.4

# Copy pocket-dev orchestration files into the image
COPY pocketdev.yaml /pocket-dev/pocketdev.yaml
COPY stacks/ /pocket-dev/stacks/
COPY extensions/ /pocket-dev/extensions/
COPY .openclaw/orchestrate.sh /pocket-dev/orchestrate.sh

USER root
# ffmpeg is required by the whisper extension (faster-whisper transcription
# fails without it) but extensions run at container start as the non-root
# "node" user and can't apt-get their own packages, so it has to live here.
# gh (GitHub CLI) isn't packaged in bookworm's default repos, and GitHub's
# apt repo (cli.github.com/packages/deb) is currently returning 404s, so the
# .deb release asset is fetched and installed directly instead (curl comes
# from the base openclaw image). It's installed here (not as a stack) since
# it's a core tool useful regardless of which stacks are selected.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && GH_CLI_ARCH="$(dpkg --print-architecture)" \
    && GH_CLI_VERSION="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | grep -m1 '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')" \
    && curl -fsSL -o /tmp/gh.deb "https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}/gh_${GH_CLI_VERSION}_linux_${GH_CLI_ARCH}.deb" \
    && apt-get install -y --no-install-recommends /tmp/gh.deb \
    && rm -f /tmp/gh.deb \
    && rm -rf /var/lib/apt/lists/* \
    && chmod +x /pocket-dev/orchestrate.sh \
    && find /pocket-dev/stacks -name "install.sh" -exec chmod +x {} \; \
    && find /pocket-dev/extensions -name "install.sh" -exec chmod +x {} \; \
    && /pocket-dev/orchestrate.sh
USER node
