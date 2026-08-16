const BOOTSTRAP_KEY = "agent:main:__voice-session-reset-scope-bootstrap__";
const MAX_ATTEMPTS = 6;
const RETRY_DELAY_MS = 1500;

export function extractRequestId(text: string): string | null {
  const match = text.match(/requestId:\s*([a-f0-9-]+)/);
  return match ? match[1] : null;
}

export type BootstrapRunCommand = (
  args: string[],
) => Promise<{ code: number; stdout?: string; stderr?: string }>;

export type BootstrapLogger = {
  info: (message: string) => void;
  warn: (message: string) => void;
};

export async function bootstrapOperatorAdminScope(
  runCommand: BootstrapRunCommand,
  logger: BootstrapLogger,
  sleep: (ms: number) => Promise<void> = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
): Promise<void> {
  let succeeded = false;

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    const result = await runCommand([
      "gateway",
      "call",
      "sessions.reset",
      "--json",
      "--params",
      JSON.stringify({ key: BOOTSTRAP_KEY }),
    ]);

    if (result.code === 0) {
      succeeded = true;
      break;
    }

    const requestId = extractRequestId(`${result.stdout ?? ""}${result.stderr ?? ""}`);
    if (requestId) {
      await runCommand(["devices", "approve", requestId]);
      continue;
    }

    // No scope-upgrade request found — could be a transient "Gateway not
    // ready yet" connection failure rather than a real scope rejection.
    // Retry with a short delay instead of giving up on the first miss.
    if (attempt < MAX_ATTEMPTS) {
      await sleep(RETRY_DELAY_MS);
    }
  }

  await runCommand([
    "gateway",
    "call",
    "sessions.delete",
    "--json",
    "--params",
    JSON.stringify({ key: BOOTSTRAP_KEY }),
  ]).catch(() => undefined);

  if (succeeded) {
    logger.info("voice-session-reset: operator.admin scope bootstrap succeeded.");
  } else {
    logger.warn(
      "voice-session-reset: operator.admin scope bootstrap did not complete after retries — " +
        "session resets will fail until the scope is granted manually (see .openclaw/README.md).",
    );
  }
}
