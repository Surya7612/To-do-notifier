# To-Do Notifier → Native Personal Context Companion
**Updated project plan — September 7, 2026**

## 1. Project Direction

This remains a **personal side project first**.

The goal is **not** to force it into a startup, YC application, or commercial product right now. The project should evolve around real problems I personally have and workflows I actually use.

The clearest vision is:

> **Clicky’s native Mac embodiment + Engram’s context/retrieval thinking + the existing To-Do Notifier productivity system.**

In plain language:

> **A native personal Mac companion that knows what I am doing, remembers why things mattered, and keeps track of what I intended to do.**

The companion is the interface.  
The real value is the context layer underneath it.

---

## 2. What Each Existing Idea Contributes

### From Clicky
Use Clicky as an **engineering reference**, not as a product to clone.

Borrow the useful native interaction ideas:

- Native macOS app
- Swift / SwiftUI
- AppKit where SwiftUI is not enough
- Floating companion window
- Cursor-relative UI
- Menu bar behavior
- Global hotkeys
- ScreenCaptureKit
- Screen-aware AI interaction
- Transparent overlays
- Voice interaction
- Native macOS permissions
- Multi-monitor awareness

The goal is **not** "Clicky + more features."

The goal is to use native Mac embodiment as one surface for a broader personal context system.

#### Second pass — after the companion was working

Re-reading Clicky's `AGENTS.md` once our own app existed surfaced things worth
taking that were not obvious before there was code to compare against.

**Adopted:**

| Borrowed | Why it earned its place |
|---|---|
| `AGENTS.md` at the repo root | Architecture, key-file table, conventions, and self-update rules. Every agent session was re-deriving the architecture from scratch. Ours also records the no-AI-attribution rule and the hotkey and TCC traps. |
| Click-outside-to-dismiss | Every other floating panel on the system does this. Ours only closed on Esc, so it hung over whatever you switched to. Mouse-only monitor, so it still needs no Accessibility permission. |
| `LSUIElement` in Info.plist | We set `.accessory` programmatically, which works but flashes a dock icon at launch. Declaring it removes the flash. |
| Live audio level → waveform | Clicky drives a waveform from mic levels. Our silence watchdog was already computing peak amplitude and discarding it, so the listening ring now breathes with your voice. Silence looks like silence. |
| Multi-monitor capture | Already listed above as a Clicky idea, but unimplemented — we only grabbed the display under the cursor. The second monitor usually holds the documentation or terminal the question is actually about. |
| A design tokens file | Clicky's `DesignSystem.swift`. Ours is smaller, but the panel, library, and cursor ring are separately-authored surfaces that need to look like one app. |
| A release script | Clicky's `scripts/release.sh`, reduced to the steps a free Apple account can perform. See "Distribution reality" below. |

**Rejected, with reasons:**

| Not taken | Why not |
|---|---|
| Cursor pointing (`[POINT:x,y:label]`, bezier arcs to UI elements) | Clicky's signature feature and its most demo-friendly, but it serves tutoring. Our north star is connecting current activity to past intent. This is the clearest case of "Clicky + more features" and is exactly what §2 warns against. |
| Global push-to-talk via `CGEvent` tap | Requires Accessibility permission. We chose Carbon hot keys specifically to avoid that, and "clear permission boundaries" is a stated privacy principle. Not worth trading for a nicer dictation trigger. |
| AssemblyAI / OpenAI transcription providers | Both stream your voice off the machine. Apple's on-device recognizer is less accurate, and local-first is a product constraint rather than a default to trade away for accuracy. |
| PostHog analytics | Contradicts "do not silently collect everything". |
| Cloudflare Worker API proxy | Solves a problem we do not have: there are no API keys to hide when the model is local Ollama. Revisit only if a cloud model is ever added. |
| Sparkle auto-updates | Needs Developer ID signing and notarization. See below. |

**One inherited rule we should not copy.** Clicky's `AGENTS.md` says never run
`xcodebuild` from the terminal because it invalidates TCC permissions. That was
true for us under ad-hoc signing — it is the bug behind the "app needs
permission" loop in Phase 4. Once `DEVELOPMENT_TEAM` was set, TCC keys on the
stable signing identity instead of a per-build hash, and terminal builds became
safe. Our `AGENTS.md` says so explicitly so the rule is not cargo-culted.

#### Third pass — a cloud model, region selection, and the bridge

Two of the three rejections above were revisited once the local model's ceiling
became obvious in practice. Asked what was on screen, it described an editor
displaying a screenshot as "a To-Do-Notifier application" — a plausible sentence
about the wrong thing. Remembering survives that. Explaining a concept does not.

**A cloud provider, scoped by a rule rather than a preference.** OpenAI is now
selectable, and §12 already allowed for it: "local-first by *default*", "minimal
cloud data", "API keys in Keychain". The rule that keeps it honest is narrower
than a toggle:

> A cloud model may answer a question the user explicitly asked.
> It may never do background work.

Summaries are generated unprompted, across everything the user ever keeps, and
that accumulated picture of a working life is precisely what should not be
exported — while compressing OCR into one sentence is something a small local
model does perfectly well, so there is no quality argument either. This is
enforced by the type system, not by discipline: `summarize` is absent from the
`Brain` protocol and exists only on `OllamaBrain`, so no cloud provider can be
attached to it. Ollama remains the default, the key lives in the Keychain, and
the panel carries a standing badge naming who will answer.

That badge is now the control as well as the label. Leaving the choice in
Settings alone made it effectively permanent: switching meant summoning the
panel, abandoning the question, opening a window — the click that opens it
dismisses the panel — changing two settings, and starting over. In practice the
choice is per-question, since the local model reads text back perfectly well and
is worth leaving for a diagram or an unfamiliar interface. The menu also carries
"Send the screenshot", because that is the setting that decides whether a visual
question can be answered at all: without it OpenAI receives OCR text and guesses
at anything that is not words, which reads as the cloud model being no better.

