import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { matchesTriggerPhrase } from "./trigger.ts";
import { matchesAffirmative, matchesNegative, PendingConfirmations } from "./confirmation.ts";
import { buildResetCommand } from "./reset-command.ts";

const pending = new PendingConfirmations();

export default definePluginEntry({
  id: "voice-session-reset",
  name: "Voice Session Reset",
  register(api) {
    api.on(
      "before_agent_run",
      async (event, ctx) => {
        if (ctx?.channel !== "discord") return;
        const sessionKey = ctx?.sessionKey;
        if (!sessionKey) return;
        const text = event?.prompt ?? "";

        if (pending.isPending(sessionKey)) {
          if (matchesAffirmative(text)) {
            pending.clear(sessionKey);
            const { cmd, args } = buildResetCommand(sessionKey);
            const result = await api.runtime.system.runCommandWithTimeout([cmd, ...args], {
              timeoutMs: 10_000,
            });
            if (result.code !== 0) {
              // NOTE: api.logger.error(message, meta) silently drops the `meta`
              // object for this plugin/runtime combination (same subsystem-logger
              // behavior documented for .info() in task-5-report.md, Deviation 2).
              // Interpolate the diagnostic fields into the message string itself
              // so they actually reach the persisted log on a reset failure.
              api.logger.error(
                `voice-session-reset: reset command failed sessionKey=${JSON.stringify(
                  sessionKey,
                )} code=${JSON.stringify(result.code)} stderr=${JSON.stringify(result.stderr)}`,
              );
              return {
                outcome: "block",
                reason: "voice-session-reset-failed",
                message: "Couldn't reset the session, sorry — try again in a bit.",
              };
            }
            return {
              outcome: "block",
              reason: "voice-session-reset-confirmed",
              message: "Starting fresh.",
            };
          }

          if (matchesNegative(text)) {
            pending.clear(sessionKey);
            return {
              outcome: "block",
              reason: "voice-session-reset-cancelled",
              message: "Okay, keeping this session.",
            };
          }

          // Ambiguous reply to a pending confirmation — don't let it fall through
          // to the model as if it were normal conversation.
          pending.clear(sessionKey);
          return;
        }

        if (matchesTriggerPhrase(text)) {
          pending.start(sessionKey);
          return {
            outcome: "block",
            reason: "voice-session-reset-confirm",
            message: "Want to start a new session? Say yes to confirm.",
          };
        }
      },
      { priority: 50 },
    );
  },
});
