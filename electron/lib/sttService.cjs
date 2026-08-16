/**
 * OpenAI speech-to-text. Prefers gpt-4o-mini-transcribe; falls back to whisper-1.
 */

const PRIMARY_MODEL = "gpt-4o-mini-transcribe";
const FALLBACK_MODEL = "whisper-1";

/**
 * @param {{
 *   apiKey: string,
 *   wavBuffer: Buffer,
 *   prompt?: string,
 *   preferredModel?: string,
 * }} opts
 */
async function transcribeAudio(opts) {
  const key = String(opts.apiKey || "").trim();
  if (!key) return { ok: false, detail: "No OpenAI API key in Settings" };

  const preferred = String(opts.preferredModel || "").trim();
  const models =
    preferred === FALLBACK_MODEL
      ? [FALLBACK_MODEL]
      : preferred === PRIMARY_MODEL
        ? [PRIMARY_MODEL, FALLBACK_MODEL]
        : [PRIMARY_MODEL, FALLBACK_MODEL];

  const hint = String(opts.prompt || "").trim().slice(0, 220);
  let lastDetail = "Transcription failed";

  for (const model of models) {
    try {
      const form = new FormData();
      form.append(
        "file",
        new Blob([opts.wavBuffer], { type: "audio/wav" }),
        "chunk.wav"
      );
      form.append("model", model);
      form.append("language", "en");
      form.append("response_format", "json");
      form.append("temperature", "0");
      if (hint) form.append("prompt", hint);

      const res = await fetch(
        "https://api.openai.com/v1/audio/transcriptions",
        {
          method: "POST",
          headers: { Authorization: `Bearer ${key}` },
          body: form,
        }
      );

      if (!res.ok) {
        const errText = await res.text();
        lastDetail = `OpenAI ${res.status}: ${errText.slice(0, 240)}`;
        // Retry next model on model/param errors; stop on auth.
        if (res.status === 401 || res.status === 403) {
          return { ok: false, detail: lastDetail };
        }
        continue;
      }

      const json = await res.json();
      const text = String(json.text || "").trim();
      return { ok: true, text, model };
    } catch (err) {
      lastDetail = err && err.message ? String(err.message) : String(err);
    }
  }

  return { ok: false, detail: lastDetail };
}

module.exports = { transcribeAudio, PRIMARY_MODEL, FALLBACK_MODEL };
