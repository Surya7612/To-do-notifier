import { useEffect, useRef, useState } from "react";
import { v4 as uuid } from "uuid";
import type { AppData, NoteItem } from "../shared/types";
import { bumpTraining } from "../shared/types";
import { addCardsFromText } from "./ReviewPanel";
import { playSfx } from "../lib/sound";
import {
  voiceController,
  type VoiceStatus,
} from "../lib/voiceController";
import duckGoku from "../assets/duckgoku.png";

const ASK_RE =
  /\b(ask me|quiz me|probe me|test me|ask (me )?questions?|what am i missing|help me understand)\b/i;

async function readDroppedFile(file: File): Promise<string> {
  const name = file.name.toLowerCase();
  if (
    name.endsWith(".txt") ||
    name.endsWith(".md") ||
    name.endsWith(".markdown") ||
    name.endsWith(".csv") ||
    file.type.startsWith("text/")
  ) {
    return file.text();
  }
  if (name.endsWith(".pdf") || file.type === "application/pdf") {
    try {
      const pdfjs = await import("pdfjs-dist");
      pdfjs.GlobalWorkerOptions.workerSrc = new URL(
        "pdfjs-dist/build/pdf.worker.min.mjs",
        import.meta.url
      ).toString();
      const buf = await file.arrayBuffer();
      const doc = await pdfjs.getDocument({ data: buf }).promise;
      let text = "";
      const max = Math.min(doc.numPages, 20);
      for (let i = 1; i <= max; i++) {
        const page = await doc.getPage(i);
        const content = await page.getTextContent();
        text +=
          content.items
            .map((it) => ("str" in it ? String(it.str) : ""))
            .join(" ") + "\n";
      }
      return text.trim();
    } catch {
      throw new Error("PDF parse failed. Paste the text instead.");
    }
  }
  throw new Error("Supported drops: .txt, .md, .csv, .pdf");
}

function stripAskPhrase(text: string) {
  return text.replace(ASK_RE, " ").replace(/\s+/g, " ").trim();
}