**Region selection, which is not the rejected pointing feature.** Clicky has the
*model* point at UI elements. This has the *user* point, which needs no
coordinate mapping, no animation, and no multi-monitor arithmetic. It also costs
nothing at capture time: the screenshot is already in memory from the summon, so
selecting a region is a crop rather than a second capture, which cannot flicker
and cannot race a screen that changed in between. Two presets — *Explain this*
and *What's the next step?* — cover the questions worth a shortcut.

**Phase 3 finally exists.** Until now the two apps in this repository had never
exchanged a byte, despite the whole premise being one personal context system.
`TodoBridge` reads the Electron app's `app-data.json` and feeds open tasks into
the prompt, so "what should I work on" has something real to answer from. The
companion is sandboxed and cannot reach `~/Library/Application Support` on its
own; rather than switching the sandbox off, the user points at the file once and
a security-scoped bookmark carries the grant forward. Read-only, always.

#### Distribution reality

The full Clicky release pipeline — Developer ID export, Apple notarization,
stapling, Sparkle EdDSA signing, appcast — requires the paid Apple Developer
Program at $99/year. The available signing identity is `Apple Development`
only. `scripts/release-companion.sh` therefore stops at: archive, export, DMG,
GitHub release, and tells downloaders in the generated release notes that they
must right-click → Open once, and why. The three missing commands are recorded
in the script's header so the gap closes cheaply if a membership is ever bought.

---

### From Engram
Engram’s Context Layer: Engram is designed around the idea that raw information alone is not enough for an intelligent system to make good decisions; the system also needs to understand relationships, provenance, history, intent, and what information is relevant to the current situation. In its original engineering-focused form, Engram would connect artifacts such as repositories, pull requests, incidents, architectural decisions, documentation, services, and developer activity so that an AI agent could retrieve the right historical and organizational context before acting. For this personal companion, we are reusing only that underlying context philosophy rather than the full enterprise Engram architecture. The app will treat todos, projects, screenshots, notes, conversations, reminders, applications, focus sessions, saved links, and user-provided intentions as related pieces of context rather than isolated records. For example, a screenshot can be linked to a project, the reason it was saved, a task it supports, the application it came from, and a future condition under which it should be resurfaced. The context layer therefore becomes responsible for answering questions such as “Why did I save this?”, “What information is related to what I am working on now?”, “What was I trying to accomplish the last time I worked on this?”, and “Which past notes, screenshots, tasks, or conversations are relevant right now?” The important principle borrowed from Engram is that the companion should not merely remember data; it should maintain enough structured, temporal, and provenance-backed context to determine what matters now and why. This can initially be implemented with simple structured relationships and local persistence, adding semantic retrieval or embeddings only when they provide a clear benefit; the full Neo4j/Qdrant/LangGraph enterprise stack is not required for this project.

Do **not** embed the full B2B Engram system into this app.

Do not add enterprise-only complexity such as:

- GitHub organization ingestion
- PR graphs
- incident graphs
- service ownership
- engineering-org knowledge graphs
- heavy Neo4j infrastructure
- complex LangGraph agent pipelines

Instead, borrow Engram's **core ideas**:

- Context matters more than raw information
- Relationships matter
- Provenance matters
- Time matters
- "Why did this matter?" matters
- "What is relevant now?" matters
- Retrieval should depend on current context
- Historical context should be resurfaced when useful

For this personal project, those ideas apply to:

- Projects
- Todos
- Notes
- Screenshots
- Voice notes
- Saved links
- Conversations
- Reminders
- Focus sessions
- Intentions

---

### From the Existing To-Do Notifier

Keep the useful parts already built:

- Todos
- Due dates
- Lead-time reminders
- Overdue reminders
- Focus / Pomodoro
- Notes
- Tutor / Rubber Duck mode
- Voice interaction
- Menu bar functionality
- Existing companion/pet concept
- Local AI via Ollama
- Existing STT/TTS experimentation
- Local-first personal data

The existing Electron app is **not discarded immediately**.

It remains the working product while the native version is developed incrementally.

---

# 3. Core Product Concept

The central idea is not "AI screenshot organizer."

It is not "AI todo list."

It is not "AI that sees my screen."

It is:

> **A personal context layer that remembers the intention surrounding information and resurfaces the right context when it becomes relevant.**

A useful mental model:

```text
THING
+
WHY I CARE
+
WHAT IT RELATES TO
+
WHAT SHOULD HAPPEN
+
WHEN IT BECOMES RELEVANT
```

Examples:

> "Save this architecture diagram for when I work on Engram retrieval."

> "I want to read this paper before my next reliability write-up."

> "This job looks interesting. Remind me tonight when I am home."

> "This screenshot shows the API I want to test when I continue the native companion."

The system should remember more than the screenshot or note.

It should remember the **reason** it was saved.

---

# 4. The Main Interaction Loop

The most important loop is:

```text
CAPTURE
   ↓
INTENT
   ↓
CONTEXT
   ↓
STORE
   ↓
RETRIEVE / RESURFACE
   ↓
ACTION
```

### Capture
Something enters the system:

- Screenshot
- Text note
- Voice note
- Link
- File
- Todo
- Conversation
- Manual save

### Intent
I explain why it matters.

Example:

> "This might solve the multi-monitor coordinate problem. Bring it back when I continue ScreenCaptureKit."

### Context
The app associates it with:

- Project
- Task
- Topic
- App
- Time
- Current activity
- Reminder condition

### Store
The system stores the item and its meaning.

### Retrieve / Resurface
Later:

> "What was that ScreenCaptureKit thing I saved?"

or the app notices that I am back in the relevant project and surfaces it.

### Action
The context can lead to:

- Open item
- Create/update todo
- Remind later
- Mark done
- Add to project
- Ask AI about it

---

# 5. Screenshot / Context Capture

This remains an important feature, but **not the entire product thesis**.

## Mac flow

When I take a screenshot:

```text
Screenshot created
      ↓
Companion notices it
      ↓
"Add context?"
      ↓
Voice / Text / Ignore
      ↓
Save Context Object
```

