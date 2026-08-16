import { useMemo, useState } from "react";
import { v4 as uuid } from "uuid";
import type { AppData, Flashcard } from "../shared/types";
import {
  bumpTraining,
  reviewFlashcard,
  todayKey,
} from "../shared/types";
import { playSfx } from "../lib/sound";

export function ReviewPanel({
  data,
  save,
}: {
  data: AppData;
  save: (d: AppData) => Promise<AppData>;
}) {
  const due = useMemo(
    () =>
      [...data.flashcards]
        .filter((c) => new Date(c.dueAt).getTime() <= Date.now())
        .sort(
          (a, b) => new Date(a.dueAt).getTime() - new Date(b.dueAt).getTime()
        ),
    [data.flashcards]
  );
  const [index, setIndex] = useState(0);
  const [flipped, setFlipped] = useState(false);
  const card = due[index] ?? null;

  async function grade(quality: number) {
    if (!card) return;
    const updated = reviewFlashcard(card, quality);
    const flashcards = data.flashcards.map((c) =>
      c.id === card.id ? updated : c
    );
    const next = bumpTraining(
      { ...data, flashcards },
      { cardsReviewed: 1 }
    );
    playSfx(quality >= 3 ? "ping" : "scold", data.settings.sfxEnabled);
    await save(next);
    setFlipped(false);
    setIndex(0);
  }

  function exportAnki() {
    const rows = [
      "Front\tBack",
      ...data.flashcards.map(
        (c) =>
          `${c.front.replace(/\t|\n/g, " ")}\t${c.back.replace(/\t|\n/g, " ")}`
      ),
    ];
    const blob = new Blob([rows.join("\n")], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `goku-cards-${todayKey()}.txt`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div className="stack">
      <div className="panel stack">
        <div className="row" style={{ justifyContent: "space-between" }}>
          <div>
            <strong>Spaced review</strong>
            <p className="muted" style={{ margin: "0.25rem 0 0" }}>
              {due.length} due · {data.flashcards.length} total
            </p>
          </div>
          <button className="btn secondary" type="button" onClick={exportAnki}>
            Export Anki/TSV
          </button>
        </div>

        {!card ? (
          <div className="empty">No cards due. Generate some from Tutor/Notes.</div>
        ) : (
          <div className="stack">
            <button
              type="button"
              className="note-card"
              style={{ textAlign: "left", cursor: "pointer", width: "100%" }}
              onClick={() => setFlipped((f) => !f)}
            >
              <h3>{flipped ? "Answer" : "Prompt"}</h3>
              <p>{flipped ? card.back : card.front}</p>
              <p className="muted" style={{ marginTop: "0.5rem" }}>
                Click to flip
              </p>
            </button>
            {flipped && (
              <div className="row">
                <button className="btn secondary" type="button" onClick={() => void grade(1)}>
                  Again
                </button>
                <button className="btn secondary" type="button" onClick={() => void grade(3)}>
                  Hard
                </button>
                <button className="btn" type="button" onClick={() => void grade(4)}>
                  Good
                </button>
                <button className="btn" type="button" onClick={() => void grade(5)}>
                  Easy
                </button>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

export async function addCardsFromText(
  data: AppData,
  save: (d: AppData) => Promise<AppData>,
  noteId: string | undefined,
  raw: string
) {
  // Expect lines like Q: ... A: ... or JSON array
  let cards: { front: string; back: string }[] = [];
  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) {
      cards = parsed
        .map((x) => ({
          front: String(x.front || x.q || "").trim(),
          back: String(x.back || x.a || "").trim(),
        }))
        .filter((x) => x.front && x.back);
    }
  } catch {
    const blocks = raw.split(/\n+/);
    for (const line of blocks) {
      const m = line.match(/^(?:Q:|Front:)\s*(.+?)\s*(?:\|(?:A:|Back:)\s*|\t)(.+)$/i);
      if (m) cards.push({ front: m[1].trim(), back: m[2].trim() });
    }
    // also numbered "1. question — answer"
    if (cards.length === 0) {
      for (const line of blocks) {
        const m = line.match(/^\d+[.)]\s*(.+?)\s*[—\-:]\s*(.+)$/);
        if (m) cards.push({ front: m[1].trim(), back: m[2].trim() });
      }
    }
  }

  if (cards.length === 0) return 0;
  const now = new Date().toISOString();
  const latest = await window.todoApi.getData();
  const flashcards: Flashcard[] = [
    ...cards.map((c) => ({
      id: uuid(),
      front: c.front,
      back: c.back,
      noteId,
      dueAt: now,
      intervalDays: 0,
      ease: 2.5,
      reps: 0,
      createdAt: now,
    })),
    ...latest.flashcards,
  ];
  await save({ ...latest, flashcards });
  return cards.length;
}
