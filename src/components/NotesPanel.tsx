import { FormEvent, useState } from "react";
import { v4 as uuid } from "uuid";
import type { AppData, NoteItem } from "../shared/types";
import { todayKey } from "../shared/types";
import { addCardsFromText } from "./ReviewPanel";

export function NotesPanel({
  data,
  save,
}: {
  data: AppData;
  save: (d: AppData) => Promise<AppData>;
}) {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const selected = data.notes.find((n) => n.id === selectedId) ?? null;

  async function onCreate(e: FormEvent) {
    e.preventDefault();
    if (!title.trim() && !body.trim()) return;
    const now = new Date().toISOString();
    const note: NoteItem = {
      id: uuid(),
      title: title.trim() || "Untitled note",
      body: body.trim(),
      source: "manual",
      createdAt: now,
      updatedAt: now,
    };
    await save({ ...data, notes: [note, ...data.notes] });
    setTitle("");
    setBody("");
    setSelectedId(note.id);
  }

  async function onUpdate() {
    if (!selected) return;
    const notes = data.notes.map((n) =>
      n.id === selected.id
        ? {
            ...n,
            title: title || n.title,
            body,
            updatedAt: new Date().toISOString(),
          }
        : n
    );
    await save({ ...data, notes });
  }

  async function onDelete(id: string) {
    await save({ ...data, notes: data.notes.filter((n) => n.id !== id) });
    if (selectedId === id) {
      setSelectedId(null);
      setTitle("");
      setBody("");
    }
  }

  function openNote(note: NoteItem) {
    setSelectedId(note.id);
    setTitle(note.title);
    setBody(note.body);
  }

  return (
    <div className="stack">
      <form className="panel stack" onSubmit={onCreate}>
        <div className="field">
          <label htmlFor="note-title">Title</label>
          <input
            id="note-title"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Topic / session title"
          />
        </div>
        <div className="field">
          <label htmlFor="note-body">Notes</label>
          <textarea
            id="note-body"
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="Write freely, or let tutoring mode fill this in."
          />
        </div>
        <div className="row">
          {selected ? (
            <>
              <button className="btn" type="button" onClick={() => void onUpdate()}>
                Save changes
              </button>
              <button
                className="btn secondary"
                type="button"
                onClick={() => {
                  setSelectedId(null);
                  setTitle("");
                  setBody("");
                }}
              >
                New note
              </button>
              <button
                className="btn secondary"
                type="button"
                onClick={() => {
                  const blob = new Blob(
                    [`# ${title}\n\n${body}\n`],
                    { type: "text/markdown" }
                  );
                  const url = URL.createObjectURL(blob);
                  const a = document.createElement("a");
                  a.href = url;
                  a.download = `${(title || "note").replace(/\s+/g, "-")}-${todayKey()}.md`;
                  a.click();
                  URL.revokeObjectURL(url);
                }}
              >
                Export .md
              </button>
              <button
                className="btn secondary"
                type="button"
                onClick={() =>
                  void window.todoApi.ollamaChat({
                    system:
                      'Return ONLY a JSON array of 6-8 {"front","back"} flashcards from the note.',
                    prompt: `${title}\n\n${body}`,
                  }).then(async (raw) => {
                    const cleaned = raw.replace(/```json|```/g, "").trim();
                    const n = await addCardsFromText(
                      data,
                      save,
                      selectedId ?? undefined,
                      cleaned
                    );
                    await window.todoApi.notify({
                      title: "Cards from note",
                      body: n ? `Added ${n} cards` : "No cards parsed",
                    });
                  })
                }
              >
                Make cards
              </button>
            </>
          ) : (
            <button className="btn" type="submit">
              Create note
            </button>
          )}
        </div>
      </form>

      <div className="stack">
        {data.notes.length === 0 ? (
          <div className="panel empty">No notes yet.</div>
        ) : (
          data.notes.map((note) => (
            <article key={note.id} className="note-card">
              <div className="row" style={{ justifyContent: "space-between" }}>
                <h3>{note.title}</h3>
                <span className="badge">
                  {note.source === "tutoring"
                    ? "From Goku"
                    : note.source === "import"
                      ? "Import"
                      : "Manual"}
                </span>
              </div>
              <p>{note.body.slice(0, 220)}{note.body.length > 220 ? "…" : ""}</p>
              <div className="row" style={{ marginTop: "0.65rem" }}>
                <button
                  className="btn secondary"
                  type="button"
                  onClick={() => openNote(note)}
                >
                  Open
                </button>
                <button
                  className="btn ghost"
                  type="button"
                  onClick={() => void onDelete(note.id)}
                >
                  Delete
                </button>
              </div>
            </article>
          ))
        )}
      </div>
    </div>
  );
}