Possible interaction:

> "This was the Swift API Clicky uses. Check it when I work on screen awareness."

Store:

```text
SavedContext
- image
- user_context
- AI_summary
- project
- topics
- source_app
- created_at
- optional reminder
- provenance
```

The **user's explanation has higher authority** than the AI's guessed interpretation.

---

## iPhone flow — later

Do **not** build a full iPhone version immediately.

First validate simple ingestion.

Initial possible flow:

```text
iPhone Screenshot
      ↓
Share Sheet / Shortcut
      ↓
"Save to Companion"
      ↓
Type or dictate context
      ↓
Send to Companion Inbox
```

Possible transport for the personal version:

- iCloud Drive folder
- lightweight backend later
- native iOS share extension later

A full iPhone app is only justified when I repeatedly need:

- Browsing saved context
- Completing todos
- Rescheduling reminders
- Asking the companion questions away from Mac
- Receiving rich actionable push notifications

---

# 6. Reminder System

The current reminder system should evolve from local-only notifications into a **channel-based reminder architecture**.

Conceptually:

```text
                 Reminder Engine
                       │
        ┌──────────────┼──────────────┐
        ↓              ↓              ↓
   macOS local       Email         Push later
   notification      fallback       (iOS)
```

Possible future channels:

```swift
enum DeliveryChannel {
    case local
    case email
    case push
    case imessageExperimental
}
```

## Important rule

Do not depend on the home Mac being awake for critical remote reminders.

The Mac can sleep, reboot, lose Wi-Fi, or the app can close.

Remote reminders should eventually come from a small cloud scheduler/service.

Only minimal reminder data needs to leave the Mac:

```text
todo_id
title
due_at
remind_at
status
delivery_channel
```

Sensitive personal context can remain local unless explicitly needed.

---

## iMessage

iMessage can be a **fun experimental personal channel**, but not the foundation.

Why:

- Great user experience
- Feels like the companion is messaging me
- No iPhone app required

But:

- Automation depends on the Mac
- Mac must be awake
- Messages must be logged in
- Not a robust server-side product API

So:

```text
Local notification → dependable on Mac
Email → reliable remote fallback
iMessage → optional personal experiment
Push → best long-term mobile delivery
```

---

# 7. Native macOS Architecture

The new native app should use:

### Swift
Primary native language.

### SwiftUI
For:

- Main settings UI
- Lists
- Todos
- Notes
- Project views
- Normal app surfaces

### AppKit
Use when native window behavior matters:

- Floating companion
- Transparent windows
- NSPanel
- Cursor-relative windows
- Overlay windows
- Window levels
- Menu bar integration
- Advanced event handling

### ScreenCaptureKit
For:

- Current-screen capture
- Window/display context
- Multi-monitor handling
- Excluding the app's own UI from screenshots

### Accessibility APIs / AXUIElement
Potentially for:

- Active UI semantics
- Selected text
- Application/window context
- More intelligent context than raw screenshots alone

**Decision: not used, and now deliberately unnecessary.** The last thing this was wanted for was
pointing at a control Max had named. That shipped in Phase 10 without it, on the OCR word boxes
Vision was already producing, and the OCR route turned out to be *better* rather than merely
permission-free — see that phase for the reasoning. Application and window context comes from
`NSWorkspace` and ScreenCaptureKit, which need no such grant.

Granting the permission by hand on the developer's own machine does not change this. A grant on one
machine is not a property of the product; every downloader would still have to be asked.

### AVFoundation / Speech
For native voice/audio work.

### SwiftData or SQLite
For the first native persistent model.

Start simple.

Do **not** introduce Neo4j just because relationships exist.

### Keychain
For API keys/secrets.

### Ollama
Can remain local.

Native Swift can call its HTTP API directly.

---

# 8. Context Data Model

Avoid building everything as unrelated arrays such as:

```text
todos[]
notes[]
screenshots[]
```

Move gradually toward a reusable context model.

Possible primitives:

```text
Artifact
Intent
Project
Task
Reminder
Context
Relationship
Event
Source
Conversation
```

### Example

```text
Artifact
  └─ screenshot

Intent
  └─ "Use this when working on retrieval"

Project
  └─ Engram

Task
  └─ Improve retrieval architecture

Relationship
  screenshot → RELATES_TO → Engram
  screenshot → CREATED_FOR → retrieval task
  intent → EXPLAINS → screenshot
```

This gives the system the ability to answer:

> "Why did I save this?"

> "What have I saved for Engram?"

> "What context matters for what I'm doing right now?"

---

# 9. Migration Strategy: Do NOT Rewrite Everything

Do not do:

```text
Electron app
   ↓
2-month full rewrite
   ↓
same application in Swift
```

That creates work without creating new capability.

Instead:

```text
To-do-notifier/
├── electron/
├── src/
├── docs/
├── ...
└── TodoCompanion/          # native macOS app (Xcode project)
    ├── TodoCompanion.xcodeproj
    └── TodoCompanion/
```

The Xcode project uses a **file-system synchronized group**, so any `.swift` file
added under `TodoCompanion/TodoCompanion/` joins the target automatically. That
removes the main reason to hand-edit `project.pbxproj`.

Build new native functionality in vertical slices.

Keep the Electron app usable during the transition.

Only migrate older features when the native architecture benefits from it.

---

# 10. Xcode + Cursor Workflow

Use both.

## Cursor

Primary source-code editor / AI coding environment.

Use it for:

- Swift source
- SwiftUI
- AppKit source
- Models
- Networking
- Tests
- Refactoring
- Codebase navigation

## Xcode

Use for:

- Creating the macOS project
- Build / Run
- Debugging
- Signing
- Capabilities
- Entitlements
- Permissions
- Asset catalogs
- Instruments
- Target settings
- Project configuration

Both edit the same files on disk.

### Important

Avoid letting Cursor blindly modify:

```text
project.pbxproj
```

unless necessary.

Let Xcode manage:

- Targets
- Signing
- Capabilities
- Resources
- Entitlements
- Build settings

