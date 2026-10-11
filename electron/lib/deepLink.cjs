/**
 * `todonotifier://` links, which is how the companion sends someone here.
 *
 * The companion reads this app's tasks and can show them, but completing one
 * belongs to this app, so the most it can usefully do is bring this window up
 * at the right row. A link rather than IPC because the two are separate
 * processes from separate toolchains, and a URL is the one thing macOS will
 * route between them with no shared code — including launching this app when
 * it is not running.
 *
 * Anything unrecognised parses to null and is ignored: a link is input from
 * outside, and the worst it should be able to do is open the window.
 */

const SCHEME = "todonotifier";

/**
 * @param {string} url
 * @returns {{ kind: "task" | "project", id: string } | null}
 */
function parseDeepLink(url) {
  if (typeof url !== "string") return null;
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  if (parsed.protocol !== `${SCHEME}:`) return null;

  const kind = parsed.hostname;
  if (kind !== "task" && kind !== "project") return null;

  const id = parsed.searchParams.get("id");
  if (!id || id.length > 200) return null;
  return { kind, id };
}

module.exports = { SCHEME, parseDeepLink };
