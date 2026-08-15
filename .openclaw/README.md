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

1. Message [@BotFather](https://t.me/BotFather) on Telegram, run `/newbot`,
   and follow the prompts to get a bot token.
2. Message [@userinfobot](https://t.me/userinfobot) to get your numeric
   Telegram user ID.
3. Pair the channel:
   ```bash
   docker compose exec openclaw node openclaw.mjs channels add --channel telegram --token "<bot-token>"
   ```
4. Restrict who can message the agent to your own ID:
   ```bash
   docker compose exec openclaw node openclaw.mjs config patch --stdin << 'EOF'
   { channels: { telegram: { allowFrom: ["<your-numeric-id>"], dmPolicy: "allowlist" } } }
   EOF
   ```

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

## Discord voice (continuous Talk mode)

One-time manual setup is required. `extensions/discord-voice/install.sh`
installs the Discord channel plugin (published separately from OpenClaw
core, unlike Telegram which is bundled) and patches the non-secret mode
settings automatically; the bot token, guild ID, and your user ID are
secrets/environment-specific, so those still need the manual steps below.

Uses `stt-tts` mode: reuses the container's existing whisper transcription
and piper TTS, so it's free and requires no external API keys — unlike
OpenClaw's `agent-proxy` realtime mode, which needs a paid realtime
provider and is *not* what this extension configures.

1. Create a Discord application + bot at
   [discord.com/developers/applications](https://discord.com/developers/applications)
   ("Build a bot" → "New Application" → "Bot" tab → "Reset Token", copy it).
2. In the same application, on the **Bot** tab, scroll down to
   **Privileged Gateway Intents** and toggle on **Message Content Intent**
   and **Server Members Intent**, then **Save Changes**.
3. Invite the bot to your server:
   1. In the same application, go to the **OAuth2** tab → **URL
      Generator**.
   2. Under **Scopes**, check `bot` **and** `applications.commands`.
      Skipping `applications.commands` is a common trap: the bot still
      joins your server and slash commands still register on Discord's
      backend, but they never appear in any of that server's channels —
      only in DMs to the bot. If `/vc` shows up when you DM the bot but
      not in a server channel, this scope is what's missing; redo this
      step with both scopes checked and re-open the generated URL to
      re-authorize (Discord adds the missing grant, it won't invite a
      duplicate bot).
   3. Under **Bot Permissions** (appears once `bot` is checked), check
      **Connect**, **Speak**, **Send Messages**, **Read Message
      History**.
   4. Copy the generated URL from the bottom of the page.
   5. Open that URL in a browser (on desktop it redirects into the
      Discord app if installed and logged in; on mobile, tapping the
      link opens the app directly). Discord shows an **"Add to
      Server"** dialog — pick your server from the dropdown (only
      servers where you have **Manage Server** permission are listed)
      and click **Authorize**, completing the captcha if prompted.
   6. The bot now appears in your server's member list (offline until
      the extension is running).
4. Get your server (guild) ID and your own Discord user ID:
   1. In the Discord client: **User Settings** (gear icon) → **Advanced**
      → enable **Developer Mode**.
   2. Right-click your server's icon in the sidebar → **Copy Server ID**
      — this is your guild ID.
   3. Right-click your own username/avatar → **Copy User ID** — this is
      your Discord user ID. (Not the bot's token or the bot's own user
      ID — this is *your* account, the one allowed to talk to the bot.)
5. Patch the bot token and guild allowlist (replace the placeholders with
   your real values — this is a secret plus environment-specific IDs, so
   it's a manual step rather than something `install.sh` can do; the token
   goes in as a plain string here, same as Telegram's `botToken` — it ends
   up only in `.openclaw/data/openclaw.json`, gitignored, never committed):
   ```bash
   docker compose exec openclaw node openclaw.mjs config patch --stdin << 'EOF'
   { channels: { discord: { token: "<YOUR_BOT_TOKEN>", guilds: { "<YOUR_GUILD_ID>": { users: ["<YOUR_DISCORD_USER_ID>"] } } } } }
   EOF
   ```
6. Restart to pick up the extension (installs the Discord plugin) and the
   new config:
   ```bash
   docker compose restart
   ```
   First time only: this restart is what triggers `extensions/discord-voice/install.sh`
   to run `openclaw plugins install @openclaw/discord`, so it can take a bit
   longer than a normal restart.

7. Send the bot any message (DM or in an allowed channel/server). Being on
   the `guilds.<id>.users` allowlist controls who's *allowed* to talk to
   it, but the first message still triggers a separate device-pairing
   handshake — the bot replies with a one-time pairing code instead of a
   real answer. Approve it with:
   ```bash
   docker compose exec openclaw node openclaw.mjs pairing approve discord <CODE>
   ```
   After approving, that Discord sender is remembered — you won't need to
   pair again.

Verify with:

```bash
docker compose exec openclaw node openclaw.mjs channels status
```

Look for a `Discord default: enabled, configured, running, connected` line.

Then, in a text channel the bot can see in your server, run
`/vc join channel:<voice-channel-id>` and speak — you should hear a
piper-synthesized reply after whisper transcribes what you said. `/vc
leave` ends the session. If it doesn't respond, check
`docker compose logs openclaw` for errors.

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

Transcription is pinned to `language="en"` in `extensions/whisper/install.sh`
(the `whisper-transcribe.py` heredoc) rather than left on auto-detect.
Auto-detect can misfire on short or noisy clips and transcribe into the wrong
language, which then makes the agent reply in that language too — and an
English-only Piper voice just mangles non-English text into unintelligible
audio instead of erroring. Change the `language="en"` argument there if you
configure a non-English Piper voice.
