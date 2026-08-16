/** Pure voice parsing helpers (unit-tested). */

const WAKE_RE =
  /\b(?:hey\s+goku|hi\s+goku|okay\s+goku|ok\s+goku|yo\s+goku|son\s+wake\s+up)\b/i;

// Do NOT list "dictate" / command words — the model will hallucinate them from noise.
export const COMPANION_PROMPT =
  "Clear English speech only. The user may say Hey Goku then a short command or question.";

export const DICTATE_PROMPT =
  "Accurate English transcription of study notes or a technical explanation. Prefer verbatim wording over paraphrasing.";

/** Loose STT spellings of "Goku" only — never "google" (false wakes from noise). */
const GOKU_NAME = /\b(goku|goko|goco|goku'?s|go\s*ku)\b/i;

export function isWakePhrase(text: string) {
  if (WAKE_RE.test(text)) return true;
  if (/\bson\s+wake\s+up\b/.test(text)) return true;
  const lead = /\b(hey|hi|okay|ok|yo)\b/.test(text);
  if (!lead) return false;
  return GOKU_NAME.test(text);
}

export function stripWake(text: string) {
  return text
    .replace(WAKE_RE, " ")
    .replace(/\b(hey|hi|okay|ok|yo)\s+(goku|goko|goco|goku'?s|go\s*ku)\b/gi, " ")
    .replace(/\bson\s+wake\s+up\b/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function normalizeHeard(text: string) {
  return text
    .toLowerCase()
    .replace(/[^\w\s']/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function parsePetCommand(text: string): string | null {
  const t = normalizeHeard(text);
  if (/\b(run|sprint|dash|fly)\b/.test(t)) return "run";
  if (/\b(teleport|warp|blink|vanish)\b/.test(t)) return "teleport";
  if (/\b(kamehameha|kame|beam)\b/.test(t)) return "kamehameha";
  if (/\b(open|show)\b/.test(t) && /\b(app|todos?|window)\b/.test(t))
    return "open";
  if (/\b(open app|show app|open todos)\b/.test(t)) return "open";
  if (/\b(power\s*up|transform|super\s*saiyan)\b/.test(t)) return "powerup";
  if (/\b(disc|destructo)\b/.test(t)) return "disc";
  if (/\b(dragon\s*fist)\b/.test(t)) return "dragon";
  return null;
}

/**
 * Explicit only — bare "tutor" / lone "dictate" / "transcribe" must NOT start
 * dictation (those are common STT hallucinations from silence/keyboard noise).
 */
export function wantsDictate(text: string) {
  return /\b(start dictating|dictate mode|take notes|tutor mode|enter tutor mode|start tutor)\b/i.test(
    text
  );
}

/** End dictation (Tutor transcript mode). */
export function wantsStopDictate(text: string) {
  return /\b(stop dictating|stop tutor|done explaining|end tutor|stop transcript|that'?s all)\b/i.test(
    text
  );
}

/**
 * Leave conversation / dictation and return to wake-only standby.
 * "Stop listening" must work here — it used to only match inside dictate mode.
 */
export function wantsStandDown(text: string) {
  const t = normalizeHeard(text);
  if (
    /\b(stop listening|go to sleep|go sleep|standby|stand by|be quiet|never mind|nevermind|not now|i'?m done|that'?s enough|cancel|chill out|back to sleep|stop talking|quiet down)\b/.test(
      t
    )
  ) {
    return true;
  }
  return /^(stop|quiet|enough|later|bye|goodbye)$/.test(t);
}
