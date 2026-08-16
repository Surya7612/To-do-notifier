import { useEffect, useState } from "react";
import { v4 as uuid } from "uuid";
import type { AppData, NoteItem } from "../shared/types";
import { bumpTraining } from "../shared/types";
import { addCardsFromText } from "./ReviewPanel";
import { playSfx } from "../lib/sound";
import {
  voiceController,
  type VoiceStatus,
} from "../lib/voiceController";

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
  const [status, setStatus] = useState("…");
  const [ollamaOk, setOllamaOk] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [topic, setTopic] = useState("Study session");
  const [socratic, setSocratic] = useState(data.settings.socraticDefault);
  const [dragOver, setDragOver] = useState(false);

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

  // Shared mic: companion (wake/chat) vs dictate (this panel's transcript)
  useEffect(() => {
    const off = voiceController.subscribe({
      onMode: (mode) => setListening(mode === "dictate"),
      onStatus: (s) => {
        setVoiceStatus(s);
      },
      onFinal: (text) => {
        if (voiceController.isDictating()) setTranscript(text);
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
  }, []);

  async function toggleTutorCapture() {
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

  async function askQuestions() {
    const source = draftNotes.trim() || transcript.trim();
    if (!source) {
      setError("Need notes or a transcript to quiz from.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const content = await window.todoApi.ollamaChat({
        system: socratic
          ? "You are Goku helping a friend study. Ask 5 short spoken-style questions only. No answers. Casual tone."
          : "You are Goku quizzing a friend. Ask 5 short questions from the notes only. Number them. No answers. Sound natural, not like a worksheet.",
        prompt: `Notes:\n${source}`,
      });
      setQuiz(content.trim());
      await saveMerge((latest) => bumpTraining(latest, { quizRounds: 1 }));
      playSfx("ping", data.settings.sfxEnabled);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
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
          'Return ONLY a JSON array of 6-10 objects {"front":"...","back":"..."} for spaced-repetition flashcards grounded in the notes. No markdown fences.',
        prompt: source,
      });
      const cleaned = content.replace(/```json|```/g, "").trim();
      const n = await addCardsFromText(data, save, undefined, cleaned);
      if (!n) throw new Error("Could not parse flashcards from model output.");
      playSfx("done", data.settings.sfxEnabled);
      setError(null);
      await window.todoApi.notify({
        title: "Flashcards ready",
        body: `Added ${n} cards to Review.`,
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function onDrop(files: FileList | null) {
    if (!files?.length) return;
    setDragOver(false);
    setBusy(true);
    setError(null);
    try {
      const text = await readDroppedFile(files[0]);
      setTranscript((prev) =>
        prev ? `${prev}\n\n---\nImported ${files[0].name}\n${text}` : text
      );
      setTopic(files[0].name.replace(/\.[^.]+$/, ""));
      const now = new Date().toISOString();
      const note: NoteItem = {
        id: uuid(),
        title: files[0].name,
        body: text.slice(0, 20000),
        source: "import",
        createdAt: now,
        updatedAt: now,
      };
      await saveMerge((latest) => ({
        ...latest,
        notes: [note, ...latest.notes],
      }));
      playSfx("ping", data.settings.sfxEnabled);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  const displayTranscript = transcript;

  return (
    <div className="stack">
      <div
        className="panel stack"
        onDragOver={(e) => {
          e.preventDefault();
          setDragOver(true);
        }}
        onDragLeave={() => setDragOver(false)}
        onDrop={(e) => {
          e.preventDefault();
          void onDrop(e.dataTransfer.files);
        }}
        style={
          dragOver
            ? { outline: "2px dashed rgba(255,106,61,0.7)" }
            : undefined
        }
      >
        <div className="row" style={{ justifyContent: "space-between" }}>
          <strong>Tutor</strong>
          <span className="status-pill">
            <span className={`dot ${ollamaOk ? "ok" : ""}`} />
            {status}
          </span>
        </div>

        <div className={`voice-stage ${listening ? "live" : ""}`}>
          <button
            type="button"
            className="voice-orb"
            aria-label={listening ? "Stop dictation" : "Start dictation"}
            onClick={toggleTutorCapture}
          >
            <span className="voice-ring" />
            <span className="voice-ring delay" />
            <span className="voice-core">
              {voiceStatus === "blocked"
                ? "Mic blocked"
                : voiceStatus === "error"
                  ? "Error"
                  : voiceStatus === "loading" || voiceStatus === "asking-mic"
                    ? "…"
                    : listening
                      ? "Dictating"
                      : "Dictate"}
            </span>
          </button>
        </div>

        <label className="row" style={{ gap: "0.5rem" }}>
          <input
            type="checkbox"
            checked={socratic}
            onChange={(e) => setSocratic(e.target.checked)}
          />
          <span>Socratic</span>
        </label>

        <div className="field">
          <label htmlFor="topic">Topic</label>
          <input
            id="topic"
            value={topic}
            onChange={(e) => setTopic(e.target.value)}
            placeholder="Topic"
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
            disabled={busy || !transcript.trim()}
            onClick={() => void askQuestions()}
          >
            Quiz
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
            Save
          </button>
        </div>

        {error && (
          <p style={{ color: "var(--danger)", margin: 0 }}>{error}</p>
        )}

        <div className="field">
          <label htmlFor="transcript">Transcript</label>
          <textarea
            id="transcript"
            value={displayTranscript}
            onChange={(e) => setTranscript(e.target.value)}
            placeholder="Your explanation…"
            style={{ minHeight: 140 }}
          />
        </div>

        <div className="field">
          <label htmlFor="draft">{socratic ? "Probes" : "Notes"}</label>
          <textarea
            id="draft"
            value={draftNotes}
            onChange={(e) => setDraftNotes(e.target.value)}
            placeholder="Output…"
            style={{ minHeight: 160 }}
          />
        </div>

        {quiz && (
          <div className="quiz-box">
            <strong>Quiz</strong>
            <p style={{ whiteSpace: "pre-wrap", margin: "0.5rem 0 0" }}>
              {quiz}
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
