import { useEffect, useState } from "react";
import { useAppData } from "./hooks/useAppData";
import { TodosPanel } from "./components/TodosPanel";
import { PomodoroPanel } from "./components/PomodoroPanel";
import { NotesPanel } from "./components/NotesPanel";
import { TutoringPanel } from "./components/TutoringPanel";
import { ReviewPanel } from "./components/ReviewPanel";
import { ProgressPanel } from "./components/ProgressPanel";
import { SettingsPanel } from "./components/SettingsPanel";
import { WakeListener } from "./components/WakeListener";
import { VoiceStatusBadge } from "./components/VoiceStatusBadge";
import { voiceController } from "./lib/voiceController";
import packageJson from "../package.json";
import "./styles.css";

type Tab =
  | "todos"
  | "pomodoro"
  | "notes"
  | "tutor"
  | "review"
  | "progress"
  | "settings";

const TABS: { id: Tab; label: string }[] = [
  { id: "todos", label: "Todos" },
  { id: "pomodoro", label: "Focus" },
  { id: "notes", label: "Notes" },
  { id: "tutor", label: "Tutor" },
  { id: "review", label: "Review" },
  { id: "progress", label: "Training" },
  { id: "settings", label: "Settings" },
];

export default function App() {
  const { data, ready, save, saveMerge } = useAppData();
  const [tab, setTab] = useState<Tab>("todos");
  const autoListen = Boolean(ready && data.settings.wakeWordEnabled);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "g") {
        e.preventDefault();
        void voiceController.startConversation();
        return;
      }
      if (e.key === "Escape") {
        const mode = voiceController.getStatus().mode;
        if (mode === "awake" || mode === "dictate") {
          e.preventDefault();
          voiceController.goStandby();
        }
      }
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, []);

  return (
    <div className="app-shell">
      <WakeListener autoListen={autoListen} />
      {!ready ? (
        <div className="empty">Loading…</div>
      ) : (
        <>
          <header className="topbar">
            <div className="brand-cluster">
              <div className="brand">
                <strong>To-Do Notifier</strong>
                <span>
                  v{packageJson.version} ·{" "}
                  {data.todos.filter((t) => t.status === "open").length} open ·
                  streak {data.streak}
                  {data.flashcards.filter(
                    (c) => new Date(c.dueAt).getTime() <= Date.now()
                  ).length
                    ? ` · ${
                        data.flashcards.filter(
                          (c) => new Date(c.dueAt).getTime() <= Date.now()
                        ).length
                      } due`
                    : ""}
                </span>
              </div>
              <VoiceStatusBadge />
              <button
                type="button"
                className="btn secondary"
                style={{ padding: "0.25rem 0.65rem", fontSize: "0.8rem" }}
                title="Start conversation (⌘G)"
                onClick={() => void voiceController.startConversation()}
              >
                ⌘G Talk
              </button>
            </div>
            <nav className="tabs">
              {TABS.map((t) => (
                <button
                  key={t.id}
                  type="button"
                  className={`tab ${tab === t.id ? "active" : ""}`}
                  onClick={() => setTab(t.id)}
                >
                  {t.label}
                </button>
              ))}
            </nav>
          </header>
          <main className="content">
            {tab === "todos" && <TodosPanel data={data} save={save} />}
            {tab === "pomodoro" && <PomodoroPanel data={data} save={save} />}
            {tab === "notes" && <NotesPanel data={data} save={save} />}
            {tab === "tutor" && (
              <TutoringPanel data={data} save={save} saveMerge={saveMerge} />
            )}
            {tab === "review" && <ReviewPanel data={data} save={save} />}
            {tab === "progress" && <ProgressPanel data={data} save={save} />}
            {tab === "settings" && <SettingsPanel data={data} save={save} />}
          </main>
        </>
      )}
    </div>
  );
}
