import { useCallback, useEffect, useMemo, useState } from "react";
import type { CompanionProject } from "../shared/types";

/**
 * The macOS companion's project list, and which project each task is in.
 *
 * Re-read when this window regains focus rather than polled: the file only
 * changes when the user does something in the other app, and returning here is
 * exactly the moment the answer could be stale. Empty whenever the companion
 * is not installed, has never run, or has no projects — so nothing about this
 * list appears until there is something real to show.
 */
export function useCompanionProjects() {
  const [projects, setProjects] = useState<CompanionProject[]>([]);

  const refresh = useCallback(async () => {
    try {
      const result = await window.todoApi.companionProjects();
      setProjects(result?.projects ?? []);
    } catch {
      setProjects([]);
    }
  }, []);

  useEffect(() => {
    void refresh();
    const onFocus = () => void refresh();
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, [refresh]);

  /**
   * Nothing stops the companion putting one task in two projects, so the first
   * by name wins here. Showing two labels on one row would suggest this app
   * can resolve an ambiguity it has no say in.
   */
  const projectByTodoId = useMemo(() => {
    const map = new Map<string, CompanionProject>();
    for (const project of projects) {
      for (const id of project.todoIDs) {
        if (!map.has(id)) map.set(id, project);
      }
    }
    return map;
  }, [projects]);

  return { projects, projectByTodoId, refresh };
}
