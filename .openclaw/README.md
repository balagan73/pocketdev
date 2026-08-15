# OpenClaw + Flutter Container — Operator Notes

Quick reference for running and maintaining this stack. Full design/plan docs
live in `docs/superpowers/`.

## What this is

OpenClaw runs as a single container — the gateway process and all tool
execution together, no host-side OpenClaw process, no per-tool sandbox — with
a Flutter SDK (web build target only) layered on top. The container is the
entire trust boundary: the agent's reach never extends past it.

## First run

```bash
docker compose up -d --build
docker compose logs openclaw   # copy the generated gateway token
```

The token is also saved at `.openclaw/data/.env` (`OPENCLAW_GATEWAY_TOKEN=...`)
for reuse after restarts.

**Important:** after pulling changes that touch `.openclaw/Dockerfile` (like
the faster-whisper packages), you must `docker compose up -d --build` — a
plain `docker compose restart` reuses the old image and won't pick up new apt
packages or SDK layers.

## Health check

```bash
docker compose exec openclaw node openclaw.mjs health --token "$(grep OPENCLAW_GATEWAY_TOKEN .openclaw/data/.env | cut -d= -f2)"
```

## Telegram pairing

Not yet configured. Task 6 in
`docs/superpowers/plans/2026-07-21-flutter-openclaw-container.md` is
postponed pending a bot token (from [@BotFather](https://t.me/BotFather)) and
the operator's numeric Telegram ID (from
[@userinfobot](https://t.me/userinfobot)) — see that task's steps to resume
it.

## GitHub CLI (gh)

`gh` is installed in the base image so it's available to the agent for PRs,
issues, and repo operations. It needs a one-time login per container (state
persists in `.openclaw/data/gh/`, mounted from the persistent data volume, so
you won't need to repeat this after restarts or rebuilds — only if that
volume is wiped):

```bash
docker compose exec openclaw gh auth login
```

Answer the prompts: `GitHub.com` → `HTTPS` → `Login with a web browser`. It
prints a one-time code and a `https://github.com/login/device` URL — open
that URL on any device, paste the code, and approve. Verify with:

```bash
docker compose exec openclaw gh auth status
```

## Voice transcription (faster-whisper)

On first run, the entrypoint installs `faster-whisper` into a persistent venv,
writes `whisper-transcribe.py` into the openclaw data dir, and wires it up as
openclaw's `tools.media.audio` transcription command — all automatic, no
manual config needed. The whisper model itself downloads into
`.openclaw/data/whisper-models/` on first real transcription (~25s cold,
~3s once cached).

Verify it worked with:

```bash
docker compose exec openclaw python3 -c "import faster_whisper; print('ok')"
docker compose exec openclaw node openclaw.mjs config get tools.media.audio
```
