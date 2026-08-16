import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { matchesTriggerPhrase } from "./trigger.ts";
import { classifyReply, PendingConfirmations } from "./confirmation.ts";
import { buildResetCommand } from "./reset-command.ts";

const pending = new PendingConfirmations();
const CONFIRM_MESSAGE = "Want to start a new session? Say yes to confirm.";

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
          // Repeating the trigger phrase while a confirmation is pending
          // just re-asks and resets the TTL, rather than being treated as
          // an ambiguous (and therefore cancelling) reply.
          if (matchesTriggerPhrase(text)) {
            pending.start(sessionKey);
            return {
              outcome: "block",
              reason: "voice-session-reset-confirm",
              message: CONFIRM_MESSAGE,
            };
          }

          pending.clear(sessionKey);

          if (classifyReply(text) === "yes") {
            const { cmd, args } = buildResetCommand(sessionKey);
            let result;
            try {
              result = await api.runtime.system.runCommandWithTimeout([cmd, ...args], {
                timeoutMs: 10_000,
              });
            } catch (err) {
              api.logger.error(
                `voice-session-reset: reset command threw sessionKey=${JSON.stringify(
                  sessionKey,
                )} err=${JSON.stringify(String(err))}`,
              );
              return {
                outcome: "block",
                reason: "voice-session-reset-failed",
                message: "Couldn't reset the session, sorry — try again in a bit.",
              };
            }
            if (result.code !== 0) {
              // NOTE: api.logger.error(message, meta) silently drops the
              // `meta` object for this plugin/runtime combination (same
              // subsystem-logger behavior documented for .info() and .error()
              // in task-5-report.md). Interpolate diagnostic fields into the
              // message string itself so they actually reach the log.
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

          // "no", or anything ambiguous — per the design, both are treated
          // the same: cancel, and don't let the utterance reach the model as
          // if it were real conversation content.
          return {
            outcome: "block",
            reason: "voice-session-reset-cancelled",
            message: "Okay, keeping this session.",
          };
        }

        if (matchesTriggerPhrase(text)) {
          pending.start(sessionKey);
          return {
            outcome: "block",
            reason: "voice-session-reset-confirm",
            message: CONFIRM_MESSAGE,
          };
        }
      },
      { priority: 50 },
    );
  },
});
