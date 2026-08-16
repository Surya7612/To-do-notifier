/**
 * ElevenLabs text-to-speech, with model fallbacks for plan/deprecation errors.
 * @param {{ loadData: Function, clampText: Function }} deps
 */
function createTtsService({ loadData, clampText }) {
  async function synthesizeElevenLabs(text) {
    const settings = loadData().settings;
    const key =
      String(settings.elevenLabsApiKey || "").trim() ||
      String(process.env.ELEVENLABS_API_KEY || "").trim();
    const voiceId =
      String(settings.elevenLabsVoiceId || "").trim() ||
      "zYcjlYFOd3taleS0gkk3";
    if (!key) {
      return { ok: false, detail: "No ElevenLabs API key in Settings", hasKey: false };
    }
    const line = clampText(text, 400);
    if (!line) return { ok: false, detail: "Empty text", hasKey: true };

    const models = [
      "eleven_flash_v2_5",
      "eleven_multilingual_v2",
      "eleven_turbo_v2_5",
    ];
    let lastDetail = "";
    for (const model_id of models) {
      try {
        const res = await fetch(
          `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voiceId)}`,
          {
            method: "POST",
            headers: {
              "xi-api-key": key,
              "Content-Type": "application/json",
              Accept: "audio/mpeg",
            },
            body: JSON.stringify({
              text: line,
              model_id,
              voice_settings: {
                stability: 0.35,
                similarity_boost: 0.8,
              },
            }),
          }
        );
        if (!res.ok) {
          const errText = await res.text().catch(() => "");
          lastDetail = `ElevenLabs ${res.status} (${model_id}): ${errText.slice(0, 160)}`;
          if (res.status === 401 || res.status === 403) {
            return { ok: false, detail: lastDetail, hasKey: true };
          }
          // Free tier cannot use Voice Library IDs over the API
          if (
            res.status === 402 ||
            /paid_plan_required|Free users cannot use library voices/i.test(
              errText
            )
          ) {
            return {
              ok: false,
              hasKey: true,
              detail:
                "ElevenLabs free plan blocks Voice Library IDs on the API. Use a voice from My Voices (clone/create), or upgrade ElevenLabs, or enable “Allow system voice if ElevenLabs fails”.",
            };
          }
          if (
            res.status === 400 &&
            /unsupported_model|deprecated/i.test(errText)
          ) {
            continue;
          }
          if (res.status === 404) {
            return { ok: false, detail: lastDetail, hasKey: true };
          }
          continue;
        }
        const buf = Buffer.from(await res.arrayBuffer());
        if (buf.length < 100) {
          lastDetail = "ElevenLabs returned empty audio";
          continue;
        }
        return {
          ok: true,
          mime: "audio/mpeg",
          base64: buf.toString("base64"),
          hasKey: true,
        };
      } catch (err) {
        lastDetail = err && err.message ? String(err.message) : String(err);
      }
    }
    return {
      ok: false,
      detail: lastDetail || "ElevenLabs TTS failed",
      hasKey: true,
    };
  }

  return { synthesizeElevenLabs };
}

module.exports = { createTtsService };