---

# 11. Development Roadmap

## Phase 0 — Setup

- [x] Install Xcode
- [x] Create native macOS project
- [x] Save it inside the existing repository
- [x] Open the native project folder in Cursor
- [x] Confirm build/run from Xcode
- [x] Create clean Git branch for native work (`native-companion`)

Actual path:

```text
TodoCompanion/
```

Deployment target is macOS 26.5, App Sandbox is on, and the sandbox grants
outgoing network connections only (needed to reach Ollama on localhost).

---

## Phase 1 — Native Companion Prototype

Goal:

> Build something genuinely new before migrating old UI.

First vertical slice:

```text
Global hotkey
      ↓
Floating native companion appears
      ↓
Capture current screen
      ↓
Send image + prompt to AI
      ↓
Show answer beside companion
```

Build:

- [x] Menu bar app (`MenuBarExtra` + `.accessory` activation policy, no Dock icon)
- [x] Floating companion `NSPanel` (`.nonactivatingPanel`, joins all Spaces)
- [x] Transparent background (`.ultraThinMaterial` over a clear window)
- [x] Drag / position (`isMovableByWindowBackground`)
- [x] Cursor-relative placement (clamped to the visible frame of the cursor's screen)
- [x] Global hotkey (⌃⌥Space via Carbon `RegisterEventHotKey` — no Accessibility permission)
- [x] ScreenCaptureKit screenshot (display under the cursor)
- [x] Exclude own companion window (`SCContentFilter(excludingApplications:)` by bundle ID)
- [x] AI request (streaming Ollama `/api/generate`)
- [x] Response bubble (token-by-token, selectable text)

Deliberate choice for the first slice: the screenshot is OCR'd on-device with
Vision and only the **recognized text** is sent to the model. That works with the
`llama3.2` model already installed, keeps pixels on the Mac, and matches the
privacy principles in section 12. Sending the raw image is a toggle in Settings
for when a vision model is pulled.

Still open from this phase:

- [x] Visual "listening"/streaming animation beyond the status dot (a ring at the
      cursor: blue while capturing, pink with a live audio waveform while listening)
- [x] Configurable hotkey (a picker of non-reserved combos in Settings)
- [x] Multi-monitor: every attached display is captured for one question, with the
      one under the cursor as primary and the others supplied as labelled text

This teaches:

- Swift
- SwiftUI
- AppKit
- Xcode
- Permissions
- Async Swift
- Native windows
- ScreenCaptureKit
- Signing / entitlements

---

## Phase 2 — Voice

Add:

- [x] Push-to-talk (⌘D, or the mic button, toggles a dictation session)
- [x] Speech-to-text (`SFSpeechRecognizer` forced on-device; the panel says which)
- [x] Voice response (`AVSpeechSynthesizer`, off by default, sentence at a time).
      Reversed once conversations arrived: the earlier reasoning was right about
      a one-shot answer and wrong about a multi-turn one. Being walked through
      an interface means looking at the interface, not at the panel, and a
      hosted voice was never on the table — the ban on cloud transcription
      applies in reverse.
- [x] Visual listening state (pink ring at the cursor, driven by real input level
      so a muted or wrong input device is visible rather than silent)
- [x] Stop / cancel control (⌘D again, Esc, or silence)

Do not add wake-word monitoring, now or later. See §13: it means an always-hot
microphone in an app built on capture being explicit, and the hotkey already
costs one keystroke.

Half duplex is a requirement rather than a simplification: the synthesizer plays
through the speakers and the recognizer would transcribe it, so speaking stops
whenever dictation starts.

Two things worth recording from building this. The audio engine has to be
recreated per session — a retained `AVAudioEngine` caches a zero-channel input
format and then yields silence forever. And the input level meter turned out to
matter more than the waveform it draws: dictation failing because the default
input is a pair of AirPods in another room is indistinguishable from dictation
being broken, unless the UI shows that no sound is arriving.

---

## Phase 3 — Existing Productivity Context

Connect the companion to existing app state.

The companion should answer:

> "What should I work on?"

using:

- [x] Todos (`TodoBridge`, read-only through a security-scoped bookmark)
- [x] Due dates (overdue tasks are labelled as such in the prompt)
- [x] Notes
- [x] Current project (narrows the task list to that project's own tasks)
- [~] Focus session — **dropped, not pending.** It lives in the Electron app's
      runtime rather than its data file, so there is nothing on disk to read.
      Getting it would mean an IPC channel between the two apps, which is more
      coupling than "what should I work on" is worth, and would break the
      one-way file contract that keeps neither app writing the other's data.

The migration question this phase left open answered itself: nothing migrates.
The two apps stay separate and exchange one file each, for the reasons in
"Why the two apps were not merged" below.

---

## Phase 4 — Context Capture

Add native capture:

- [x] Manual-save screenshots (⌘S in the companion panel)
- [x] Quick context bubble (the companion panel doubles as it)
- [x] Voice note (⌘D dictates straight into the reason field, so speech and
      typing are one input rather than two kinds of note)
- [x] Text note (the panel's field is the intent field)
- [x] Ignore (Esc discards without saving)
- [x] Topic extraction (`#tags` typed inline — user-authored, not inferred)
- [x] AI summary (generated in the background, stored in its own field)
- [x] Original user intent (authoritative, never overwritten)
- [x] Search (plain text across intent, summary, topics, app, window, screen text)
- [x] Project association (chosen in the panel before saving, reassignable in the
      library, which also browses by project)

**Built on SwiftData**, not Neo4j — per section 7. The schema is two models,
`SavedContext` and `Project`, with one relationship between them.

The privacy rule from section 12, *"never pretend AI inference is user-authored
intent,"* is enforced structurally rather than by convention: `intent` and
`aiSummary` are separate stored properties and the library labels them
"Why I kept this" and "What the model thinks it shows" respectively.

First "magic moment":

> "What was that screenshot I saved about ScreenCaptureKit?"

And the app retrieves it with the original reason I saved it.

**This now works** via search in the Saved Context window, which since Phase 5
matches by meaning as well as by words — "screen capture" does now find a note
that only says "display grabbing". That was deferred until structured retrieval
worked first, per this plan's own rule, and it was.

---

## Phase 5 — Contextual Retrieval

Add:

- [x] Semantic search (opt-in, local embeddings via `nomic-embed-text`)
- [x] Project-aware retrieval (a save in the current project scores 3.5, above
      any single screen signal, and says so: "in Engram")
- [x] Time-based retrieval (recency weighting, deliberately weak)
- [x] Provenance (app and window stored and shown on every match)
- [x] Related context (scored against the current screen on each summon)
- [x] "Why did I save this?" (the intent field, surfaced verbatim)
- [x] "Show me everything related to X" (text search in the library)

Embeddings were added here, after structured retrieval worked and not before.

**Structured retrieval now works.** `ContextRetriever` scores saved items against
the current screen using signals the user can reason about:

| Signal | Weight |
|--------|--------|
| Belongs to the project the user says they are working on | 3.5 |
| A `#topic` literally visible on screen | 3.0 each |
| Same window title | 2.5 |
| Same application | 2.0 |
| Words shared between the saved reason and the screen | 1.2 each, up to 3.0 |
| Close in meaning (opt-in) | up to 2.2, scaled from a 0.55 floor |
| Recency | up to 1.0, decaying over 30 days |

Anything under 2.0 is dropped. Every match carries a human-readable reason
("same window", "#engram", "mentions retrieval") which is shown in the panel —
resurfacing without an explanation is indistinguishable from the app guessing.

That explainability was the reason to hold embeddings back, and it became the
condition on adding them rather than a reason to refuse them forever. Meaning is
one signal inside the structured score, not a replacement for it: it carries the
reason "close in meaning", it can only ever add, and it is weighted below "same
window" on purpose — a shared window title is a fact, a resemblance is not. With
the feature off, scoring is exactly what it was before. In library search a save
that literally contains the typed words is never ranked below a resemblance.

The floor is 0.55 because embedding models have a high similarity floor rather
than a zero one. Measured with `nomic-embed-text`, plainly unrelated pairs score
0.31–0.40 while related ones score 0.62–0.69, so the threshold sits in that gap
and the contribution scales from it rather than from zero.

Embedding runs locally and is kept off the `Brain` protocol exactly as
`summarize` is. It is in fact the worst thing to export, because it runs once per
save rather than once per question: the volume is the whole library, not one
deliberate ask. It covers the user's reason, their topics, and the model's
one-line gloss, but deliberately not the raw OCR text, which would swamp a
one-sentence reason and make every save from the same editor look alike.

Known rough edge to tune with real use: "same app" alone clears the threshold, so
once there are many saves from one editor the top three may be dominated by it.
A test pins that behaviour deliberately, so changing it has to be a decision
rather than a drift.

Writing those tests corrected one of these weights. Shared words were originally
worth 0.8 each against a threshold of 2.0, which meant the user's own reason had
to echo **three** distinctive words on screen before it counted for anything —
while sitting in the same application, which says nothing about relevance,
qualified on its own at 2.0. The strongest available signal was weaker than the
weakest one. Two shared words now clear the bar; one still does not.

---

## Phase 6 — Selective Resurfacing

The companion should become proactive **carefully**.

Started, in the least intrusive form available: matches surface **only on an
explicit summon**. There is no background polling, no timer, and no capture the
user did not ask for. The "continuous screenshots + an LLM call every few
seconds" pattern this section warns against is still avoided entirely.

Potential cheap signals:

- Active application changes
- Active window title
- Project opened
- Focus session begins
- Scheduled commitment
- Manual context event
- Accessibility event

Only escalate to vision/LLM when useful.

Avoid:

```text
continuous screenshots
+
LLM call every few seconds
```

Reasons:

- Expensive
- Creepy
- Wasteful
- Bad privacy
- Bad battery usage
- Likely annoying

The goal is:

> **High relevance, low interruption.**

### Decision: stopping here

This phase is **closed at the summon-only form**, not left pending. The reasoning
is worth keeping, because "make it proactive" is the obvious next idea and it is
the wrong one for this app.

The trigger has to be free of Accessibility permission, which rules out
everything on the list above except application activation from `NSWorkspace`.
Window titles are available only for the frontmost app, and focus sessions live
in the Electron app's runtime rather than its data file, so they cannot be read
at all. What is left is "the user switched apps" — a signal that says nothing
about whether they need anything.

Acting on it then forces a choice with no good side. Matching on a window title
alone is cheap and nearly always wrong, because a title is a filename. Matching
on screen contents means capturing without being asked, which contradicts the
rule that capture is always explicit — the one thing that makes this app
defensible to run all day.

And the interruption budget is tiny. A companion that is right 30% of the time
and speaks up unprompted is worse than one that is right 30% of the time when
asked, because the wrong 70% now costs attention that was being spent elsewhere.
Being summonable is not a weaker version of being proactive; for this kind of
tool it is the better product.

Retrieval-on-summon already delivers what the phase was for: relevant past
material appears next to the answer, explained, at the moment the user has
demonstrably chosen to pay attention. That is high relevance and zero
interruption, which beats the stated goal rather than falling short of it.

---

## Phase 7 — Remote Reminders

Local reminders came first, and they cover most of what this phase was for.

- [x] Reminder on a saved context (`remindAt`, scheduled through
      `UNUserNotificationCenter`, cancellable from the library)
- [x] Natural-language time from the saved reason ("remind me tomorrow at 4")
- [x] Notification opens the library at the thing it is about

The design rule that matters here: the parser may **offer** a time but only arms
the reminder itself when the user explicitly asked to be reminded. A date merely
mentioned in passing is offered switched off, and the time chosen is always shown
along with the words it was read from. Setting a reminder from inference would be
exactly the "present model inference as the user's intent" failure this project
is built to avoid.

`remindAt` had existed on the model since Phase 4 with nothing reading or writing
it — a field that implied a feature that was not there. Worth noting as a failure
mode of its own: schema is not behaviour.

- [x] Quiet hours (mirrored from the Electron app rather than reinvented)

- [x] Delivery to other devices, by writing dated tasks into an iCloud
      Reminders list (`ReminderMirror`, `AppleReminders`)

What is still genuinely remote-only, and therefore still open:

- [ ] Minimal cloud reminder model
- [ ] Email channel
- [ ] Retry logic
- [ ] Delivery state
- [ ] Escalation logic
- [ ] Optional experimental self-iMessage

The honest limitation of a local notification is that it needs this Mac awake at
the time it fires, and that was named here as the one thing a hosted scheduler
would actually buy. Most of what it would buy turns out to be purchasable for
nothing: Apple runs a scheduler already, and a reminder written into an iCloud
list is delivered to the phone and the watch with no server, no push
certificate, and no paid developer programme. So the away-from-Mac case is now
covered by a publish into Apple Reminders, on the same footing as
`ProjectExport` — one-way, never read back as truth.

That does not close the rest of this phase, and it is worth being clear about
what it does not buy. There is no delivery state, so nothing here knows whether
an alert was seen; there is no escalation and no retry; and the mirror is only
as current as the last time the app was summoned, because this app reads the
task list on summon rather than polling. A hosted scheduler is still the answer
to those. It is no longer the answer to "I am not at my Mac", which was the only
part of it the user actually felt.

Two consequences worth recording, because both are the kind of thing that reads
as a broken feature rather than a refused one. Only tasks **still ahead** are
copied: an `EKAlarm` whose date has passed is delivered as soon as it syncs, so
mirroring a backlog would set off every overdue task at once, on every device,
the moment the switch was flipped. And the list must be created in a **syncing**
source — `defaultCalendarForNewReminders` may sit in the local account, where
everything here works and nothing ever reaches the phone, so that state is named
in Settings instead of discovered later.

Native reminders respect the quiet hours already configured in the Electron app,
read through the same read-only bridge. Two notification systems disagreeing
about one do-not-disturb setting is worse than one of them ignoring it, because
the disagreement is invisible until a reminder fires at 2am.

### Why the two apps were not merged

Folding the Electron app into the native one was considered once projects existed
on one side and tasks on the other. Measured, it is ~3,100 lines in `electron/`
and ~4,400 in `src/`: more than twice the native app's size, to arrive at feature
parity with something that already works.

Worse, about a third of it should not be ported at all. The pet is ~1,300 lines
built on copyrighted art that cannot ship, and the voice stack is ~950 lines
using cloud TTS that section 12 forbids. And the real boundary is not the
runtime, it is the product: the Electron app is a gamified study companion
(pet, streaks, flashcards, Socratic tutoring, pomodoro) and the native one is a
context and memory tool. Merging them yields a split personality rather than one
coherent app.

What they genuinely share is a task list, so that is what is shared. A project
can hold tasks from the to-do app, with the link stored on this side —
`Project.linkedTodoIDs` — so the companion never becomes a writer of a file it
does not own. Completing a task stays where tasks live.

### Making the shared view mutual

- [x] Publish projects for the to-do app to read (`ProjectExport`)
- [x] Read them there (`electron/lib/companionProjects.cjs`) and label tasks by project
- [x] Filter the task list by project
- [x] Tests on both sides of the contract
- [x] Publish reminders as task requests, and create real tasks from them there
      (`electron/lib/companionTasks.cjs`), keyed on the reminder's own identifier
- [x] Keep the announcing in the companion, and skip those tasks in the to-do
      app's nag sweep, so one thing pings once

A grouping only the companion could see was half a feature: the point of putting
tasks in a project is to look at that project's work, and the to-do list is where
work actually gets done.

The obvious way to do it — a `project` field on `TodoItem` in `app-data.json` —
is the one to avoid. That file is owned by a running Electron process that holds
it in memory and rewrites it whole, with no locking; a sandboxed second writer
would eventually lose an edit or truncate the file. It also cannot work in
principle, because a project groups saved screens as well as tasks, and the
to-do app has no concept of a saved screen to hang the other half on.

So the arrangement is symmetric instead: **each app owns one file and reads the
other's.** `TodoBridge` reads tasks, notes, and quiet hours in;
`ProjectExport` writes the project list out. The export lands in the companion's
own sandbox container, which is the only place it can write unprompted, and the
Electron app is unsandboxed so it can read there. Republishing is driven off
`ModelContext.didSave` rather than called from each place that edits a project,
because those are scattered across the panel and the library, and a new one that
forgot to publish would leave the other app quietly showing stale names.

The consequence to keep in mind: the to-do app shows project **labels and a
filter**, and nothing more. It cannot create a project or move a task between
them, because it does not own the list. That asymmetry is deliberate and should
stay visible in the UI rather than being smoothed over.

### Reminders as tasks

A reminder set in the companion is a time on a kept screenshot, not a to-do, and
for a while it left no trace in the app that owns tasks — so "remind me to text
voice bugs" was invisible in the only list the user actually works from. The fix
follows the rule that already governs file edits: **the companion proposes, the
owner writes.** `ProjectExport` publishes `requestedTasks`, and the to-do app
creates real tasks from them.

Importing rather than mirroring is the point. A task created there is genuinely
that app's, so it can be completed, rescheduled and notified like any other,
where a read-only list would have looked identical and done none of it. The
companion still never writes `app-data.json`.

Idempotency rests on the id — `companion:` plus the reminder's own identifier,
which is stable across launches and store migrations. The import runs repeatedly
by design, so anything less stable would add the same task over and over. An
already-imported id counts whether the task is open or **done**: bringing back
something the user has ticked off is the failure that would make this unusable.

Two things were got wrong first time round and are worth recording, because both
failed *silently* in the direction of the feature appearing not to exist.

The import was hung off the to-do panel mounting, so it only ran when that panel
was on screen — and the app can start hidden into the tray, with no window at
all. It now runs in the main process, at startup and on the same tick as the
reminder sweep; the IPC handler remains only so that returning to the window
picks up something set moments ago. And only *future* reminders were published,
which meant "remind me in one minute" left the export a minute later: unless the
to-do app happened to be open inside that minute, the task was never created. A
fired reminder is now still offered for a bounded window, and arrives overdue —
which is how that list already talks about anything missed. Bounded, because the
import keys on a stable id, so an unbounded offer would resurrect a task the user
deleted, forever.

The notification stays with the companion, which scheduled it when the user set
the reminder; the to-do app shows and completes the task but skips it in its nag
sweep. The first design handed ownership over instead — the companion watched for
the task through the read-only bridge and then cancelled its own notification —
which worked, but made delivery of a reminder depend on whether a second app had
run yet. Stating ownership once, in the app that took the request, does the same
job with none of that.

Later:

- [ ] iOS push

---

## Phase 8 — iPhone Capture

Before a full iOS app:

- [x] Create "Save to Companion" Shortcut (the recipe is in the companion's README)
- [x] Share screenshot/link/photo (share-sheet Shortcut, base64 into one manifest)
- [x] Dictate/type reason (Ask for Input, which dictation works in)
- [x] Send into Companion Inbox (a folder, via `InboxImporter`)
- [x] Sync to Mac (iCloud Drive carries the folder; import on launch and on each summon)

Only build a native iOS client when the Shortcut becomes limiting.

**The inbox is a folder, not an iCloud container.** A container needs an
entitlement that requires the paid Apple Developer Program, which this project
does not have. A folder *inside* iCloud Drive needs no entitlement at all and
syncs identically, so access goes through a user-chosen security-scoped
bookmark — the same mechanism as the to-do bridge, and the same reason: the user
picking the folder is what grants a sandboxed app access to it. As a side effect
the transport also works over Dropbox, Syncthing, or no sync at all.

The image travels base64-encoded inside a single JSON manifest rather than as a
paired image file. Two files sharing a base name was the obvious alternative and
is worse over a syncing folder: the halves arrive independently, so a reader can
see a manifest whose image has not landed yet and cannot distinguish that from
one that is never coming.

Importing removes what it imported, because the folder is a transport rather
than storage. A manifest that *fails* to parse is deliberately left in place —
deleting it would destroy something the user captured, and its staying put is
the only signal they get that anything went wrong. An item with a reason and no
image is accepted, since a thought captured on a walk is much of the point. An
image with no reason is refused: the reason is what this app is built around,
and supplying one by inference is the exact failure §12 forbids.

---

## Phase 9 — Conversation

The panel was one-shot: ask, read, dismiss. That is fine for "what does this
error mean" and useless for the thing it should be best at — standing next to an
unfamiliar interface while you are taken through it.

- [x] Multi-turn conversation, with earlier turns replayed into the prompt
- [x] Re-capture that keeps the transcript (⌘L), and a fresh start that keeps
      the capture (⌘K)
- [x] A named assistant, Max, as tone in the prompt and the UI
- [x] Spoken answers, local, off by default (see Phase 2)
- [x] A proposed change to one user-picked file, applied only from a diff
- [x] Conversations kept with the save they were about (`ConversationTurn`)
- [x] A graph view of saves, projects, topics and apps, on the existing
      relationships rather than a graph database

**Conversations are kept, not collected.** §2 always listed conversations among
the things the context layer should relate, and Phase 9 initially built them as
panel state that Esc discarded. They are now written by ⌘S and only by ⌘S: most
summons are throwaway, and saving all of them would fill the library with
material the user never chose to keep, which inverts the rule the rest of the
app runs on. The transcript joins literal search but deliberately not the
embedding source — most of its length is the model's words, and embedding those
would let what Max said drive what gets resurfaced.

**The graph needed a view, not a store.** §7 says not to introduce Neo4j merely
because relationships exist, and this is the check on that: the edges were
already there in SwiftData, so a graph database would have added infrastructure
and no information. The layout is deterministic so the same library always draws
the same picture, which is the difference between a diagram you can learn and
one that is only a demo.

**History is capped.** The screen text already dominates the prompt, so an
unbounded transcript would push it out of a small local model's context window
and answers would degrade the longer you talked — precisely backwards.

**Max is not the bundle name.** TCC keys the Screen Recording grant to the
signature and identifier, the SwiftData container is derived from the identifier,
and `companionProjects.cjs` hardcodes it. A rename would silently cost the
permission and the database and break the other app's project labels.

**The persona is fenced.** A warm voice is the standard way grounding rules get
loosened without anyone deciding to loosen them, so the prompt says outright that
a persona does not license inventing what is on screen or softening an "I don't
know". `Prompt.summarySystem` is the same rule inverted: a background gloss is a
label in a list and gets no persona at all. Summaries went through `answerStream`
and inherited the teacher's instructions, which measurably worsened them.

**Preset wording can never become a stated reason.** Asking clears the field, so
⌘S afterwards falls back to the first question the user typed — but never to
"Explain what this is", which is this app's sentence. `intent` is a promise about
whose words are in it, and a convenience is exactly where that promise would
have broken quietly.

**Editing is a proposal, not an action.** Same shape as the reminder parser:
inference may offer, only the user commits. One file, chosen through a picker, a
locally-computed diff, and a write that happens on a button press. The model
returns a whole file rather than a patch because wrong diff line numbers are far
more common than a mangled file, and a diff computed here from both versions
cannot misreport what changed. A reply whose fence never closed is refused
outright — a truncated file written over the user's own is the worst available
outcome.

## Phase 10 — Pointing at the screen

- [x] Per-word OCR boxes kept from Vision, asked for by character range
- [x] `ScreenTextLocator`, matching a finished answer against them
- [x] `ScreenHighlight`, a box drawn briefly around the match
- [x] The prompt asks Max to quote a control's label verbatim
- [x] Offered on a button that names the match, never drawn automatically
- [~] Moving the cursor to the control — rejected, see below

Closes the last thing §7 wanted `AXUIElement` for. An answer that says to click
"Fairlight" now offers a **Show me "Fairlight"** button, and ⌘P boxes those words
on the actual screen. The box outlives the panel, so the user can press it, click
into the application, and still see where they were pointed.

**Accessibility was rejected on merit, not only on permissions.** The obvious
build is Clicky's: traverse the frontmost app's accessibility tree, find the
element, read its position. It needs the one permission this project has refused
throughout — and it fails in Qt, Electron, and games, which includes DaVinci
Resolve, the application that motivated the feature.

The argument that settles it is a symmetry that only becomes visible once the
model is in the loop: **Max can only name what it can read.** It is shown a
screenshot, so its words are words Vision already has. An accessibility tree's
extra coverage is therefore mostly controls Max could never have referred to,
while its blind spot is the exact application in question. Reading pixels works
wherever the user can see, which is the only place that matters here.

The owner granting Accessibility to this bundle by hand did not change the
decision. A grant on one machine is not a property of the product.

**A line box would have been useless.** Vision returns a recognized *line*, and a
menu bar comes back as one — so the line's box covers half the screen. Words are
located individually by character range and recombined into multi-word labels,
which is what makes the box tight enough to mean something.

**Matching would rather find nothing than the wrong thing.** A quoted label wins,
because the prompt asks Max to quote the label it means and that is the model
stating its intent rather than us inferring it from prose. An unquoted candidate
must be long or multi-word and must not be a word Max uses to *describe*
controls — "menu", "panel", "button" would otherwise point at wherever that word
happens to be printed. So an unlabelled glyph is unfindable and no button
appears, which is correct: Max describes those positionally, and a confident box
over the wrong icon is worse than none.

**It highlights and does not move the pointer.** Same rule as editing and
reminders, in its third instance: inference may suggest, only the user acts.
Moving the cursor would also fight anyone mid-drag. And it runs from a button
rather than after every answer, because most answers are not directions to a
control, and drawing on the user's screen unasked is the app acting on inference.

---

# 12. Privacy Principles

Because the app can eventually know a lot about the user's computer, privacy is a core engineering constraint.

Principles:

- Local-first by default
- Explicit screen capture
- Visible microphone state
- Clear permission boundaries
- Do not silently collect everything
- Do not continuously upload desktop activity
- User-provided context outranks model inference
- Minimal cloud data
- API keys in Keychain
- Make saved context inspectable/deletable
- Make proactive behavior optional
- Exclude companion UI from screen capture
- Never pretend AI inference is user-authored intent

---

# 13. What NOT to Build Right Now

Avoid scope explosion.

Do not build:

- Full iPhone clone of the Mac app
- Android app
- B2B/team product
- Full Engram enterprise graph
- Neo4j infrastructure unless real need appears
- Complex LangGraph orchestration
- Continuous screen recording
- Full autonomous computer-use agent. Narrowed rather than abandoned: Max may
  propose a change to **one file the user picked**, shown as a diff, applied
  only by a button press. The reason to stop there is product quality before
  safety — this app sees a screenshot, has no file tree, and cannot run the
  tests, so a project-wide agent here would be strictly worse than the editor
  already open on the same machine. What it uniquely offers is answering about
  the code currently on screen
- Wake words and always-listening modes. "Hey Max" needs a hot microphone in an
  app whose screen capture is explicit and whose mic state is deliberately
  visible, and the hotkey is already one keystroke with no Accessibility
  requirement. The Electron app's own wake word ships off by default
- Cloud speech **synthesis**. Spoken answers are built, using the macOS voices;
  a hosted voice would export the screen to a vendor that is not answering the
  question
- Calendar/email integrations immediately
- Social features
- SaaS billing
- YC pitch deck
- Startup branding exercise
- Multi-user authentication unless needed for remote sync
- Cursor-pointing / element-highlighting overlays (see §2, rejected from Clicky)
- Anything requiring Accessibility permission
- Cloud speech-to-text
- Hosted LLMs doing **background** work — summaries, categorisation, anything
  unprompted. Answering a question the user explicitly asked is now allowed and
  opt-in; see the third pass in §2 for why that ban was narrowed rather than
  kept whole
- Usage analytics of any kind

This is a **personal project first**.

Use it.

Notice what is genuinely useful.

Then expand.

---

# 14. What Would Make This Project Successful

The success test is not GitHub stars.

It is whether I personally start relying on it.

Examples:

> "I would have forgotten that if the companion had not brought it back."

> "I don't lose screenshot context anymore."

> "I can ask why I saved something."

> "The app knows which tasks and saved information relate to the project I am working on."

> "I trust its reminders."

> "I use the companion instead of opening five different productivity tools."

If those happen repeatedly, the project is working.

---

# 15. Possible Long-Term Vision

If the project continues to prove useful, it could become:

> **A personal context runtime for macOS and eventually iPhone.**

The companion is the interface.

The underlying system understands:

```text
Tasks
Screenshots
Notes
Projects
Intentions
Conversations
Reminders
Files
Activity
Relationships
History
```

and tries to answer one fundamental question:

> **Given what I am doing now, what context from my past intentions is relevant?**

Possible future interactions:

> "Why did I open this?"

> "What was I researching yesterday?"

> "What did I save for this project?"

> "I have 45 minutes. What should I work on?"

> "I'm back in this codebase. What was I trying to solve?"

> "Bring back the things I said I would revisit."

> "Remind me about this when I return to Xcode."

---

# 16. One-Sentence North Star

> **Build a native personal companion that connects what I am doing now with what I previously intended to remember, revisit, or complete.**

---

# 17. Immediate Next Step

Do not start with the full context system.

Start here:

```text
Xcode macOS project
        ↓
Native floating companion
        ↓
Global hotkey
        ↓
Capture current screen
        ↓
Ask AI
        ↓
Native response bubble
```

Once that works reliably, connect the companion to the existing To-Do Notifier data and begin adding persistent context.

That is the first real milestone.
