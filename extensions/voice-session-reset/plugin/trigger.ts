const TRIGGER_PATTERNS: RegExp[] = [
  /\bstart\s+(?:a\s+|the\s+)?new\s+(?:session|conversation|chat)\b/i,
  /\b(?:reset|restart|wipe|clear)\s+(?:the\s+|this\s+)?(?:chat|session|conversation)\b/i,
  /\bforget\s+(?:this\s+|our\s+)?conversation\b/i,
];

export function matchesTriggerPhrase(text: string): boolean {
  return TRIGGER_PATTERNS.some((pattern) => pattern.test(text));
}
