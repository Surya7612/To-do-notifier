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
- [ ] Create clean Git branch for native work

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

- [ ] Visual "listening"/streaming animation beyond the status dot
- [x] Configurable hotkey (a picker of non-reserved combos in Settings)
- [ ] Multi-monitor: capture the display under the cursor is done; capturing *all*
      displays for one question is not

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

- [ ] Push-to-talk
- [ ] Speech-to-text
- [ ] Voice response
- [ ] Visual listening state
- [ ] Stop / cancel control

Do not add wake-word monitoring immediately.

---

## Phase 3 — Existing Productivity Context

Connect the companion to existing app state.

The companion should answer:

> "What should I work on?"

using:

- Todos
- Due dates
- Focus session
- Notes
- Current project

At this stage, begin deciding how old Electron data migrates into the new native store.

---

## Phase 4 — Context Capture

Add native capture:

- [x] Manual-save screenshots (⌘S in the companion panel)
- [x] Quick context bubble (the companion panel doubles as it)
- [ ] Voice note (waits on Phase 2)
- [x] Text note (the panel's field is the intent field)
- [x] Ignore (Esc discards without saving)
- [x] Topic extraction (`#tags` typed inline — user-authored, not inferred)
- [x] AI summary (generated in the background, stored in its own field)
- [x] Original user intent (authoritative, never overwritten)
- [x] Search (plain text across intent, summary, topics, app, window, screen text)
- [ ] Project association (`Project` model and relationship exist; no UI to assign one yet)

**Built on SwiftData**, not Neo4j — per section 7. The schema is two models,
`SavedContext` and `Project`, with one relationship between them.

The privacy rule from section 12, *"never pretend AI inference is user-authored
intent,"* is enforced structurally rather than by convention: `intent` and
`aiSummary` are separate stored properties and the library labels them
"Why I kept this" and "What the model thinks it shows" respectively.

First "magic moment":

> "What was that screenshot I saved about ScreenCaptureKit?"

And the app retrieves it with the original reason I saved it.

**This now works** via text search in the Saved Context window. It is not yet
semantic — searching "screen capture" will not match a note that only says
"display grabbing." Embeddings are deliberately deferred to Phase 5, per the
plan's own rule about not adding them before structured retrieval works.

---

## Phase 5 — Contextual Retrieval

Add:

- [ ] Semantic search
- [ ] Project-aware retrieval
- [ ] Time-based retrieval
- [ ] Provenance
- [ ] Related context
- [ ] "Why did I save this?"
- [ ] "Show me everything related to X"

Embeddings can be added here.

Do not add them before basic structured retrieval works.

---

## Phase 6 — Selective Resurfacing

The companion should become proactive **carefully**.

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

---

## Phase 7 — Remote Reminders

Add a small hosted reminder scheduler.

- [ ] Minimal cloud reminder model
- [ ] Email channel
- [ ] Retry logic
- [ ] Delivery state
- [ ] Quiet hours
- [ ] Escalation logic
- [ ] Optional experimental self-iMessage

Later:

- [ ] iOS push

---

## Phase 8 — iPhone Capture

Before a full iOS app:

- [ ] Create "Save to Companion" Shortcut
- [ ] Share screenshot/link/photo
- [ ] Dictate/type reason
- [ ] Send into Companion Inbox
- [ ] Sync to Mac

Only build a native iOS client when the Shortcut becomes limiting.

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
- Full autonomous computer-use agent
- Calendar/email integrations immediately
- Social features
- SaaS billing
- YC pitch deck
- Startup branding exercise
- Multi-user authentication unless needed for remote sync

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
