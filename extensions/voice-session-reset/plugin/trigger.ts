const TRIGGER_PATTERNS: RegExp[] = [
  /\bstart\s+(?:a\s+|the\s+)?new\s+session\b/i,
  /\b(?:reset|restart)\s+(?:the\s+)?(?:chat|session)\b/i,
];

export function matchesTriggerPhrase(text: string): boolean {
  return TRIGGER_PATTERNS.some((pattern) => pattern.test(text));
}
