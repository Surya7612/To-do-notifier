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
  const empty = { projects: [], requestedTasks: [], updatedAt: null };

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
    requestedTasks: parseRequestedTasks(parsed.requestedTasks),
    updatedAt: typeof parsed.updatedAt === "string" ? parsed.updatedAt : null,
  };
}

/**
 * Reminders the companion is offering as tasks.
 *
 * Absent from older versions of the file, so a missing or malformed list is an
 * empty one rather than a reason to reject the projects alongside it. Every
 * field is required: a request with no title would become a blank row in the
 * task list, and one with no id could not be imported twice without
 * duplicating, which is the whole basis of the contract.
 *
 * @param {unknown} value
 */
function parseRequestedTasks(value) {
  if (!Array.isArray(value)) return [];

  return value
    .filter(
      (item) =>
        item &&
        typeof item === "object" &&
        typeof item.id === "string" &&
        item.id !== "" &&
        typeof item.title === "string" &&
        item.title.trim() !== "" &&
        typeof item.dueAt === "string" &&
        !Number.isNaN(Date.parse(item.dueAt))
    )
    .map((item) => ({
      id: item.id,
      title: item.title.trim(),
      dueAt: item.dueAt,
    }));
}

/**
 * @param {string} [filePath]
 */
function loadCompanionProjects(filePath = companionProjectsPath()) {
  try {
    return parseCompanionProjects(fs.readFileSync(filePath, "utf8"));
  } catch {
    return { projects: [], requestedTasks: [], updatedAt: null };
  }
}

/**
 * The copy next to this app's own store, plus the companion's container file.
 *
 * The container used to be enough. Current macOS returns EPERM when this
 * process opens another app's container, which is why a reminder reached
 * Apple Reminders (the companion writes EventKit itself) and never became a
 * row here. Max now also writes beside `app-data.json`. Prefer the newer of
 * the two so an older leftover cannot hide a fresh request.
 *
 * @param {string[]} filePaths
 */
function loadNewestCompanionProjects(filePaths) {
  const empty = { projects: [], requestedTasks: [], updatedAt: null };
  let best = empty;
  let bestTime = Number.NEGATIVE_INFINITY;

  for (const filePath of filePaths || []) {
    const parsed = loadCompanionProjects(filePath);
    const stamp = parsed.updatedAt ? Date.parse(parsed.updatedAt) : Number.NaN;
    const time = Number.isNaN(stamp) ? Number.NEGATIVE_INFINITY : stamp;
    if (time < bestTime) continue;
    if (time === bestTime
        && parsed.requestedTasks.length === 0
        && parsed.projects.length === 0) {
      continue;
    }
    best = parsed;
    bestTime = time;
  }

  return best;
}

/**
 * Where Max also publishes, once the to-do app has been linked.
 *
 * @param {string} userDataDir `app.getPath("userData")`
 */
function localCompanionProjectsPath(userDataDir) {
  return path.join(userDataDir, "companion-projects.json");
}

/**
 * Calls `onChange` shortly after the companion republishes.
 *
 * The 30-second tick alone meant a reminder set in the companion took up to
 * half a minute to appear here — long enough, said aloud in front of someone,
 * to look like it had not worked. The tick stays as the fallback: this watches
 * the *directory*, because the companion writes atomically by replacing the
 * file, and a watch on the file itself stops firing after the first replace.
 *
 * Absent directory (the companion never installed or never run) is not an
 * error, just no watch. Returns a function that stops watching.
 *
 * @param {() => void} onChange
 * @param {{ filePath?: string, debounceMs?: number, watch?: typeof fs.watch }} [options]
 */
function watchCompanionProjects(onChange, options = {}) {
  const filePath = options.filePath || companionProjectsPath();
  const debounceMs = options.debounceMs ?? 300;
  const watch = options.watch || fs.watch;
  const name = path.basename(filePath);

  let timer = null;
  let watcher;
  try {
    watcher = watch(path.dirname(filePath), (_event, changed) => {
      // Some platforms omit the name; treat that as possibly ours.
      if (changed && changed.toString() !== name) return;
      // One save produces several events (temp file, rename); act once.
      clearTimeout(timer);
      timer = setTimeout(onChange, debounceMs);
    });
    watcher.on?.("error", () => {});
  } catch {
    return () => {};
  }

  return () => {
    clearTimeout(timer);
    try {
      watcher.close();
    } catch {
      /* already closed */
    }
  };
}

module.exports = {
  companionProjectsPath,
  localCompanionProjectsPath,
  parseCompanionProjects,
  loadCompanionProjects,
  loadNewestCompanionProjects,
  watchCompanionProjects,
};
