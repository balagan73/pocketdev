const AFFIRMATIVE_PATTERNS: RegExp[] = [
  /\b(yes|yeah|yep|confirm(?:ed)?|do it|go ahead)\b/i,
];

const NEGATIVE_PATTERNS: RegExp[] = [
  /\b(no|nope|cancel|never\s*mind|stop)\b/i,
];

export function matchesAffirmative(text: string): boolean {
  return AFFIRMATIVE_PATTERNS.some((pattern) => pattern.test(text));
}

export function matchesNegative(text: string): boolean {
  return NEGATIVE_PATTERNS.some((pattern) => pattern.test(text));
}

const DEFAULT_TTL_MS = 20_000;

type PendingEntry = {
  expiresAt: number;
};

export class PendingConfirmations {
  private readonly pending = new Map<string, PendingEntry>();
  private readonly ttlMs: number;
  private readonly now: () => number;

  constructor(ttlMs: number = DEFAULT_TTL_MS, now: () => number = Date.now) {
    this.ttlMs = ttlMs;
    this.now = now;
  }

  start(sessionKey: string): void {
    this.pending.set(sessionKey, { expiresAt: this.now() + this.ttlMs });
  }

  isPending(sessionKey: string): boolean {
    const entry = this.pending.get(sessionKey);
    if (!entry) return false;
    if (entry.expiresAt <= this.now()) {
      this.pending.delete(sessionKey);
      return false;
    }
    return true;
  }

  clear(sessionKey: string): void {
    this.pending.delete(sessionKey);
  }
}
