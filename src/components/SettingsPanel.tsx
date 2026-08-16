import { useEffect, useState } from "react";
import type { AppData, AppSettings, CompanionMode } from "../shared/types";

type HealthChecks = Record<string, { ok: boolean; detail?: string }>;

export function SettingsPanel({
  data,
  save,
}: {
  data: AppData;
  save: (d: AppData) => Promise<AppData>;
}) {
  const s = data.settings;
  const [voices, setVoices] = useState<SpeechSynthesisVoice[]>([]);
  const [healthBusy, setHealthBusy] = useState(false);
  const [healthReady, setHealthReady] = useState<boolean | null>(null);
  const [healthChecks, setHealthChecks] = useState<HealthChecks>({});
  const [healthMsg, setHealthMsg] = useState("");

  useEffect(() => {
    const load = () => {
      const list = window.speechSynthesis?.getVoices?.() || [];
      setVoices(list.filter((v) => /^en/i.test(v.lang) || !v.lang));
    };
    load();
    window.speechSynthesis?.addEventListener?.("voiceschanged", load);
    return () => {
      window.speechSynthesis?.removeEventListener?.("voiceschanged", load);
    };
  }, []);

  async function patch(partial: Partial<AppSettings>) {
    await save({
      ...data,
      settings: { ...data.settings, ...partial },
    });
  }

  async function runHealth() {
    setHealthBusy(true);
    setHealthMsg("");
    try {
      const res = await window.todoApi.appHealth();
      setHealthReady(res.ready);
      setHealthChecks(res.checks || {});
      setHealthMsg(
        res.ready
          ? "All systems go — ready for daily use."
          : "Fix the red items below, then run check again."
      );
      if (res.checks?.elevenlabs?.ok) {
        void window.todoApi.petSpeak("Power up.");
      }
    } catch (e) {
      setHealthReady(false);
      setHealthMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setHealthBusy(false);
    }
  }

  return (
    <div className="stack">
      <div className="panel stack">
        <strong>Readiness</strong>
        <p className="muted" style={{ margin: 0, fontSize: "0.85rem" }}>
          Run this once. It checks mic, OpenAI, ElevenLabs, Ollama, and
          notifications.
        </p>
        <div className="row" style={{ flexWrap: "wrap", gap: "0.5rem" }}>
          <button
            type="button"
            className="btn"
            disabled={healthBusy}
            onClick={() => void runHealth()}
          >
            {healthBusy ? "Checking…" : "Run full check"}
          </button>
          <button
            type="button"
            className="btn secondary"
            onClick={() => void window.todoApi.petSpeak("Hey — ElevenLabs check.")}
          >
            Test Goku voice
          </button>
          <button
            type="button"
            className="btn secondary"
            onClick={() =>
              void window.todoApi.notify({
                title: "To-Do Notifier",
                body: "Test alert — reminders can reach you.",
              })
            }
          >
            Test notification
          </button>
          <button
            type="button"
            className="btn secondary"
            onClick={() => void window.todoApi.openMicSettings()}
          >
            Mic settings
          </button>
        </div>
        {healthMsg && (
          <p style={{ margin: 0, fontWeight: 600 }}>
            {healthReady === true ? "✓ " : healthReady === false ? "✗ " : ""}
            {healthMsg}
          </p>
        )}
        {Object.keys(healthChecks).length > 0 && (
          <ul style={{ margin: 0, paddingLeft: "1.1rem", fontSize: "0.9rem" }}>
            {Object.entries(healthChecks).map(([name, c]) => (
              <li key={name} style={{ color: c.ok ? "#8fdf8f" : "#f0a0a0" }}>
                {c.ok ? "OK" : "FIX"} · {name}: {c.detail || ""}
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="panel stack">
        <strong>Voice</strong>
        <p className="muted" style={{ margin: 0, fontSize: "0.85rem" }}>
          <strong>⌘G</strong> starts conversation · <strong>Esc</strong> stops
          it · Tutor <strong>Dictate</strong> button for notes. Mic stays off
          until you ask (unless wake word is enabled below).
        </p>
        <div className="field">
          <label htmlFor="openai">OpenAI API key (listening)</label>
          <input
            id="openai"
            type="password"
            autoComplete="off"
            placeholder="sk-…"
            value={s.openaiApiKey || ""}
            onChange={(e) => void patch({ openaiApiKey: e.target.value.trim() })}
          />
        </div>
        <div className="field">
          <label htmlFor="stt-model">Listening model</label>
          <select
            id="stt-model"
            value={s.openaiTranscribeModel || "auto"}
            onChange={(e) =>
              void patch({
                openaiTranscribeModel: e.target.value as AppSettings["openaiTranscribeModel"],
              })
            }
          >
            <option value="auto">Auto (best → Whisper fallback)</option>
            <option value="gpt-4o-mini-transcribe">gpt-4o-mini-transcribe</option>
            <option value="whisper-1">whisper-1 only</option>
          </select>
        </div>
        <div className="field">
          <label htmlFor="eleven">ElevenLabs API key (Goku speak)</label>
          <input
            id="eleven"
            type="password"
            autoComplete="off"
            placeholder="Paste your ElevenLabs API key"
            value={s.elevenLabsApiKey || ""}
            onChange={(e) =>
              void patch({ elevenLabsApiKey: e.target.value.trim() })
            }
          />
        </div>
        <div className="field">
          <label htmlFor="eleven-voice">ElevenLabs voice ID</label>
          <input
            id="eleven-voice"
            value={s.elevenLabsVoiceId || "zYcjlYFOd3taleS0gkk3"}
            onChange={(e) =>
              void patch({ elevenLabsVoiceId: e.target.value.trim() })
            }
          />
        </div>
        <label className="row" style={{ gap: "0.5rem" }}>
          <input
            type="checkbox"
            checked={s.allowSystemVoiceFallback !== false}
            onChange={(e) =>
              void patch({ allowSystemVoiceFallback: e.target.checked })
            }
          />
          Prefer system voice when ElevenLabs is unavailable (recommended)
        </label>
        <div className="field">
          <label htmlFor="goku-voice">System voice fallback</label>
          <select
            id="goku-voice"
            value={s.gokuVoiceURI || ""}
            onChange={(e) => void patch({ gokuVoiceURI: e.target.value })}
          >
            <option value="">Auto</option>
            {voices.map((v) => (
              <option key={v.voiceURI} value={v.voiceURI}>
                {v.name} ({v.lang})
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label htmlFor="goku-rate">Voice speed</label>
          <input
            id="goku-rate"
            type="number"
            min={0.85}
            max={1.25}
            step={0.05}
            value={s.gokuVoiceRate ?? 1.02}
            onChange={(e) =>
              void patch({ gokuVoiceRate: Number(e.target.value) || 1.02 })
            }
          />
        </div>
      </div>

      <div className="panel stack">
        <strong>Reminders</strong>
        <div className="row">
          <div className="field">
            <label htmlFor="lead">Lead time (min)</label>
            <input
              id="lead"
              type="number"
              min={5}
              max={240}
              value={s.reminderLeadMinutes}
              onChange={(e) =>
                void patch({ reminderLeadMinutes: Number(e.target.value) || 60 })
              }
            />
          </div>
          <div className="field">
            <label htmlFor="nag">Overdue nag (min)</label>
            <input
              id="nag"
              type="number"
              min={5}
              max={240}
              value={s.overdueNagMinutes}
              onChange={(e) =>
                void patch({ overdueNagMinutes: Number(e.target.value) || 30 })
              }
            />
          </div>
          <div className="field">
            <label htmlFor="tone">Reminder tone</label>
            <select
              id="tone"
              value={s.momTone}
              onChange={(e) =>
                void patch({ momTone: e.target.value as AppSettings["momTone"] })
              }
            >
              <option value="playful">Playful</option>
              <option value="gentle">Gentle</option>
              <option value="strict">Strict</option>
            </select>
          </div>
        </div>
        <label className="row" style={{ gap: "0.5rem" }}>
          <input
            type="checkbox"
            checked={s.quietHoursEnabled}
            onChange={(e) => void patch({ quietHoursEnabled: e.target.checked })}
          />
          Quiet hours
        </label>
        {s.quietHoursEnabled && (
          <div className="row">
            <div className="field">
              <label htmlFor="qh-start">From</label>
              <input
                id="qh-start"
                type="number"
                min={0}
                max={23}
                value={s.quietHoursStart}
                onChange={(e) =>
                  void patch({ quietHoursStart: Number(e.target.value) || 0 })
                }
              />
            </div>
            <div className="field">
              <label htmlFor="qh-end">Until</label>
              <input
                id="qh-end"
                type="number"
                min={0}
                max={23}
                value={s.quietHoursEnd}
                onChange={(e) =>
                  void patch({ quietHoursEnd: Number(e.target.value) || 0 })
                }
              />
            </div>
          </div>
        )}
        <label className="row" style={{ gap: "0.5rem" }}>
          <input
            type="checkbox"
            checked={s.softBlockDuringFocus}
            onChange={(e) =>
              void patch({ softBlockDuringFocus: e.target.checked })
            }
          />
          Pause upcoming reminders during focus (does not block other apps)
        </label>
      </div>

      <div className="panel stack">
        <strong>Focus & tutor</strong>
        <div className="row">
          <div className="field">
            <label htmlFor="focus">Pomodoro (min)</label>
            <input
              id="focus"
              type="number"
              min={1}
              max={120}
              value={s.pomodoroMinutes}
              onChange={(e) =>
                void patch({ pomodoroMinutes: Number(e.target.value) || 25 })
              }
            />
          </div>
          <div className="field">
            <label htmlFor="break">Break (min)</label>
            <input
              id="break"
              type="number"
              min={1}
              max={60}
              value={s.breakMinutes}
              onChange={(e) =>
                void patch({ breakMinutes: Number(e.target.value) || 5 })
              }
            />
          </div>
          <div className="field">
            <label htmlFor="model">Ollama</label>
            <input
              id="model"
              value={s.ollamaModel}
              onChange={(e) => void patch({ ollamaModel: e.target.value.trim() })}
            />
          </div>
        </div>
        <label className="row" style={{ gap: "0.5rem" }}>
          <input
            type="checkbox"
            checked={s.focusPulseEnabled}
            onChange={(e) => void patch({ focusPulseEnabled: e.target.checked })}
          />
          Focus Pulse
        </label>
        <label className="row" style={{ gap: "0.5rem" }}>
          <input
            type="checkbox"
            checked={s.socraticDefault}
            onChange={(e) => void patch({ socraticDefault: e.target.checked })}
          />
          Socratic by default
        </label>
        <label className="row" style={{ gap: "0.5rem" }}>
          <input
            type="checkbox"
            checked={s.sfxEnabled}
            onChange={(e) => void patch({ sfxEnabled: e.target.checked })}
          />
          SFX
        </label>
      </div>

      <div className="panel stack">
        <strong>Companion behavior</strong>
        <div className="field">
          <label htmlFor="mode">Goku mode</label>
          <select
            id="mode"
            value={s.companionMode}
            onChange={(e) =>
              void patch({
                companionMode: e.target.value as CompanionMode,
              })
            }
          >
            <option value="corner">Corner idle (default)</option>
            <option value="patrol">Patrol (top-band auto dash)</option>
            <option value="bodyDouble">Body double (stay nearby + nudges)</option>
            <option value="perchTop">Perch top of screen</option>
            <option value="perchBottom">Perch near Dock</option>
          </select>
        </div>
        <div className="field">
          <label htmlFor="corner">Corner side</label>
          <select
            id="corner"
            value={s.petCorner || "right"}
            onChange={(e) =>
              void patch({
                petCorner: e.target.value as "left" | "right",
              })
            }
          >
            <option value="right">Top-right</option>
            <option value="left">Top-left</option>
          </select>
        </div>
        <label className="row" style={{ gap: "0.5rem" }}>
          <input
            type="checkbox"
            checked={Boolean(s.wakeWordEnabled)}
            onChange={(e) => void patch({ wakeWordEnabled: e.target.checked })}
          />
          Always listen for “Hey Goku” (optional — mic stays on)
        </label>
        <label className="row" style={{ gap: "0.5rem" }}>
          <input
            type="checkbox"
            checked={s.alwaysOnCompanion !== false}
            onChange={(e) => {
              const on = e.target.checked;
              void patch({
                alwaysOnCompanion: on,
                launchAtLogin: on ? true : s.launchAtLogin,
              });
            }}
          />
          Menu-bar companion
        </label>
        <label className="row" style={{ gap: "0.5rem" }}>
          <input
            type="checkbox"
            checked={Boolean(s.launchAtLogin)}
            disabled={s.alwaysOnCompanion !== false}
            onChange={(e) => void patch({ launchAtLogin: e.target.checked })}
          />
          Launch at login
          {s.alwaysOnCompanion !== false ? " (on with companion)" : ""}
        </label>
        <label className="row" style={{ gap: "0.5rem" }}>
          <input
            type="checkbox"
            checked={s.hideDockIcon}
            onChange={(e) => void patch({ hideDockIcon: e.target.checked })}
          />
          Hide Dock icon
        </label>
        {s.companionMode === "bodyDouble" && (
          <div className="field">
            <label htmlFor="nudge">Nudge every (min)</label>
            <input
              id="nudge"
              type="number"
              min={2}
              max={30}
              value={s.bodyDoubleNudgeMinutes}
              onChange={(e) =>
                void patch({
                  bodyDoubleNudgeMinutes: Number(e.target.value) || 8,
                })
              }
            />
          </div>
        )}
        <div className="row">
          <button
            className="btn secondary"
            type="button"
            onClick={() => void window.todoApi.setPetVisible(!s.petVisible)}
          >
            {s.petVisible ? "Hide Goku" : "Show Goku"}
          </button>
        </div>
        <label className="row" style={{ gap: "0.5rem" }}>
          <input
            type="checkbox"
            checked={s.showNimbus}
            onChange={(e) => void patch({ showNimbus: e.target.checked })}
          />
          Nimbus cloud
        </label>
      </div>
    </div>
  );
}
