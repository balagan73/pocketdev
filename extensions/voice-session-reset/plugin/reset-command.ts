export type ResetCommand = {
  cmd: string;
  args: string[];
};

export function buildResetCommand(sessionKey: string): ResetCommand {
  return {
    cmd: "openclaw",
    args: [
      "gateway",
      "call",
      "sessions.reset",
      "--json",
      "--params",
      JSON.stringify({ key: sessionKey, reason: "new" }),
    ],
  };
}
