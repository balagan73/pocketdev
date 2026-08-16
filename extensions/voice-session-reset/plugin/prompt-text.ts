// before_agent_run's event.prompt is the full constructed prompt sent to the
// model, not the user's raw message — for Discord voice it's prefixed with
// several sentences of reply-style instructions (which happen to contain the
// standalone word "no", e.g. "unless no spoken response is appropriate").
// Running trigger/reply matching against that whole blob poisons the match.
// The actual utterance is appended after this marker; extract just that.
const VOICE_TRANSCRIPT_MARKER = /voice transcript from speaker\s*"[^"]*":\s*/i;

export function extractUserUtterance(prompt: string): string {
  const match = VOICE_TRANSCRIPT_MARKER.exec(prompt);
  if (!match) return prompt.trim();
  return prompt.slice(match.index + match[0].length).trim();
}
