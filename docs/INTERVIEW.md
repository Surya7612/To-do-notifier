# Interview narrative (AI Engineer)

## 30 seconds

Max is a menu-bar context companion: hotkey → ScreenCaptureKit → on-device OCR →
answer from a local or opt-in cloud model **only when I ask**. Memory stores my
stated reason separately from any model gloss. Tasks stay in the study app; Max
never writes its store. Off-Mac alerts use Apple’s iCloud Reminders sync instead
of a custom push server. Shipped as a Developer ID–signed, notarized suite DMG
with Sparkle updates on the direct-download channel.

## Why not APNs / a hosted scheduler?

“I am not at my Mac” is solved by writing dated tasks into an **iCloud Reminders
list** — Apple already runs the scheduler and delivers to iPhone and Watch. A
custom APNs pipeline needs a server, token registration, delivery state, and
usually an iOS app. That buys *knowing an alert was seen* and retries; it does
not buy the away-from-Mac case we already have. Saying so in an interview shows
product judgment, not a missing feature.

## Architecture sound bites

- **User vs inference:** `SavedContext.intent` is never overwritten; `aiSummary`
  is labelled; retrieval always explains itself (`same window`, `#tag`,
  `close in meaning`).
- **No background cloud work:** `summarize` / `embed` exist only on
  `OllamaBrain`, not on the `Brain` protocol.
- **Two apps, one task list:** companion publishes `companion-projects.json`;
  Electron imports `companion:` tasks; neither mutates the other’s file.
- **Teaching without invented coordinates:** Max names controls in quotes; Vision
  OCR boxes decide pixels; board is a separate surface for invented diagrams.

## AI Engineer — what to showcase

| Capability | Where it lives | Why it reads as engineering |
| --- | --- | --- |
| Structured retrieval + optional embeddings | `ContextRetriever`, `Embedding` | Additive, explainable scores; asymmetric task prefixes for `nomic-embed-text` |
| Screen-conditioned prompts | `ScreenKind`, `Prompt` | Inference may shape *how* to answer, never whether / what to store |
| On-device speech in/out | Parakeet + Kokoro via FluidAudio | No cloud STT/TTS on the companion path |
| Streaming Markdown UI | `AnswerContent`, `CodeHighlighter` | Streaming-safe parse; opaque code well for legibility |
| Lesson / follow-along | `Lesson`, `ScreenTextLocator` | Quoted labels only for unprompted drawing |

## Tech research — what beats the plan for an AI Engineer interview

Researched against what Max already ships (OCR + optional cloud vision, local
embeddings, Parakeet/Kokoro, explainable retrieval, Teach/board). Goal: **demo
capability density**, not feature count. Free / free-trial only.

### Ranked recommendations

| Rank | Tech | Cost | Beats what we have? | Interview signal | Fit / risk | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| **1** | **Ollama + Qwen2.5-VL** (`qwen2.5vl:7b` or `:3b`) | Free | Yes — local answers that *see* UI/diagrams; today local path is OCR-first and cloud is the vision escape hatch | Multimodal, Apple Silicon, privacy-preserving | Code already sends `images` when `includeImage`; need VL model pulled + “Send screenshot” on for local. 16 GB RAM tight on 7B | **Do for demo** — highest ROI, ~zero new architecture |
| **2** | **Apple Foundation Models** (`SystemLanguageModel`) | Free (AI-capable Mac) | Partial — zero-install on-device LLM for summarize / structured extract; weaker than Qwen VL on screenshots | Native Apple AI API, guided generation (`@Generable`), tool calling | Needs Apple Intelligence device/region; fallback required | **Strong talking point**; optional Brain backend if time |
| **3** | **Eval harness** (golden screen Qs + rubric) | Free | Yes vs “vibes demo” — measurable answer quality OCR-only vs VL vs cloud | Evaluation, metrics, iteration | Pure test fixtures + a script; no product risk | **Do** — 1–2 day, screams AI Engineer |
| **4** | **Tool-calling / structured lesson JSON** (local model emits step schema) | Free | Slightly — today lessons are Markdown lists; schema = reliable Teach | Agents / structured output without LangChain | Keep OCR boxes as ground truth; schema only names labels | **Nice** if Teach flakes in rehearsal |
| **5** | **MLX Swift / macMLX / SwiftLM** | Free (OSS) | Maybe latency — in-process Metal vs Ollama HTTP | Deep Apple Silicon inference story | Extra runtime, Metal toolchain, duplicates Ollama | **Skip pre-interview** — Ollama+VL wins the same story cheaper |
| **6** | **Gemini / OpenAI free tier as default vision** | Free trial / credits | Quality on hard UIs | “I use the best model when opted in” | Already wired; exporting screen by default fights the product thesis | Keep **opt-in**; use as backup if VL not pulled |
| **7** | **LangChain / multi-file agents / MCP coding agent** | Free | Broader agent demos elsewhere | Agentic frameworks | Plan rejected for Max: no file tree, no tests, worse than the open editor | **Don’t bolt onto Max** — speak to the rejection as judgment |
| **8** | **CloudKit + APNs / custom push** | Free tier + Dev Program | Delivery receipts | Mobile + infra | Weeks of work; Reminders already covers “away from Mac” | **After interview** |
| **9** | **Fine-tuning / LoRA on your screens** | Free (MLX) | Domain adaptation story | Training loop | Data collection + eval burden; overkill for days | **Skip** |
| **10** | **Whisper.cpp replacing Parakeet** | Free | Unlikely — Parakeet already on-device Neural Engine | STT swap | Regression risk mid-demo | **Skip** |

