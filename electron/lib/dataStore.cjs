const fs = require("fs");
const path = require("path");
const { DEFAULT_SETTINGS, DEFAULT_DATA } = require("./defaults.cjs");

/**
 * JSON-file persistence for app data, rooted at Electron's userData path.
 * @param {{ app: Electron.App }} deps
 */
function createDataStore({ app }) {
  const dataPath = () => path.join(app.getPath("userData"), "app-data.json");

  function saveData(data) {
    fs.mkdirSync(path.dirname(dataPath()), { recursive: true });
    fs.writeFileSync(dataPath(), JSON.stringify(data, null, 2), "utf8");
  }

  function loadData() {
    try {
      const raw = fs.readFileSync(dataPath(), "utf8");
      const parsed = JSON.parse(raw);
      const settings = { ...DEFAULT_SETTINGS, ...parsed.settings };
      let migrated = false;
      // One-time migrate: old default was patrol auto-dash across the whole screen
      if (settings.petBehaviorVersion == null) {
        if (settings.companionMode === "patrol") settings.companionMode = "corner";
        settings.petBehaviorVersion = 2;
        migrated = true;
      }
      // v3: hotkey voice (⌘G / Esc / Dictate button); wake word opt-in, default off
      if (settings.petBehaviorVersion < 3) {
        settings.wakeWordEnabled = false;
        settings.petBehaviorVersion = 3;
        migrated = true;
      }
      if (migrated) {
        try {
          const fixed = {
            todos: parsed.todos ?? [],
            notes: parsed.notes ?? [],
            flashcards: parsed.flashcards ?? [],
            training: parsed.training ?? [],
            settings,
            streak: parsed.streak ?? 0,
            longestStreak: parsed.longestStreak ?? 0,
            lastActiveDate: parsed.lastActiveDate,
            dayPlan: parsed.dayPlan,
            lastRecapDate: parsed.lastRecapDate,
          };
          saveData(fixed);
        } catch {
          /* ignore */
        }
      }
      return {
        todos: parsed.todos ?? [],
        notes: parsed.notes ?? [],
        flashcards: parsed.flashcards ?? [],
        training: parsed.training ?? [],
        settings,
        streak: parsed.streak ?? 0,
        longestStreak: parsed.longestStreak ?? 0,
        lastActiveDate: parsed.lastActiveDate,
        dayPlan: parsed.dayPlan,
        lastRecapDate: parsed.lastRecapDate,
      };
    } catch {
      return structuredClone(DEFAULT_DATA);
    }
  }

  return { loadData, saveData, dataPath, DEFAULT_SETTINGS, DEFAULT_DATA };
}

module.exports = { createDataStore };
