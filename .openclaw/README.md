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

## Voice transcription (faster-whisper)

Installs into a persistent venv on first run after this feature was added.
Verify it worked with:

```bash
docker compose exec openclaw python3 -c "import faster_whisper; print('ok')"
```
