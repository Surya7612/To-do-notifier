import { useEffect } from "react";

/**
 * Brings reminders set in the macOS companion in as tasks.
 *
 * Runs on mount and whenever this window regains focus, on the same reasoning
 * as the project list: the companion is a separate process that can set a
 * reminder at any moment and has no way to tell this app that it did, and
 * coming back to this window is exactly when a stale list would be noticed.
 *
 * Holds no state of its own. The import happens in the main process, which owns
 * `app-data.json`, and the new tasks arrive through the same `data:changed`
 * broadcast as every other change — so the list updates by the normal route
 * rather than this hook having a second opinion about what the todos are.
 */
export function useCompanionTasks() {
  useEffect(() => {
    const runImport = () => {
      // Silent by design. The companion may not be installed, may never have
      // run, or may be midway through publishing, none of which is worth
      // putting in front of someone looking at their task list.
      void window.todoApi.companionImportTasks().catch(() => undefined);
    };

    runImport();
    window.addEventListener("focus", runImport);
    return () => window.removeEventListener("focus", runImport);
  }, []);
}
