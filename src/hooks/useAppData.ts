import { useCallback, useEffect, useState } from "react";
import type { AppData } from "../shared/types";
import { DEFAULT_DATA } from "../shared/types";

export function useAppData() {
  const [data, setData] = useState<AppData>(DEFAULT_DATA);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let alive = true;
    window.todoApi.getData().then((d) => {
      if (!alive) return;
      setData(d);
      setReady(true);
    });
    const off = window.todoApi.onDataChanged((d) => setData(d));
    return () => {
      alive = false;
      off();
    };
  }, []);

  const save = useCallback(async (next: AppData) => {
    setData(next);
    return window.todoApi.setData(next);
  }, []);

  /** Always merge against latest disk state to avoid tutor/notes races. */
  const saveMerge = useCallback(
    async (mutator: (latest: AppData) => AppData) => {
      const latest = await window.todoApi.getData();
      const next = mutator(latest);
      setData(next);
      return window.todoApi.setData(next);
    },
    []
  );

  return { data, ready, save, saveMerge, setData };
}
