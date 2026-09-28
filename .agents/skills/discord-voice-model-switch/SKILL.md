---
name: "discord-voice-model-switch"
description: "Switch or report the Discord voice channel's model/mode when the user asks, by voice or text — e.g. \"switch to sonnet\", \"use haiku\", \"go back to the default\", \"use the realtime model\", \"what model are you using\". Runs scripts/discord-voice-mode.sh."
---

# Discord voice model switch

Every action here goes through `/workspace/scripts/discord-voice-mode.sh`. Run
only that script, with only the arguments shown below. Don't edit
`openclaw.json` or call `config patch` yourself: the script validates the
target against OpenClaw's live model catalog, and hand edits skip that check.

## "What model are you using?"

```
/workspace/scripts/discord-voice-mode.sh status
```

Say the mode and model in one short sentence, e.g. "I'm on Claude Haiku 4.5."
In `bidi` mode say you're in realtime mode, name the realtime model, and name
the agent model as the one behind it.

## "Switch to <X>"

1. List the valid targets. The `*` marks the active one:

   ```
   /workspace/scripts/discord-voice-mode.sh list
   ```

2. Map the request to exactly one target:

   | User says | Run with |
   |---|---|
   | "default", "back to normal", "Claude" (no model named) | `default` |
   | "realtime", "GPT realtime", "the fast voice" | `realtime` |
   | a model name, e.g. "sonnet", "haiku", "GPT 5.4 mini" | `model <key>`, where `<key>` is the one line from `list` that matches |

   Take `<key>` from the `list` output you just printed, never from memory:
   the catalog changes. If none matches, or more than one does (e.g. "GPT 5.4"
   when both `codex/gpt-5.4` and `codex/gpt-5.4-mini` are listed), don't
   switch. Read out the closest few names and ask which one. If the target is
   already marked `*`, say so and stop.

3. `realtime` uses the paid OpenAI API. Switch to it only when the user asked
   for realtime by name.

4. Run the switch with `--after 10`:

   ```
   /workspace/scripts/discord-voice-mode.sh model <key> --after 10
   /workspace/scripts/discord-voice-mode.sh default --after 10
   /workspace/scripts/discord-voice-mode.sh realtime --after 10
   ```

   Without `--after`, the Discord channel reloads while your reply is still
   being spoken, and the reply is lost. `--after 10` checks the target now,
   then switches 10 seconds later in the background.

5. If the command printed `Validated. Switching ...`, reply with one short
   sentence, e.g. "Switching to Sonnet — I'll drop out for a second and be
   right back." If it failed, say briefly why. For an unknown model, name a
   few from `list`.

The switch lasts until the container restarts. After a restart the voice
channel is back on the default from `extensions/discord-voice/config.yaml`.

## When you can't run the script

In realtime (`bidi`) mode you're reached through a consult, and those run
read-only by default. If you have no shell tool, don't try another route.
Say: "I can't change the voice model from realtime voice. Type it in this
channel's text chat instead, like 'switch to haiku'." Typed messages run as a
normal agent turn and can do the switch.
