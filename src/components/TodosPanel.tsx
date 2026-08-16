import { FormEvent, useMemo, useState } from "react";
import { v4 as uuid } from "uuid";
import type { AppData, TodoItem } from "../shared/types";
import { bumpTraining } from "../shared/types";
import { playSfx } from "../lib/sound";

function dueBadge(todo: TodoItem, leadMinutes: number) {
  if (todo.status === "done") return null;
  const due = new Date(todo.dueAt).getTime();
  const now = Date.now();
  if (due <= now) return <span className="badge overdue">Overdue</span>;
  if (due - now <= Math.max(1, leadMinutes) * 60_000)
    return <span className="badge due-soon">Due soon</span>;
  return null;
}

function formatDue(iso: string) {
  const d = new Date(iso);
  return d.toLocaleString([], {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

function defaultDueLocal() {
  const d = new Date();
  d.setHours(d.getHours() + 2, 0, 0, 0);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function TodosPanel({
  data,
  save,
}: {
  data: AppData;
  save: (d: AppData) => Promise<AppData>;
}) {
  const [title, setTitle] = useState("");
  const [dueLocal, setDueLocal] = useState(defaultDueLocal);
  const lead = data.settings.reminderLeadMinutes || 60;

  const sorted = useMemo(() => {
    return [...data.todos].sort((a, b) => {
      if (a.status !== b.status) return a.status === "open" ? -1 : 1;
      return new Date(a.dueAt).getTime() - new Date(b.dueAt).getTime();
    });
  }, [data.todos]);

  async function onAdd(e: FormEvent) {
    e.preventDefault();
    if (!title.trim()) return;
    const due = new Date(dueLocal);
    if (Number.isNaN(due.getTime())) return;
    const item: TodoItem = {
      id: uuid(),
      title: title.trim(),
      dueAt: due.toISOString(),
      status: "open",
      createdAt: new Date().toISOString(),
    };
    await save({ ...data, todos: [item, ...data.todos] });
    setTitle("");
    setDueLocal(defaultDueLocal());
  }

  async function toggle(id: string) {
    const before = data.todos.find((t) => t.id === id);
    const todos = data.todos.map((t) => {
      if (t.id !== id) return t;
      const nextStatus = t.status === "done" ? "open" : "done";
      return {
        ...t,
        status: nextStatus as TodoItem["status"],
        remindedAt: nextStatus === "open" ? undefined : t.remindedAt,
        overdueRemindedAt:
          nextStatus === "open" ? undefined : t.overdueRemindedAt,
      };
    });
    let next: AppData = { ...data, todos };
    if (before && before.status === "open") {
      next = bumpTraining(next, { todosDone: 1 });
      playSfx("done", data.settings.sfxEnabled);
    }
    await save(next);
  }

  async function remove(id: string) {
    await save({ ...data, todos: data.todos.filter((t) => t.id !== id) });
  }

  async function testNotify() {
    await window.todoApi.notify({
      title: "To-Do Notifier",
      body: "If you see this, reminders can reach you.",
    });
  }

  return (
    <div className="stack">
      <form className="panel stack" onSubmit={onAdd}>
        <div className="row">
          <div className="field">
            <label htmlFor="todo-title">Task</label>
            <input
              id="todo-title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Finish systems notes"
              autoFocus
            />
          </div>
          <div className="field" style={{ maxWidth: 240 }}>
            <label htmlFor="todo-due">Due</label>
            <input
              id="todo-due"
              type="datetime-local"
              value={dueLocal}
              onChange={(e) => setDueLocal(e.target.value)}
            />
          </div>
          <div style={{ alignSelf: "end" }}>
            <button className="btn" type="submit">
              Add
            </button>
          </div>
        </div>
        <div className="row" style={{ justifyContent: "space-between" }}>
          <p className="muted" style={{ margin: 0, fontSize: "0.85rem" }}>
            Reminder ~{lead}m before · overdue every{" "}
            {data.settings.overdueNagMinutes}m
          </p>
          <div className="row" style={{ gap: "0.4rem" }}>
            <button
              className="btn ghost"
              type="button"
              onClick={() => void testNotify()}
            >
              Test alert
            </button>
            {data.todos.some((t) => t.status === "done") && (
              <button
                className="btn ghost"
                type="button"
                onClick={() =>
                  void save({
                    ...data,
                    todos: data.todos.filter((t) => t.status === "open"),
                  })
                }
              >
                Clear done
              </button>
            )}
          </div>
        </div>
      </form>

      <div className="panel">
        {sorted.length === 0 ? (
          <div className="empty">No tasks yet.</div>
        ) : (
          <ul className="todo-list">
            {sorted.map((todo) => (
              <li
                key={todo.id}
                className={`todo-item ${todo.status === "done" ? "done" : ""}`}
              >
                <input
                  type="checkbox"
                  checked={todo.status === "done"}
                  onChange={() => void toggle(todo.id)}
                  aria-label={`Mark ${todo.title}`}
                />
                <div>
                  <div className="todo-title">{todo.title}</div>
                  <div className="todo-meta row" style={{ gap: "0.5rem" }}>
                    <span>{formatDue(todo.dueAt)}</span>
                    {dueBadge(todo, lead)}
                  </div>
                </div>
                <button
                  className="btn ghost"
                  type="button"
                  onClick={() => void remove(todo.id)}
                >
                  Delete
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
