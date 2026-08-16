import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { matchesTriggerPhrase } from "./trigger.ts";
import { classifyReply, PendingConfirmations } from "./confirmation.ts";
import { buildResetCommand } from "./reset-command.ts";
import { bootstrapOperatorAdminScope } from "./scope-bootstrap.ts";
import { extractUserUtterance } from "./prompt-text.ts";

const pending = new PendingConfirmations();
const CONFIRM_MESSAGE = "Want to start a new session? Say yes to confirm.";

export default definePluginEntry({
  id: "voice-session-reset",
  name: "Voice Session Reset",
  register(api) {
    // The operator.admin scope grant that sessions.reset needs can only be
    // requested once the Gateway is actually listening, so it runs here
    // rather than in the extension's install.sh — that script completes
    // before the entrypoint execs the Gateway, when no RPC can succeed.
    api.on("gateway_start", async () => {
      try {
        await bootstrapOperatorAdminScope(
          (args) => api.runtime.system.runCommandWithTimeout(["openclaw", ...args], {
            timeoutMs: 10_000,
          }),
          api.logger,
        );
      } catch (err) {
        api.logger.warn(
          `voice-session-reset: operator.admin scope bootstrap threw err=${JSON.stringify(
            String(err),
          )}`,
        );
      }
    });

    // A direct text-phrase match arms `pending` here — this is the ONLY
    // trigger, and the only place a reset actually happens. It intercepts
    // before the model ever runs, so it doesn't depend on the model
    // choosing to call any tool.
    api.on(
      "before_agent_run",
      async (event, ctx) => {
        if (ctx?.channel !== "discord") return;
        const sessionKey = ctx?.sessionKey;
        if (!sessionKey) return;
        const text = extractUserUtterance(event?.prompt ?? "");

        if (!pending.isPending(sessionKey)) {
          if (matchesTriggerPhrase(text)) {
            pending.start(sessionKey);
            return {
              outcome: "block",
              reason: "voice-session-reset-confirm",
              message: CONFIRM_MESSAGE,
            };
          }
          return;
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
      },
      { priority: 50 },
    );
  },
});
