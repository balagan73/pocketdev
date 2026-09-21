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

## Voice session reset

Say a trigger phrase in the Discord voice channel (e.g. "start new session",
"reset chat", "restart the conversation", "wipe this chat", or "forget this
conversation") to reset that channel's session in place — no container or
Gateway restart. It asks for confirmation first ("Want to start a new
session? Say yes to confirm."); reply "yes" to reset, anything else keeps
the session. This is intercepted directly from the raw message text before
the model ever runs, so it doesn't depend on the model choosing to do
anything.

**No setup needed.** This ships as part of the `discord-voice` extension, so
selecting `discord-voice` installs it. The reset goes through OpenClaw's
`sessions.reset` Gateway RPC, which needs the in-container CLI device to
hold the `operator.admin` scope; the plugin requests and approves that scope
automatically once the Gateway starts, and the grant persists in the
bind-mounted `.openclaw/data/`.

**If the reset doesn't work,** check what the automatic bootstrap reported:

```bash
docker compose logs openclaw | grep voice-session-reset
```

Expect "voice-session-reset: operator.admin scope bootstrap succeeded.". If
you instead see "...did not complete after retries...", or no bootstrap line
at all, grant the scope manually — list any pending scope-upgrade request,
then approve it by `requestId`:

```bash
docker compose exec openclaw node openclaw.mjs devices list --json
docker compose exec openclaw node openclaw.mjs devices approve <requestId> --json
```

You may need to repeat that cycle once or twice, since OpenClaw requests
scopes (`operator.pairing`, then `operator.admin`) incrementally. It's done
once the CLI device's `scopes` include `operator.admin`.

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

## Usage metrics (per-agent token tracking)

Each end user gets their own OpenClaw agent bound to their own Discord bot
(see "Per-user onboarding" below), so per-agent usage is per-user usage.
The `usage-metrics` extension enables OpenClaw's built-in
`diagnostics-prometheus` plugin — no custom token-counting code — and an
optional Prometheus + Grafana overlay visualizes it.

Once `usage-metrics` is selected (via `./setup.sh`, or present in
`pocketdev.yaml`) and you run `./rebuild.sh`, Prometheus and Grafana come up
automatically alongside the gateway — no extra flags needed. `rebuild.sh`
writes a root `.env` setting `COMPOSE_FILE` to include the metrics overlay
whenever `usage-metrics` is selected (and removes it otherwise), so a plain
`docker compose up -d` picks up both files on its own. Deselecting the
extension and running `./rebuild.sh` again tears the overlay back down
(`--remove-orphans` cleans up the now-unlisted containers).

If `usage-metrics` isn't selected, Prometheus never has a scrape token to
authenticate with and would just get 401s from the gateway — which is why
its containers only ever come up together with the extension, never on
their own.

Both services publish to loopback only (`127.0.0.1`), matching this
deployment's trust model — the container (and now the metrics overlay) is
reachable from this host only, never from other machines on the LAN, even
though `localhost` still resolves to it locally.

Grafana: `http://localhost:3000`. Default login is `admin`/`admin` unless
you set `GRAFANA_ADMIN_PASSWORD` in `.env` or the shell environment before
`docker compose up` — do that for a real deployment instead of relying on
Grafana's first-login change-password prompt. Open the "Usage per agent"
dashboard for token totals broken out by agent, over any selected time
range.

Prometheus: `http://localhost:9090`, loopback-only, no authentication —
treat it the same as the gateway itself from a trust standpoint.

**First-ever container start only:** the extension writes Prometheus's
scrape token from `OPENCLAW_GATEWAY_TOKEN`, but that token is generated
*after* extensions run on a brand-new container. If `docker compose logs
openclaw | grep "Prometheus scrape token"` shows the "not yet generated"
warning, run `docker compose restart` once more — every subsequent start
picks it up fine.

**Cost tracking isn't available yet.** The `diagnostics-prometheus` plugin
doesn't currently export a cost metric, so the dashboard shows token counts
only. This can be revisited if a future plugin version adds cost export.

### Per-user onboarding

1. Create a new Discord application/bot for the patron (same steps as
   "Discord voice" above).
2. Create their isolated agent and bind it to their bot:
   ```bash
   docker compose exec openclaw node openclaw.mjs agents add <userId>
   docker compose exec openclaw node openclaw.mjs agents bind --agent <userId> --bind discord:<accountId>
   ```
3. Their usage now appears automatically as a new series labeled by `agent`
   in the dashboard — no metrics code to touch.

### Testing without a Discord bot

`openclaw agent --agent <id> --message "..."` runs a turn through the
Gateway for any agent, bypassing channel routing entirely — useful for
exercising the metrics pipeline without provisioning a real bot per test
agent.

## Remote restart & rebuild (from inside the container)

The container has no `docker.sock` and can't restart or rebuild itself.
`scripts/restart-helper.py` (host-side) and `scripts/restart-trigger.py`
(container-side) let the agent ask the host to do either over a Unix socket
— useful when the agent needs to recover from a stuck gateway process, or
wants to pick up a change it just made to its own extensions.

Start the listener on the **host** (not inside the container) and leave it
running — it isn't supervised, so it won't survive a host reboot on its own
unless you wrap it in `tmux`, `screen`, or a systemd user service:

```bash
nohup python3 scripts/restart-helper.py > /tmp/restart-helper.log 2>&1 &
disown
```

It listens on `/tmp/openclaw-restart/helper.sock`, which `docker-compose.yml`
mounts into the container at `/run/restart-helper` (the socket's *parent
directory* is mounted, not the file itself, since the helper recreates the
socket file every time it restarts).

From inside the container:

```bash
python3 /workspace/scripts/restart-trigger.py           # restart
python3 /workspace/scripts/restart-trigger.py rebuild   # rebuild
```

- **`restart`** (`docker compose restart openclaw`) — seconds, reuses the
  existing image. Good for a hung/stuck process or state that's only read at
  startup (e.g. plugin enablement); useless for anything baked into the
  image at build time.
- **`rebuild`** (`bash rebuild.sh`) — minutes, rebuilds the image first.
  Needed whenever `extensions/`, `stacks/`, or `pocketdev.yaml` changed —
  see the top-level `README.md`'s note on extensions needing a rebuild when
  their own code (not just their config) changes.

Either command kills the very container the trigger script is running in
partway through, so it may report a broken connection instead of a clean
"ok" — that's expected, not a failure. Check the host-side listener's log or
`docker compose logs openclaw` to confirm it actually worked.

## Updating OpenClaw

`.openclaw/Dockerfile` pins `FROM ghcr.io/openclaw/openclaw:<version>` to an
exact version — not `:latest`. A plain `./rebuild.sh` only pulls that base
image the first time it's ever built on a machine; after that it reuses the
locally cached image indefinitely, so the pin never drifts on its own and
`rebuild.sh` never silently jumps versions.

To move to a newer version, run:

```bash
./update-openclaw.sh <version>   # e.g. ./update-openclaw.sh 2026.10.1
```

This isn't just a rebuild — a core version jump can require a state
migration before the gateway will even start, and it can break
externally-installed (ClawHub/npm) plugins whose compiled code no longer
matches the new core's internals, even though bundled plugins never have
this problem. The script: backs up real state (verified) to
`~/backups/pocketdev/` (override with `OPENCLAW_BACKUP_DIR`), updates the
Dockerfile pin, rebuilds, stops the gateway cleanly, runs `doctor --fix` in
isolation against the real state, brings the gateway back up, updates any
externally-installed plugins (currently `discord`, `usage-metrics`'s
`diagnostics-prometheus`), and finishes with a `status --deep` check.

Read its output — it confirms the gateway responds, but whether each
channel (Discord/Telegram/etc.) actually works again needs a human look at
that status output, same as any upgrade.
