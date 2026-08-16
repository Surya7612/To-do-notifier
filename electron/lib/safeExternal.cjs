/**
 * Safe external URL opening for Electron (scheme allowlist).
 */

const ALLOWED = new Set([
  "https:",
  "http:",
  "mailto:",
  "x-apple.systempreferences:",
]);

/**
 * @param {unknown} raw
 * @returns {{ ok: true, url: string } | { ok: false, detail: string }}
 */
function validateExternalUrl(raw) {
  const s = String(raw || "").trim();
  if (!s || s.length > 2048) {
    return { ok: false, detail: "Invalid URL" };
  }
  let parsed;
  try {
    parsed = new URL(s);
  } catch {
    return { ok: false, detail: "Invalid URL" };
  }
  if (!ALLOWED.has(parsed.protocol)) {
    return { ok: false, detail: `Blocked scheme: ${parsed.protocol}` };
  }
  // Block file: and javascript: already by scheme; also block credentials tricks
  if (parsed.username || parsed.password) {
    return { ok: false, detail: "URLs with credentials are blocked" };
  }
  return { ok: true, url: parsed.toString() };
}

/**
 * @param {typeof import('electron').shell} shell
 * @param {unknown} raw
 */
async function openExternalSafe(shell, raw) {
  const v = validateExternalUrl(raw);
  if (!v.ok) return v;
  try {
    await shell.openExternal(v.url);
    return { ok: true, url: v.url };
  } catch (err) {
    return {
      ok: false,
      detail: err && err.message ? String(err.message) : String(err),
    };
  }
}

module.exports = { validateExternalUrl, openExternalSafe, ALLOWED };
