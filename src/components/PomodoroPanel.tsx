import { useEffect, useMemo, useRef, useState } from "react";
import type { AppData } from "../shared/types";
import { AmbientPlayer, type AmbientKind, playSfx } from "../lib/sound";

type Mode = "focus" | "break";

function pad(n: number) {
  return String(n).padStart(2, "0");
}

export function PomodoroPanel({
  data,
  save,
}: {
  data: AppData;
  save: (d: AppData) => Promise<AppData>;
}) {
  const ambient = useRef(new AmbientPlayer());
  const [mode, setMode] = useState<Mode>("focus");
  const [running, setRunning] = useState(false);
  const [secondsLeft, setSecondsLeft] = useState(
    data.settings.pomodoroMinutes * 60
  );
  const [ambientKind, setAmbientKind] = useState<AmbientKind | "off">(
    data.settings.ambientDefault === "off"
      ? "off"
      : (data.settings.ambientDefault as AmbientKind)
  );
  const [pulseOpen, setPulseOpen] = useState(false);
  const pulsedRef = useRef(false);
  const sessionStartTotal = useRef(data.settings.pomodoroMinutes * 60);

  const total = useMemo(() => {
    return (
      (mode === "focus"
        ? data.settings.pomodoroMinutes
        : data.settings.breakMinutes) * 60
    );
  }, [mode, data.settings.pomodoroMinutes, data.settings.breakMinutes]);

  useEffect(() => {
    const player = ambient.current;
    return () => {
      player.stop();
      void window.todoApi.setFocusActive(false);
      void window.todoApi.setTrayTimer("");
    };
  }, []);

  // Keep ambient locked to Start / Pause
  useEffect(() => {
    const player = ambient.current;
    if (!running || ambientKind === "off") {
      player.stop();
      return;
    }
    void player.start(ambientKind, ambientKind === "lofi" ? 0.07 : 0.09);
    return () => {
      player.stop();
    };
  }, [running, ambientKind]);

  useEffect(() => {
    if (!running) {
      void window.todoApi.setFocusActive(false);
      void window.todoApi.setTrayTimer("");
      return;
    }
    void window.todoApi.setFocusActive(mode === "focus");
    const id = window.setInterval(() => {
      setSecondsLeft((s) => {
        const next = s - 1;
        const mm = Math.floor(Math.max(0, next) / 60);
        const ss = Math.max(0, next) % 60;
        void window.todoApi.setTrayTimer(`${pad(mm)}:${pad(ss)}`);

        if (
          mode === "focus" &&
          data.settings.focusPulseEnabled &&
          !pulsedRef.current &&
          next <= Math.floor(sessionStartTotal.current / 2) &&
          next > 0
        ) {
          pulsedRef.current = true;
          setPulseOpen(true);
          playSfx("pulse", data.settings.sfxEnabled);
          void window.todoApi.focusPulse();
        }

        if (next <= 0) {
          window.clearInterval(id);
          setRunning(false);
          const finished = mode;
          playSfx("done", data.settings.sfxEnabled);
          void window.todoApi.pomodoroComplete(finished);
          if (finished === "focus") {
            void (async () => {
              const { bumpTraining } = await import("../shared/types");
              const latest = await window.todoApi.getData();
              await save(
                bumpTraining(latest, {
                  focusMinutes: latest.settings.pomodoroMinutes,
                })
              );
            })();
          }
          const nextMode: Mode = mode === "focus" ? "break" : "focus";
          setMode(nextMode);
          pulsedRef.current = false;
          const mins =
            nextMode === "focus"
              ? data.settings.pomodoroMinutes
              : data.settings.breakMinutes;
          sessionStartTotal.current = mins * 60;
          return mins * 60;
        }
        return next;
      });
    }, 1000);
    return () => window.clearInterval(id);
  }, [running, mode, data, save]);

  async function setAmbient(kind: AmbientKind | "off") {
    setAmbientKind(kind);
    // playback is driven by running + ambientKind effect
  }

  function reset() {
    setRunning(false);
    pulsedRef.current = false;
    setPulseOpen(false);
    setSecondsLeft(total);
    sessionStartTotal.current = total;
  }

  function switchMode(next: Mode) {
    setMode(next);
    setRunning(false);
    pulsedRef.current = false;
    setPulseOpen(false);
    const mins =
      (next === "focus"
        ? data.settings.pomodoroMinutes
        : data.settings.breakMinutes) * 60;
    setSecondsLeft(mins);
    sessionStartTotal.current = mins;
  }

  function start() {
    if (!running) {
      sessionStartTotal.current = secondsLeft;
      pulsedRef.current = secondsLeft < sessionStartTotal.current / 2;
    }
    setRunning(true);
    playSfx("ping", data.settings.sfxEnabled);
  }

  const mm = Math.floor(secondsLeft / 60);
  const ss = secondsLeft % 60;
  const progress = 1 - secondsLeft / Math.max(1, total);

  return (
    <div className="panel stack" style={{ alignItems: "center" }}>
      <div className="row">
        <button
          type="button"
          className={`tab ${mode === "focus" ? "active" : ""}`}
          onClick={() => switchMode("focus")}
        >
          Focus
        </button>
        <button
          type="button"
          className={`tab ${mode === "break" ? "active" : ""}`}
          onClick={() => switchMode("break")}
        >
          Break
        </button>
      </div>

      <div className="timer-display">
        {pad(mm)}:{pad(ss)}
      </div>

      <div
        style={{
          width: "min(420px, 100%)",
          height: 8,
          borderRadius: 999,
          background: "rgba(255,255,255,0.08)",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            width: `${Math.max(0, Math.min(1, progress)) * 100}%`,
            height: "100%",
            background: "linear-gradient(90deg, #ff6a3d, #ffc14a)",
          }}
        />
      </div>

      <div className="row" style={{ marginTop: "0.5rem" }}>
        <button
          className="btn"
          type="button"
          onClick={() => (running ? setRunning(false) : start())}
        >
          {running ? "Pause" : "Start"}
        </button>
        <button className="btn secondary" type="button" onClick={reset}>
          Reset
        </button>
      </div>

      <div className="row" style={{ flexWrap: "wrap", justifyContent: "center" }}>
        {(
          [
            ["off", "Off"],
            ["pink", "Pink"],
            ["brown", "Brown"],
            ["rain", "Rain"],
            ["cafe", "Café"],
            ["lofi", "Lo-fi"],
          ] as const
        ).map(([k, label]) => (
          <button
            key={k}
            type="button"
            className={`tab ${ambientKind === k ? "active" : ""}`}
            onClick={() => void setAmbient(k)}
          >
            {label}
          </button>
        ))}
      </div>

      {pulseOpen && (
        <div className="quiz-box" style={{ width: "min(420px, 100%)" }}>
          <strong>Focus Pulse</strong>
          <p className="muted" style={{ margin: "0.35rem 0 0.6rem" }}>
            Still on the task, or did you drift?
          </p>
          <div className="row">
            <button
              className="btn"
              type="button"
              onClick={() => {
                setPulseOpen(false);
                playSfx("ping", data.settings.sfxEnabled);
              }}
            >
              Still focused
            </button>
            <button
              className="btn secondary"
              type="button"
              onClick={() => {
                setPulseOpen(false);
                setRunning(false);
              }}
            >
              Drifted — pause
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
