# pocket-dev: OpenClaw + Pluggable Stacks & Extensions

A single Docker container running OpenClaw (an AI coding agent sandbox) with a pluggable stacks-and-extensions system for adding SDKs, runtimes, and tool integrations.

## What this is

OpenClaw runs inside a single container — the gateway process and all tool execution together, no host-side OpenClaw process, no per-tool sandbox. The container is the entire trust boundary. pocket-dev layers a modular build system on top: **stacks** add SDKs and tools at build time (Flutter SDK, Android SDK), and **extensions** add runtime-only features without rebuild (Telegram integration, voice transcription, text-to-speech).

## Quick start

```bash
./setup.sh                         # interactive wizard, writes pocketdev.yaml
./rebuild.sh                       # builds and starts the container
docker compose logs openclaw       # copy the printed gateway token
```

That's it. The token is also saved at `.openclaw/data/.env` for reuse across container restarts.

For operator-level details (health check, Telegram pairing, voice transcription, troubleshooting), see [`.openclaw/README.md`](.openclaw/README.md).

## How orchestration works

### Stacks vs Extensions

**Stacks** (build-time) change the Docker image: Flutter SDK, Android SDK, etc. Selecting a stack requires rebuilding the container (`./rebuild.sh`), which runs the stack's `install.sh` as root during `docker build`.

**Extensions** (runtime) only modify the running container: Telegram channel tuning, text-to-speech configuration, voice transcription setup, custom tooling. Selecting an extension requires only a container restart (`docker compose restart`)—no rebuild.

### Single Source of Truth: `pocketdev.yaml`

This file holds your selections:

```yaml
stacks:
  - android-sdk
  - flutter

extensions:
  - piper
  - telegram
  - whisper
```

Three commands consume it:

1. **`setup.sh`** — interactive discovery of available stacks/extensions (reads `stacks/*/manifest.yaml` and `extensions/*/manifest.yaml`), checkbox or numbered menu depending on TTY, writes `pocketdev.yaml`.
2. **`rebuild.sh`** — parses `pocketdev.yaml`, sources each selected stack's `env.sh` to gather environment variables (like `FLUTTER_HOME`, `ANDROID_SDK_ROOT`), writes `.openclaw/pocketdev-stacks.env`, then runs `docker compose up -d --build`.
3. **Build and startup scripts** inside the image:
   - `.openclaw/orchestrate.sh` (runs at `docker build` time) — reads the `stacks:` list, runs each stack's `install.sh` as root.
   - `.openclaw/entrypoint.sh` (runs at container start) — sources the stack env vars, then reads the `extensions:` list and runs each extension's `install.sh` as the non-root `node` user.

### Stack & Extension Anatomy

Each stack/extension directory has:

- **`manifest.yaml`** — metadata: `name`, `description`, `requires_rebuild: true|false`.
- **`install.sh`** — installation script (stacks run as root at build time; extensions run as `node` at container start).
- **`env.sh`** (stacks only) — shell script sourced by `rebuild.sh` to compute runtime environment (e.g., `export FLUTTER_HOME=/home/node/flutter; export PATH="$FLUTTER_HOME/bin:$PATH"`).
- **`config.yaml`** (optional) — extension configuration; e.g., Telegram's `streaming_mode` and `tool_progress` settings.

**Example:** the Flutter stack (`stacks/flutter/`):
- `install.sh` clones the Flutter SDK, configures it for web and Android, and fixes ownership so the `node` user can run it.
- `env.sh` exports `FLUTTER_HOME` and updates `PATH`.
- `manifest.yaml` marks `requires_rebuild: true` because the SDK is baked into the image.

**Example:** the Telegram extension (`extensions/telegram/`):
- `install.sh` reads `config.yaml`, then patches OpenClaw's channel config to use progress-mode streaming (avoiding the flash-and-disappear effect on partial answers).
- `config.yaml` defines `streaming_mode` and `tool_progress` knobs.
- `manifest.yaml` marks `requires_rebuild: false` because it only tweaks runtime config.

### Why split stacks and extensions?

Stacks need the image to change (new binaries, dependencies), so you rebuild once and the changes persist across container restarts. Extensions only need to configure or patch the running OpenClaw process, so they can install on every container start without expensive rebuilds. This separation gives you:

- **Fast iteration** — change extensions and restart the container in seconds.
- **Clean separation** — stacks are image-level; extensions are container-level.
- **No cascading rebuilds** — adding a Telegram bot token or toggling voice transcription doesn't require rebuilding the entire Docker image.

## Repo layout

- **`app/`** — The Flutter application itself (web build target; Android target requires the `android-sdk` stack).
- **`stacks/`** — Available stacks: `flutter/`, `android-sdk/`. Each has `manifest.yaml`, `install.sh`, and `env.sh`.
- **`extensions/`** — Available extensions: `telegram/`, `piper/`, `whisper/`, `discord-voice/`, `usage-metrics/`. Each has `manifest.yaml`, `install.sh`, and optional `config.yaml`.
- **`.openclaw/`** — Container and orchestration:
  - `Dockerfile` — copies pocket-dev files into the image, installs ffmpeg (needed by whisper) and the GitHub CLI (`gh`), runs `orchestrate.sh`.
  - `orchestrate.sh` — build-phase script that runs each selected stack's `install.sh` as root.
  - `entrypoint.sh` — container-start script that sources stack env, runs each selected extension's `install.sh`, generates the OpenClaw gateway token, installs Claude Code CLI, then starts the gateway.
  - `pocketdev-stacks.env` — generated by `rebuild.sh`; contains environment variables sourced from selected stacks.
  - `data/` — persistent container state (OpenClaw config, gateway token, Claude Code cache).
  - `README.md` — operator quick-reference for health check, Telegram pairing, voice transcription.
- **`docker-compose.yml`** — single service (`openclaw`) with volume mounts and env configuration.
- **`docker-compose.metrics.yml`** — optional overlay adding Prometheus + Grafana for per-agent (per-user) usage dashboards; see `.openclaw/README.md`'s "Usage metrics" section.
- **`setup.sh`** — interactive wizard to select stacks and extensions.
- **`rebuild.sh`** — resolve stack env vars and rebuild/restart the container.
- **`pocketdev.yaml`** — your current selections (generated by `setup.sh`, consumed by `rebuild.sh`, `orchestrate.sh`, and `entrypoint.sh`).
- **`docs/superpowers/`** — design docs and plans.
- **`tasks/`** — task specs for adding new stacks, extensions, or features.

## Next steps

1. Run `./setup.sh` to discover available stacks and extensions.
2. Select what you need (Flutter for web builds, Android SDK for Android builds, voice transcription, Telegram integration, etc.).
3. Run `./rebuild.sh` to build the container.
4. Copy the gateway token from `docker compose logs openclaw` and paste it into Claude Code.
5. For operator notes (health check, Telegram pairing, whisper config), see [`.openclaw/README.md`](.openclaw/README.md).
