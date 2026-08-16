import { useEffect, useMemo, useState } from "react";
import type { AppData, TodoItem } from "./shared/types";
import { DEFAULT_DATA } from "./shared/types";
import "./panel.css";

function formatDue(iso: string) {
  return new Date(iso).toLocaleTimeString([], {
    hour: "numeric",
    minute: "2-digit",
  });
}

export function PanelApp() {
  const [data, setData] = useState<AppData>(DEFAULT_DATA);

  useEffect(() => {
    void window.todoApi.getData().then(setData);
    return window.todoApi.onDataChanged(setData);
  }, []);

  const openTodos = useMemo(
    () =>
      data.todos
        .filter((t) => t.status === "open")
        .sort(
          (a, b) => new Date(a.dueAt).getTime() - new Date(b.dueAt).getTime()
        )
        .slice(0, 8),
    [data.todos]
  );

  return (
    <div
      className="panel-root"
      onMouseEnter={() => void window.todoApi.setPetHover(true)}
      onMouseLeave={() => void window.todoApi.setPetHover(false)}
    >
      <div className="panel-head">
        <strong>Today</strong>
        <button type="button" onClick={() => void window.todoApi.showMain()}>
          Open
        </button>
      </div>
      {openTodos.length === 0 ? (
        <p className="panel-empty">All clear. Nice.</p>
      ) : (
        <ul>
          {openTodos.map((t: TodoItem) => (
            <li key={t.id}>
              <span>{t.title}</span>
              <em>{formatDue(t.dueAt)}</em>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