### What “fly free” means here

The plan’s non-goals (no wake word, no background capture, no multi-file agent)
still protect the product in an interview — they are *why* Max is trustworthy
next to a private screen. Flying free means **strengthening the AI path**
(local VL, evals, Apple FM), not abandoning the trust model for a generic
agent demo every other candidate can clone from LangChain templates.

### Demo models

Use **OpenAI (or Claude/Gemini) with screenshot** for the live interview — already
wired. Local Ollama remains the default for day-to-day; no need to change stack
for the talk.

## Product zoom-out — features that would make Max *much* better for a user

Not model swaps. Jobs-to-be-done beyond “ask about this screen once.”

Today Max is strong at **this moment** (capture → answer → teach → save →
remind). The gap for a real user is **continuity**: same problem tomorrow,
same project across days, same error returning, prep before a meeting.

| Feature | User job | Why it’s bigger than now | Cost / risk | Interview angle | Priority |
| --- | --- | --- | --- | --- | --- |
| **1. “Same error / same window” memory loop** | “I fixed this last week — show me how” | Saves already exist; resurfacing on summon is thin. Explicit **match this screen to a past fix** (diff OCR/title + your old reason) turns the library into a personal Stack Overflow | Medium; stays user-initiated on summon | Retrieval + product judgment | **P0 product** |
| **2. Project brief (approve-to-save)** | “What have I been working on in Engram?” | Auto-assemble from intents + open todos + recent saves into a one-pager Max proposes; you edit/keep | Low–med; inference proposes, user writes | Structured generation + human-in-loop | **P0** |
| **3. Change-aware re-save** | “What changed since I kept this?” | Second save of same window → visual/text diff of OCR or image; file under “progress” | Med | Multimodal / diff | **P1** |
| **4. Standup / meeting prep** | “What should I say in 10 minutes?” | Pull Due soon + project saves + open tasks into a spoken or listed brief on hotkey | Low if scoped to summon | Context assembly | **P1** |
| **5. Export lesson → notes** | “Keep the teaching, not only the screenshot” | One click: numbered Teach steps + quotes → Markdown/note in Electron or clipboard | Low | Teaching → durable artifact | **P1** |
| **6. Selection / clipboard ask** | “Explain *this* without a full capture” | Hotkey on selected text or clipboard; screenshot optional | Low | Latency + precision | **P1** |
| **7. Confidence & grounding UI** | “Is Max guessing or quoting?” | Badge: OCR-only vs vision; click a claim → highlight source box | Med | Trust / eval literacy | **P1** for AI role |
| **8. Correct the box** | “You pointed at the wrong control” | Drag/resize highlight → improves next match for that label in-session | Med | Human feedback loop | **P2** |
| **9. Spaced revisit of saves** | “I saved this to learn it” | Bridge intents into Electron flashcards / Due soon “revisit” | Med; crosses apps cleanly via export | Learning product | **P2** |
| **10. Share a keep** | “Send this context to a teammate” | Export encrypted or redacted pack (image + your reason, not full chat) | Med; privacy | Collaboration | **P2** |
| Still refuse (for good product reasons) | Wake word, background capture, proactive popups, multi-file agents | Break trust next to a private screen; demos well once, hurts daily use | — | Saying no is seniority | Keep |

### What to say in the interview (zoomed out)

“Max isn’t a chatbot with a screenshot. It’s **working memory for what’s on your
screen**: capture, teach, keep under *your* words, bring it back when the same
work returns. The next product leap isn’t a bigger agent — it’s closing the
loop from ‘I learned this once’ to ‘it finds that learning when I need it
again,’ still only when I summon it.”

### If building one thing before the interview

**#1 same-error / same-window memory loop** or **#7 confidence/grounding** —
both read as AI systems thinking, not as another chat feature. Use OpenAI+vision
for the live ask; the *product* story is continuity + trust.

## Pointers

- Design rejections: [PLAN.md](PLAN.md) §17, Phase 7
- Usability non-goals: [USABILITY.md](USABILITY.md) §10
- Live demo checklist: [DEMO.md](DEMO.md)
- Agent / contributor rules: [../AGENTS.md](../AGENTS.md)
