const fs = require("fs");
const os = require("os");
const path = require("path");

/**
 * The companion's bundle identifier, which is what names its container.
 *
 * Hardcoded because it is the companion's own stable identity, set in
 * `TodoCompanion.xcodeproj`. There is no discovery API for another app's
 * container, and guessing by scanning `~/Library/Containers` would be a worse
 * kind of coupling than naming the one app we mean.
 */
const COMPANION_BUNDLE_ID = "surya.TodoCompanion";

/**
 * Where the companion publishes its project list.
 *
 * Inside its sandbox container, because that is the only place a sandboxed app
 * can write without prompting for a location. This app is not sandboxed, so it
 * can read there. Nothing here ever writes to it — the companion owns the
 * grouping, exactly as this app owns the tasks it reads back.
 */
function companionProjectsPath(homedir = os.homedir()) {
  return path.join(
    homedir,
    "Library/Containers",
    COMPANION_BUNDLE_ID,
    "Data/Library/Application Support/companion-projects.json"
  );
}

/**
 * Reads the published file into `{ projects, updatedAt }`.
 *
 * Every failure is the same answer: no projects. The companion may never have
 * been installed, may never have been run, and may be halfway through a write
 * — none of which is this app's problem, and none of which should stop the
 * to-do list from rendering.
 *
 * @param {string} raw
 */
function parseCompanionProjects(raw) {
  const empty = { projects: [], updatedAt: null };

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return empty;
  }

  if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.projects)) {
    return empty;
  }

  const projects = parsed.projects
    .filter(
      (item) =>
        item &&
        typeof item === "object" &&
        typeof item.id === "string" &&
        item.id !== "" &&
        typeof item.name === "string" &&
        item.name !== ""
    )
    .map((item) => ({
      id: item.id,
      name: item.name,
      // Only strings can match a task id, and the array is the whole reason
      // this file is read, so anything else in it is dropped rather than
      // carried through to a lookup that cannot succeed.
      todoIDs: Array.isArray(item.todoIDs)
        ? item.todoIDs.filter((id) => typeof id === "string" && id !== "")
        : [],
      savedContextCount:
        Number.isFinite(item.savedContextCount) && item.savedContextCount >= 0
          ? item.savedContextCount
          : 0,
    }));

  return {
    projects,
    updatedAt: typeof parsed.updatedAt === "string" ? parsed.updatedAt : null,
  };
}

/**
 * @param {string} [filePath]
 */
function loadCompanionProjects(filePath = companionProjectsPath()) {
  try {
    return parseCompanionProjects(fs.readFileSync(filePath, "utf8"));
  } catch {
    return { projects: [], updatedAt: null };
  }
}

module.exports = {
  COMPANION_BUNDLE_ID,
  companionProjectsPath,
  parseCompanionProjects,
  loadCompanionProjects,
};
