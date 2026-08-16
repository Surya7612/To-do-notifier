import { useEffect, useState } from "react";
import {
  voiceController,
  type VoiceMode,
  type VoiceStatus,
} from "../lib/voiceController";

function labelFor(status: VoiceStatus, mode: VoiceMode, detail: string) {
  if (status === "off") return detail || "⌘G to talk";
  if (status === "asking-mic") return detail || "Starting voice…";
  if (status === "loading") return detail || "Starting…";
  if (status === "blocked") return detail ? detail.slice(0, 42) : "Mic blocked";
  if (status === "error") return detail ? detail.slice(0, 48) : "Voice error";
  if (status === "listening") {
    if (detail?.includes("speaking")) return "Speaking";
    if (mode === "dictate") return "Dictating";
    if (mode === "awake") return "Conversation · Esc";
    if (detail) return detail;
    return "Hey Goku";
  }
  return "Voice";
}

/** Honest live status — companion vs dictation. */
export function VoiceStatusBadge() {
  const [status, setStatus] = useState<VoiceStatus>("off");
  const [mode, setMode] = useState<VoiceMode>("companion");
  const [detail, setDetail] = useState("");

  useEffect(() => {
    const cur = voiceController.getStatus();
    setStatus(cur.status);
    setMode(cur.mode);
    setDetail(cur.detail);
    const off = voiceController.subscribe({
      onStatus: (s, d) => {
        setStatus(s);
        setDetail(d || "");
      },
      onMode: (m) => setMode(m),
    });
    const offUi = window.todoApi.onVoiceUiStatus?.((payload) => {
      if (payload?.status) setStatus(payload.status as VoiceStatus);
      if (payload?.detail != null) setDetail(String(payload.detail));
    });
    return () => {
      off();
      offUi?.();
    };
  }, []);

  const ok = status === "listening";
  const bad = status === "blocked" || status === "error";
  const dictating = mode === "dictate" && ok;

  return (
    <span
      className="status-pill"
      title={detail || labelFor(status, mode, detail)}
      style={{ maxWidth: "16rem" }}
    >
      <span
        className={`dot ${ok ? "ok" : ""} ${bad ? "bad" : ""} ${dictating ? "dictate" : ""}`}
      />
      <span
        style={{
          overflow: "hidden",
          textOverflow: "ellipsis",
          whiteSpace: "nowrap",
        }}
      >
        {labelFor(status, mode, detail)}
      </span>
    </span>
  );
}
