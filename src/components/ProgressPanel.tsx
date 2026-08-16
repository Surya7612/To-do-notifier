import { useMemo, useState } from "react";
import type { AppData } from "../shared/types";
import { bumpTraining, todayKey } from "../shared/types";
import { playSfx } from "../lib/sound";

export function ProgressPanel({
  data,
  save,
}: {
  data: AppData;
  save: (d: AppData) => Promise<AppData>;
}) {
  const today = data.training.find((t) => t.date === todayKey());
  const [planBusy, setPlanBusy] = useState(false);
  const [recap, setRecap] = useState("");
  const [error, setError] = useState<string | null>(null);

  const weekMins = useMemo(() => {
    const cut = new Date();
    cut.setDate(cut.getDate() - 6);
    const key = todayKey(cut);
    return data.training
      .filter((t) => t.date >= key)
      .reduce((s, t) => s + t.focusMinutes, 0);
  }, [data.training]);

  async function makePlan() {
    setPlanBusy(true);
    setError(null);
    try {
      const open = data.todos.filter((t) => t.status === "open");
      let lines: string[] = [];
      if (open.length === 0) {
        lines = ["No open todos — pick one stretch goal or review flashcards."];
      } else {
        try {
          const content = await window.todoApi.ollamaChat({
            system:
              "You are Goku making a short daily training plan. Return 3-5 bullet lines only. Prioritize due-soon work. Energetic but concise.",
            prompt: open
              .map(
                (t) =>
                  `- ${t.title} (due ${new Date(t.dueAt).toLocaleString()})`
              )
              .join("\n"),
          });
          lines = content
            .split("\n")
            .map((l) => l.replace(/^[-*•\d.)\s]+/, "").trim())
            .filter(Boolean)
            .slice(0, 6);
        } catch {
          lines = open
            .slice()
            .sort(
              (a, b) =>
                new Date(a.dueAt).getTime() - new Date(b.dueAt).getTime()
            )
            .slice(0, 5)
            .map((t) => t.title);
        }
      }
      await save({
        ...data,
        dayPlan: {
          date: todayKey(),
          lines,
          createdAt: new Date().toISOString(),
        },
      });
      playSfx("power", data.settings.sfxEnabled);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setPlanBusy(false);
    }
  }

  async function makeRecap() {
    setPlanBusy(true);
    setError(null);
    try {
      const done = data.todos.filter((t) => t.status === "done").length;
      const open = data.todos.filter((t) => t.status === "open").length;
      const overdue = data.todos.filter(
        (t) => t.status === "open" && new Date(t.dueAt).getTime() < Date.now()
      ).length;
      const stats = `Focus minutes today: ${today?.focusMinutes ?? 0}. Todos done: ${done}. Open: ${open}. Overdue: ${overdue}. Streak: ${data.streak}.`;
      let text = stats;
      try {
        text = await window.todoApi.ollamaChat({
          system:
            "You are Goku giving a 3-sentence evening training recap. Warm, playful, honest. No markdown.",
          prompt: stats,
        });
      } catch {
        text = `${stats} Rematch tomorrow — even Super Saiyans rest.`;
      }
      setRecap(text.trim());
      await save({
        ...bumpTraining(data, {}),
        lastRecapDate: todayKey(),
      });
      playSfx("done", data.settings.sfxEnabled);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setPlanBusy(false);
    }
  }

  const plan =
    data.dayPlan?.date === todayKey() ? data.dayPlan : undefined;

  return (
    <div className="stack">
      <div className="panel stack">
        <strong>Training log</strong>
        <div className="row">
          <span className="status-pill">
            Streak <strong style={{ marginLeft: 4 }}>{data.streak}</strong>
          </span>
          <span className="status-pill">
            Best <strong style={{ marginLeft: 4 }}>{data.longestStreak}</strong>
          </span>
          <span className="status-pill">
            Week focus <strong style={{ marginLeft: 4 }}>{weekMins}m</strong>
          </span>
        </div>
        <p className="muted" style={{ margin: 0 }}>
          Today — focus {today?.focusMinutes ?? 0}m · todos{" "}
          {today?.todosDone ?? 0} · tutor {today?.tutorSessions ?? 0} · cards{" "}
          {today?.cardsReviewed ?? 0}
        </p>
      </div>

      <div className="panel stack">
        <div className="row" style={{ justifyContent: "space-between" }}>
          <strong>Today&apos;s plan</strong>
          <button
            className="btn secondary"
            type="button"
            disabled={planBusy}
            onClick={() => void makePlan()}
          >
            {plan ? "Refresh plan" : "Make plan"}
          </button>
        </div>
        {plan ? (
          <ul className="todo-list">
            {plan.lines.map((line, i) => (
              <li key={i} className="todo-item" style={{ gridTemplateColumns: "1fr" }}>
                <div className="todo-title">{line}</div>
              </li>
            ))}
          </ul>
        ) : (
          <p className="muted" style={{ margin: 0 }}>
            Morning move: generate a short plan from open todos.
          </p>
        )}
      </div>

      <div className="panel stack">
        <div className="row" style={{ justifyContent: "space-between" }}>
          <strong>Evening recap</strong>
          <button
            className="btn secondary"
            type="button"
            disabled={planBusy}
            onClick={() => void makeRecap()}
          >
            Recap with Goku
          </button>
        </div>
        {recap ? (
          <p style={{ whiteSpace: "pre-wrap", margin: 0 }}>{recap}</p>
        ) : (
          <p className="muted" style={{ margin: 0 }}>
            End the day with a 30-second debrief.
          </p>
        )}
        {error && <p style={{ color: "var(--danger)", margin: 0 }}>{error}</p>}
      </div>
    </div>
  );
}