export function TutoringPanel({
  data,
  save,
  saveMerge,
}: {
  data: AppData;
  save: (d: AppData) => Promise<AppData>;
  saveMerge: (mutator: (latest: AppData) => AppData) => Promise<AppData>;
}) {
  const [listening, setListening] = useState(false);
  const [voiceStatus, setVoiceStatus] = useState<VoiceStatus>("off");
  const [transcript, setTranscript] = useState("");
  const [draftNotes, setDraftNotes] = useState("");
  const [quiz, setQuiz] = useState("");
  const [lastQuestion, setLastQuestion] = useState("");
  const [status, setStatus] = useState("…");
  const [ollamaOk, setOllamaOk] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [topic, setTopic] = useState("Study session");
  const [dragOver, setDragOver] = useState(false);
  const [toolsOpen, setToolsOpen] = useState(false);
  const [duckOpen, setDuckOpen] = useState(false);
  const [socratic, setSocratic] = useState(data.settings.socraticDefault);
  const askBusy = useRef(false);
  const transcriptRef = useRef("");
  const socraticRef = useRef(socratic);
  socraticRef.current = socratic;

  useEffect(() => {
    let alive = true;
    window.todoApi.ollamaStatus().then((s) => {
      if (!alive) return;
      if (!s.ok) {
        setOllamaOk(false);
        setStatus("Offline");
        return;
      }
      setOllamaOk(true);
      setStatus(s.hasModel ? "Ready" : "Model missing");
    });
    return () => {
      alive = false;
    };
  }, [data.settings.ollamaModel]);

  useEffect(() => {
    const off = voiceController.subscribe({
      onMode: (mode) => setListening(mode === "dictate"),
      onStatus: (s) => setVoiceStatus(s),
      onFinal: (text) => {
        if (!voiceController.isDictating()) return;
        setTranscript(text);
        transcriptRef.current = text;
        if (ASK_RE.test(text)) {
          void askSocraticLive(stripAskPhrase(text));
        }
      },
    });
    setListening(voiceController.isDictating());
    const cur = voiceController.getStatus();
    setVoiceStatus(cur.status);
    return () => {
      off();
      if (voiceController.isDictating()) {
        voiceController.setDictate(false, { silent: true });
      }
    };
    // askSocraticLive is stable enough via refs
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function toggleListen() {
    setError(null);
    if (voiceStatus === "blocked") {
      setError("Microphone blocked in System Settings.");
      return;
    }
    if (voiceStatus === "error") {
      setError("Voice error — check Settings / OpenAI key.");
      return;
    }
    try {
      await voiceController.arm();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      return;
    }
    if (voiceController.isDictating()) {
      voiceController.setDictate(false);
    } else {
      voiceController.setDictate(true);
      playSfx("ping", data.settings.sfxEnabled);
      void window.todoApi.petSpeak(
        "I'm listening. Explain it — then say ask me when you want a question."
      );
    }
  }

  async function exitDuck() {
    if (voiceController.isDictating()) {
      voiceController.setDictate(false, { silent: true });
    }
    setDuckOpen(false);
  }

  async function askSocraticLive(sourceOverride?: string) {
    if (askBusy.current) return;
    const source = (sourceOverride ?? transcriptRef.current ?? transcript).trim();
    if (!source) {
      setError("Talk through the topic first, then ask me.");
      void window.todoApi.petSpeak("Tell me what you're studying first.");
      return;
    }
    askBusy.current = true;
    setBusy(true);
    setError(null);
    const probing = socraticRef.current;
    try {
      const content = await window.todoApi.ollamaChat({
        system: probing
          ? "You are Son Goku — a Socratic rubber-duck buddy. Reply with ONE short spoken question (max 2 sentences) that helps them understand better. No answers, no lists, no markdown. Curious friend tone."
          : "You are Son Goku — a study buddy. Give ONE short spoken tip (max 2 sentences) that clarifies their explanation. No markdown, no lists. Encouraging friend tone.",
        prompt: probing
          ? `Topic: ${topic}\n\nWhat they said:\n${source}\n\nAsk one clarifying question that exposes a gap or forces them to explain a key idea.`
          : `Topic: ${topic}\n\nWhat they said:\n${source}\n\nGive one short tip that helps them lock the idea in.`,
      });
      const line = content.replace(/\s+/g, " ").trim().slice(0, 220);
      if (!line) throw new Error("No reply from Ollama.");
      setLastQuestion(line);
      setQuiz((prev) => (prev ? `${prev}\n• ${line}` : `• ${line}`));
      await saveMerge((latest) => bumpTraining(latest, { quizRounds: 1 }));
      playSfx("ping", data.settings.sfxEnabled);
      await window.todoApi.petSpeak(line);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      askBusy.current = false;
      setBusy(false);
    }
  }

  async function scriptUnderstanding() {
    if (!transcript.trim()) {
      setError("Add some spoken/typed explanation first.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const content = await window.todoApi.ollamaChat({
        system: socratic
          ? "You are Goku. Ask 6 short probing questions that expose gaps. Number them. No answers. Casual."
          : "You are Goku turning a spoken explanation into clear study notes. Short sections, bullets, call out fuzzy bits. Encouraging. Markdown ok.",
        prompt: `Topic: ${topic}\n\nStudent explanation:\n${transcript}`,
      });
      setDraftNotes(content.trim());
      await saveMerge((latest) => bumpTraining(latest, { tutorSessions: 1 }));
      if (!socratic && content.trim()) {
        const now = new Date().toISOString();
        const note: NoteItem = {
          id: uuid(),
          title: topic.trim() || "Tutoring notes",
          body: content.trim(),
          source: "tutoring",
          createdAt: now,
          updatedAt: now,
        };
        await saveMerge((latest) => ({
          ...latest,
          notes: [note, ...latest.notes],
        }));
        await window.todoApi.notify({
          title: "Saved to Notes",
          body: note.title,
        });
      }
      playSfx("power", data.settings.sfxEnabled);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function saveAsNote() {
    if (!draftNotes.trim()) return;
    const now = new Date().toISOString();
    const note: NoteItem = {
      id: uuid(),
      title: topic.trim() || "Tutoring notes",
      body: draftNotes.trim(),
      source: "tutoring",
      createdAt: now,
      updatedAt: now,
    };
    await saveMerge((latest) => ({
      ...latest,
      notes: [note, ...latest.notes],
    }));
    await window.todoApi.notify({
      title: "Saved to Notes",
      body: note.title,
    });
  }

  async function makeFlashcards() {
    const source = draftNotes.trim() || transcript.trim();
    if (!source) {
      setError("Need notes/transcript to build cards.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const content = await window.todoApi.ollamaChat({
        system:
          "Make 6 flashcards as Q: ... / A: ... lines only, from the study text.",
        prompt: source,
      });
      await addCardsFromText(data, save, undefined, content);
      await saveMerge((latest) => bumpTraining(latest, { cardsReviewed: 0 }));
      playSfx("power", data.settings.sfxEnabled);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function onDrop(files: FileList | null) {
    if (!files?.length) return;
    setDragOver(false);
    setError(null);
    try {
      const text = await readDroppedFile(files[0]);
      setTranscript((t) => (t ? `${t}\n\n${text}` : text));
      transcriptRef.current = text;
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }

  const liveLabel =
    voiceStatus === "blocked"
      ? "Mic blocked"
      : voiceStatus === "error"
        ? "Voice error"
        : voiceStatus === "loading" || voiceStatus === "asking-mic"
          ? "Starting…"
          : listening
            ? socratic
              ? "Listening — say “ask me” for a probe"
              : "Listening — say “ask me” for a tip"
            : "Ready when you are";

  if (!duckOpen) {
    return (
      <div className="stack">
        <div className="panel stack duck-entry">
          <div
            className="duck-entry-art"
            style={{ backgroundImage: `url(${duckGoku})` }}
            aria-hidden
          />
          <div className="duck-entry-copy">
            <strong>Rubber Duck</strong>
            <p className="muted" style={{ margin: 0 }}>
              Full-screen focus with Goku. Explain out loud — he listens, then
              asks questions so the idea sticks.
            </p>
            <label className="row" style={{ gap: "0.5rem" }}>
              <input
                type="checkbox"
                checked={socratic}
                onChange={(e) => setSocratic(e.target.checked)}
              />
              <span>Socrates mode (questions only — no spoon-feeding)</span>
            </label>
            <button
              type="button"
              className="btn"
              onClick={() => setDuckOpen(true)}
            >
              Enter Rubber Duck
            </button>
          </div>
        </div>

        <div className="panel stack">
          <button
            type="button"
            className="btn secondary"
            style={{ alignSelf: "flex-start" }}
            onClick={() => setToolsOpen((v) => !v)}
          >
            {toolsOpen ? "Hide study tools" : "Study tools (notes / cards)"}
          </button>
          {toolsOpen ? (
            <>
              <div className="field">
                <label htmlFor="topic-out">Topic</label>
                <input
                  id="topic-out"
                  value={topic}
                  onChange={(e) => setTopic(e.target.value)}
                />
              </div>
              <div className="row">
                <button
                  className="btn secondary"
                  type="button"
                  disabled={busy || !transcript.trim()}
                  onClick={() => void scriptUnderstanding()}
                >
                  {socratic ? "Probe gaps" : "Make notes"}
                </button>
                <button
                  className="btn secondary"
                  type="button"
                  disabled={busy || !(draftNotes.trim() || transcript.trim())}
                  onClick={() => void makeFlashcards()}
                >
                  Cards
                </button>
                <button
                  className="btn"
                  type="button"
                  disabled={!draftNotes.trim()}
                  onClick={() => void saveAsNote()}
                >
                  Save note
                </button>
              </div>
              <div className="field">
                <label htmlFor="transcript-out">Transcript</label>
                <textarea
                  id="transcript-out"
                  rows={4}
                  value={transcript}
                  onChange={(e) => {
                    setTranscript(e.target.value);
                    transcriptRef.current = e.target.value;
                  }}
                />
              </div>
              <div className="field">
                <label htmlFor="draft-out">{socratic ? "Probes" : "Notes"}</label>
                <textarea
                  id="draft-out"
                  rows={5}
                  value={draftNotes}
                  onChange={(e) => setDraftNotes(e.target.value)}
                />
              </div>
              <div className="field">
                <label htmlFor="quiz-out">Questions so far</label>
                <textarea
                  id="quiz-out"
                  rows={4}
                  value={quiz}
                  onChange={(e) => setQuiz(e.target.value)}
                />
              </div>
            </>
          ) : null}
        </div>
      </div>
    );
  }

  return (
    <div
      className={`duck-fullscreen ${listening ? "live" : ""}`}
      onDragOver={(e) => {
        e.preventDefault();
        setDragOver(true);
      }}
      onDragLeave={() => setDragOver(false)}
      onDrop={(e) => {
        e.preventDefault();
        void onDrop(e.dataTransfer.files);
      }}
    >
      <div
        className="duck-bg"
        style={{ backgroundImage: `url(${duckGoku})` }}
        aria-hidden
      />
      <div className="duck-vignette" aria-hidden />
      <div className="duck-glow" aria-hidden />

      <button
        type="button"
        className="duck-back btn secondary"
        onClick={() => void exitDuck()}
      >
        ← Back
      </button>

      <div className="duck-hud">
        <div className="row" style={{ justifyContent: "space-between" }}>
          <div>
            <strong className="duck-title">Rubber Duck</strong>
            <p className="duck-sub muted">
              {socratic ? (
                <>
                  Explain out loud. Say <em>ask me</em> for a Socratic probe.
                </>
              ) : (
                <>
                  Explain out loud. Say <em>ask me</em> for a quick tip.
                </>
              )}
            </p>
          </div>
          <span className="status-pill">
            <span
              className={`dot ${ollamaOk ? "ok" : ""} ${listening ? "dictate" : ""}`}
            />
            {status}
          </span>
        </div>

        <label className="row duck-socratic" style={{ gap: "0.5rem" }}>
          <input
            type="checkbox"
            checked={socratic}
            onChange={(e) => setSocratic(e.target.checked)}
          />
          <span>Socrates mode</span>
        </label>

        <div className="field">
          <label htmlFor="topic">Topic</label>
          <input
            id="topic"
            value={topic}
            onChange={(e) => setTopic(e.target.value)}
            placeholder="What are you working through?"
          />
        </div>

        <div className="duck-actions row">
          <button
            type="button"
            className={`btn ${listening ? "" : "secondary"}`}
            onClick={() => void toggleListen()}
          >
            {listening ? "Stop listening" : "Start listening"}
          </button>
          <button
            type="button"
            className="btn secondary"
            disabled={busy}
            onClick={() => void askSocraticLive()}
          >
            Ask Goku
          </button>
        </div>

        <p className="duck-live muted">{liveLabel}</p>

        {lastQuestion ? (
          <div className="duck-question" role="status">
            <span className="duck-q-label">
              {socratic ? "Goku asks" : "Goku says"}
            </span>
            <p>{lastQuestion}</p>
          </div>
        ) : null}

        {error ? (
          <p style={{ color: "var(--danger)", margin: 0 }}>{error}</p>
        ) : null}

        {dragOver ? (
          <p className="muted" style={{ margin: 0 }}>
            Drop notes / PDF to add context…
          </p>
        ) : null}
      </div>
    </div>
  );
}
