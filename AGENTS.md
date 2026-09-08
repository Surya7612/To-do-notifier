# To-Do Notifier — Agent Instructions

<!-- Single source of truth for AI coding agents working in this repo. -->
<!-- AGENTS.md spec: https://agents.md — read by Cursor, Claude Code, Copilot, and others. -->

## Overview

Two applications share this repository.

**`TodoCompanion/`** is the active work: a native macOS menu bar companion that answers questions about
what is currently on screen and remembers things you explicitly ask it to remember. The assistant is
called **Max**, which is a name and a tone in the prompt and the UI, *not* the bundle name. Summoning it with a
global hotkey captures every display, runs OCR, and asks a model. `⌘R` narrows the question to a region
you drag out. Saving with `⌘S` stores the screenshot alongside *your own stated reason* for keeping it,
so it can be resurfaced later when related material is on screen.

**Everything else** (`electron/`, `src/`, `*.html`) is the original Electron + Vite + React to-do and
reminder app. It still runs and is not deprecated, but new feature work is happening in the native app.
The companion reads its `app-data.json` read-only through `TodoBridge`, so open tasks, notes, and the
quiet-hours setting become context for answers. It never writes to it.

### Which app owns what

The dividing line is **not** Electron versus native. It is *study and motivation* versus *context and
memory*, and the two share exactly one thing: a task list.

The Electron app owns tasks, notes, due dates, flashcards, streaks, the pomodoro timer, the pet, and
notification preferences. It is where work is **created and completed**. The companion owns saved screen
context, projects, and retrieval. It is where context is **captured and connected**.

Full migration of the Electron app into the native one was considered and rejected. It is ~7,500 lines
of working code, of which ~1,300 is a pet built on copyrighted art that cannot be shipped and ~950 is a
voice stack using cloud TTS that this app's own rules forbid. Porting it would buy feature parity with
something that already works, and would give one app a split personality. Plan §9 says the same thing.

The consequence for anything that spans the two: **the companion stores the link, not the other app.**
`Project.linkedTodoIDs` holds the to-do app's identifiers on this side of the boundary, because the
grouping is this app's idea. A task deleted over there simply stops resolving. Completing a task stays in
the app that owns tasks, and the library says so rather than offering a checkbox that would not work.

That grouping is nonetheless **visible in both**, through a second file going the other way.
`ProjectExport` publishes the project list into the companion's own container; the Electron app reads it
through `electron/lib/companionProjects.cjs` and uses it to label and filter its task list. So each app
owns one file and reads the other's, and **neither ever writes the other's**. Making projects a field on
the to-do app's own tasks was the alternative and is the thing to avoid: it would put the companion in
the position of writing `app-data.json`, a file another process holds in memory and rewrites wholesale,
with no locking between them.

The governing design document is `docs/TO_DO_NOTIFIER_UPDATED_PLAN.md`. Read it before proposing
architecture; it records what was deliberately rejected and why.

## Core principle

The companion distinguishes what the **user** said from what the **model** inferred, everywhere, without
exception. `SavedContext.intent` holds the user's own words and is never overwritten by inference;
`SavedContext.aiSummary` holds the model's gloss and is always labelled as such in the UI. Retrieval
explains itself — every resurfaced item carries a human-readable reason like `same window` or `#tag`.
If a change would blur that line, it is the wrong change.

The second rule concerns what leaves the machine. **A cloud model may answer a question the user
explicitly asked. It may never do background work.** Summaries are generated unprompted across
everything the user keeps, so that body of material stays local — and a small local model compresses
OCR text into a sentence perfectly well, so there is no quality argument for exporting it either. This
is enforced structurally rather than by convention: `summarize` is not on the `Brain` protocol, it
exists only on `OllamaBrain`, so a cloud provider cannot be wired to it. Keep it that way.

## Architecture — native companion

- **App type**: menu bar only, no dock icon (`LSUIElement`)
- **UI**: SwiftUI, with AppKit bridging where SwiftUI cannot reach (`NSPanel`, overlay windows)
- **State**: `@Observable` view models, `@MainActor` isolation, async/await throughout
- **Hotkey**: Carbon `RegisterEventHotKey`. Chosen specifically because it needs **no Accessibility
  permission**, unlike a `CGEvent` tap
- **Capture**: ScreenCaptureKit, excluding this app's own windows so the panel never appears in its
  own screenshot
- **OCR**: Vision `VNRecognizeTextRequest`, on device
- **AI**: local Ollama by default; OpenAI as an opt-in for questions only. The key lives in the
  Keychain, never in `UserDefaults`. The panel always states which one will answer
- **Speech**: `AVAudioEngine` + `SFSpeechRecognizer` with `requiresOnDeviceRecognition` when supported
- **Persistence**: SwiftData, with screenshots in `.externalStorage`
- **Cross-app**: the Electron store is reached through a security-scoped bookmark from a user-chosen
  file, which is what keeps the sandbox intact

### Key architecture decisions

**Hotkeys are picked from a fixed safe list.** macOS silently swallows reserved combos — `⌘Space`,
`⌥⌘Space`, `⌃⌘Space` — *before* a Carbon handler sees them, and `RegisterEventHotKey` still returns
success. A hotkey that appears registered but never fires is almost always a reserved combo, not a bug
in the registration. `HotkeyChoice.all` is the vetted set; add to it only after testing.

**TCC permissions are tied to the code signature.** Under ad-hoc signing the grant keys on the binary
hash, so every rebuild invalidates Screen Recording and the app appears enabled in System Settings while
actually being denied. The project sets `DEVELOPMENT_TEAM` for a stable identity, which fixes this.
Consequence: unlike some macOS projects, **running `xcodebuild` from the terminal here is safe** and does
not cost you your permissions.

**The panel is a non-activating `NSPanel`.** It takes keystrokes without pulling the whole app forward,
rides across Spaces and full-screen apps, and hands focus back to the previous app on dismiss. It sizes
itself to its content and pins its *top-left* corner, because AppKit resizes about the bottom-left and a
streaming answer would otherwise walk the window up and off the cursor.

**Retrieval is structured first, and meaning is one signal inside it.** `ContextRetriever` scores on
topic hits, same-window, same-app, and token overlap. Embeddings were added later under a condition
rather than as a replacement: a vector distance may only *contribute* to a score it can also explain,
so it carries the reason `close in meaning` like every other signal, and it can only ever add. It is
weighted below "same window" deliberately — a shared window title is a fact, a resemblance is not —
and in library search a literal match is never ranked below a resemblance. With the feature off,
scoring is byte-for-byte what it was before. If a change would let an unexplained score reorder the
list, it is the wrong change.

The similarity floor is 0.55 because embedding models have a high similarity floor rather than a
zero one: measured with `nomic-embed-text`, plainly unrelated pairs score 0.31–0.40 and related pairs
0.62–0.69. Contribution scales from the floor, not from zero, or everything above the line would
arrive with the same near-maximum boost.

**Embedding is local, structurally.** `embed` is absent from the `Brain` protocol and exists only on
`OllamaBrain`, exactly as `summarize` is. Embedding is the *worst* thing to export, because it runs
once per save rather than once per question — the volume is the user's whole library, not one
deliberate ask. It embeds intent, topics, and the AI summary, but deliberately **not** the raw OCR
text, which would swamp a one-sentence reason and make every save from the same app look alike.

**Phone capture is a folder, not iCloud.** An iCloud container needs an entitlement requiring the
paid Apple Developer Program. A *folder* inside iCloud Drive needs none and syncs identically, so
`InboxImporter` takes a user-chosen folder through a security-scoped bookmark, the same pattern as
`TodoBridge`. The image travels base64-encoded inside a single JSON manifest rather than as a paired
file, because two files sharing a name arrive independently over a syncing folder and a reader cannot
distinguish "image not yet synced" from "image never coming". Importing removes what it imported —
the folder is a transport — but a manifest that *fails* to parse is left in place, since that is the
only signal the user gets that something went wrong. An item with no stated reason is refused rather
than imported with an inferred one.

**The current project is stated, not detected.** `AppSettings.currentProjectID` holds a project the user
picked, and it stays until they change it. Deriving it from the frontmost app or window was the obvious
alternative and was rejected: a wrong guess silently misfiles everything saved afterwards, and there is
no point at which the user would see that it had happened. Because the project is a stated fact rather
than something read off the pixels, it outscores every individual screen signal in retrieval (3.5) and
names itself in the reason — "in Engram". Deleting a project nullifies rather than cascades, so its
saves are unfiled instead of destroyed.

**Quiet hours are mirrored, not reinvented.** The user configured a do-not-disturb window once, in the
app that owns notification preferences. `QuietHours.contains` deliberately reproduces `inQuietHours` in
`electron/lib/dataMerge.cjs`, down to treating an equal start and end as *never* quiet rather than always
— two notification systems disagreeing about one setting is worse than one of them ignoring it, because
the disagreement is invisible. A reminder landing inside the window moves to the end of it, and the panel
shows the moved time rather than the requested one.

**A reminder is set by the user, never by the parser.** `ReminderPhrase` reads a saved reason and may
*offer* a time, but it only arms the reminder by default when the user actually used words like "remind
me". A date noticed in passing — "notes from tomorrow's standup" — is offered switched off. The chosen
time is always displayed, along with the words it came from, so the app's reading is visible rather than
applied silently. This is the core principle applied to scheduling: inference may suggest, not act.
Note that `NSDataDetector` takes no reference date and always resolves relative words against the system
clock, which is why the tests assert relative facts instead of fixed timestamps.

**Who answers is switchable from the panel, not only from Settings.** The badge in the panel header is a
menu, because the choice is per-question in practice: the local model reads text back fine and is worth
leaving for a diagram or an unfamiliar interface. It also carries the "Send the screenshot" toggle, which
is the setting that decides whether a visual question can be answered *at all* — OpenAI sees the screen
only if the screenshot goes with it, and otherwise receives OCR text and guesses at anything that is not
words. Both were previously only reachable through a settings window, which the click that opens it
dismisses.

**A choice that cannot be honoured is stated, not silently downgraded.** Selecting OpenAI with no key
in the Keychain falls back to the local model. Labelling that "Local" was a real bug rather than an
honest simplification: the user flipped a switch, nothing on screen moved, and the fallback was
indistinguishable from the control being broken. `AppSettings.AnswerDestination` therefore has three
cases, not two — `cloudWithoutKey` is its own state, reads "OpenAI — no key" in the problem colour,
and names what is answering instead. It is a pure function of the provider and whether a key exists,
so it is testable without a Keychain, and it is derived from the same two facts as `makeBrain()` so
the badge cannot name one model while another answers.

**File dialogs need the app to stop being an accessory for a moment.** An
`LSUIElement` app has no Dock presence and is never a normal foreground application, so macOS
declines to give it the focus a modal file dialog requires: `NSOpenPanel.runModal()` returns
`.cancel` without the panel ever appearing, logging nothing and throwing nothing. The button simply
looks dead. `FilePicker.choose` switches the activation policy to `.regular` for the duration and
restores it afterwards, which is why every open panel goes through it rather than constructing
`NSOpenPanel` directly. The cost is a Dock icon visible while the dialog is open — worse-looking than
this app otherwise is, and strictly better than a control that does nothing.

Consequence for the sandbox: user-selected files are entitled **read-write**, not read-only, because
`InboxImporter` deletes what it has imported. Read-only would have let the import succeed and the
delete fail silently, re-importing the same capture on every summon.

**A question is a conversation, not a lookup.** Every summon used to be one-shot, which made the panel
useless for the thing it is best at: standing next to an unfamiliar interface and being asked "now
what?" three times in a row. `CompanionViewModel.turns` holds the exchange and `Prompt.user` replays it,
so a two-word follow-up resolves against what was just said. Two consequences worth knowing. History is
capped at `Prompt.historyLimit` because the screen text already dominates the prompt and an unbounded
transcript would push it out of a small local model's window — answers would get *worse* the longer you
talked, which is the opposite of the point. And `lookAgain` re-captures while keeping the transcript,
because the screen changing is the normal case between turns rather than a reason to start over; the
prompt says so, so the model does not describe a screen that has moved on.

**Max is a name and a tone, never a licence.** The persona lives in `Prompt.system` and in UI copy. It
is emphatically *not* the bundle name: renaming the bundle would invalidate the Screen Recording grant,
which TCC keys to the signature and identifier, relocate the SwiftData container, and break
`electron/lib/companionProjects.cjs`, which hardcodes `surya.TodoCompanion`. The prompt states outright
that a persona does not permit inventing what is on screen or softening an "I don't know", because a
friendly voice is the classic way grounding rules get quietly loosened. `Prompt.summarySystem` exists
for the same reason in reverse: a background one-line gloss is a label in a list, not something said to
anyone, so it gets no persona at all — `summarize` was routed through `answerStream` and inherited the
teacher's instructions, which made for visibly worse summaries.

**Asking empties the field, so saving needs a stated fallback.** `Turn.savableReason` prefers the typed
field and otherwise uses the first question the user actually typed, since ⌘S straight after asking
would otherwise refuse with the field looking empty for no visible reason. Preset wording is
**ineligible**: "Explain what this is, in plain language" is this app's sentence, and storing it as the
user's reason for keeping something would break precisely the stated-versus-inferred distinction the
app exists to maintain. That is what `Turn.isFromPreset` is for; the model never sees it.

**Speech out is local, like speech in.** `AVSpeechSynthesizer` rather than a hosted voice. The ban on
cloud transcription applies in reverse — routing every answer through a speech vendor would export the
contents of the user's screen to a third party that is not even answering the question. It speaks a
sentence at a time so playback starts about a second in, rather than per word, which the synthesizer
renders as a stilted list because its prosody needs a full clause. It is off by default, stops on
`.immediate`, and stops when dictation starts: the synthesizer plays through the speakers and the mic
would transcribe it, so Max would otherwise dictate to itself. Markup is stripped before speaking, and
a fenced block is announced rather than read, since reading code aloud character by character is both
unbearable and too long to interrupt.

**Max may propose a file edit; only the user writes one.** This is deliberately *not* the autonomous
computer-use agent the plan rejects, and the argument is about product quality as much as safety: this
app sees a screenshot, has no file tree, and cannot run the tests, so a whole-project agent here would
be strictly worse than the editor the user already has open. What it can do that the editor cannot is
answer a question about the thing currently on screen. So `EditableFile` holds exactly one file, chosen
through a picker — there is no path to a file the user has not pointed at — and `apply` runs only from a
button press, after a diff. `Prompt.editingSystem` is appended only when a file is open, so a question
about the screen never arrives with instructions about rewriting files attached.

The model returns a **whole file**, not a patch, because models emit unified diffs with wrong line
numbers far more often than they mangle an entire file, and `TextDiff` computes the diff locally — a
diff derived from the two texts cannot be wrong about what changed, because it *is* what changed. For
the same reason `CodeBlock.extract` takes the **last** fenced block (explanations quote the broken lines
first) and refuses an unterminated fence outright, since a truncated file written over the user's own is
the worst outcome available here. An identical rewrite is discarded rather than offered, and `revert`
restores the file as it was before the conversation touched it rather than undoing one step of several.

**A conversation is kept because the screen was kept.** `ConversationTurn` is written only by ⌘S,
never automatically. Most summons are throwaway, and storing every one would fill the library with
material nobody chose to keep — the opposite of how the rest of the app works, where the user states
what matters. Ordering is an explicit `order` field because SwiftData to-many relationships come back
unordered, which would otherwise print a follow-up before the question it followed. The transcript
joins `searchHaystack`, since "I remember discussing this" is a real way to look for something, but is
deliberately kept out of `embeddingSource`: most of its length is the *model's* words, and embedding
those would let what Max said decide what gets resurfaced, when that field exists so the user's stated
reason drives retrieval.

**The graph is a view, not a database.** The plan rejects Neo4j, and the edges already exist in
SwiftData — a save belongs to a project, carries the user's `#tags`, and records the app it came from.
A graph store would add a server and a query language without adding one edge. What was missing was a
way to *see* them, so `ContextGraph` flattens the models into value types and `GraphLayout` runs a
deterministic Fruchterman–Reingold placement over them. Deterministic matters: reopening the window
gives the same picture, so spatial memory of your own material is worth building. A layout that
settles somewhere new each time looks impressive once and is useless twice. Rendered in a `Canvas`
rather than as views, because a few hundred `View` identities with their own animation machinery
stutter where an immediate-mode draw does not.

**Indicators are their own windows.** One-shot ScreenCaptureKit grabs get no system recording indicator,
so a capture would otherwise be completely invisible — the wrong property for a feature that reads your
screen. `CaptureIndicator` draws a ring at the cursor; it belongs to this app and is therefore excluded
from the screenshot along with the panel.

## Key files — `TodoCompanion/TodoCompanion/`

| File | Lines | Purpose |
|---|---|---|
| `TodoCompanionApp.swift` | ~90 | Entry point. `MenuBarExtra` scene, settings and library windows, accessory activation policy. |
| `App/AppDelegate.swift` | ~87 | Lifecycle. Registers the global hotkey, owns the panel controller, handles reminder taps, and republishes the project export on every store save. |
| `App/SettingsView.swift` | ~240 | Hotkey, provider choice, Ollama and OpenAI settings, and the to-do app link. |
| `Companion/CompanionPanelController.swift` | ~160 | Panel lifecycle, cursor-relative placement, wiring the view model to the capture indicator. Remembers the previously frontmost app so context is not attributed to us. |
| `Companion/CompanionPanel.swift` | ~43 | Borderless non-activating `NSPanel`. Pins top-left across content-driven resizes. |
| `Companion/CompanionView.swift` | ~605 | Panel UI: status header with the who-answers and open-file menus, ask field, dictation and save buttons, save options, related-context strip, conversation transcript, and the diff of a proposed edit. |
| `Companion/CompanionViewModel.swift` | ~872 | Orchestrates capture → OCR → retrieval → model → save. Owns phase state, the conversation transcript, dictation, speech playback, region selection, presets, the current project, reminders, and proposed file edits. |
| `Capture/ScreenCapture.swift` | ~218 | ScreenCaptureKit capture of every display, permission preflight, and region cropping. Excludes own windows. |
| `Capture/TextRecognizer.swift` | ~24 | Vision OCR. |
| `Capture/CaptureIndicator.swift` | ~196 | Cursor-tracking ring shown while capturing (blue) or listening (pink, driven by mic level). |
| `Capture/RegionSelector.swift` | ~137 | Drag-to-select overlay. Crops the screenshot already in memory rather than capturing again. |
| `Brain/Brain.swift` | ~254 | `Brain` protocol, `AskContext`, `Turn`, and the shared prompt text — including Max's persona, the conversation rules, and the file-editing rules. |
| `Brain/OllamaBrain.swift` | ~182 | Streaming Ollama client. Also the only place summaries and embeddings are generated. |
| `Brain/OpenAIBrain.swift` | ~95 | Streaming OpenAI client with vision. Opt-in; key from the Keychain. |
| `Voice/SpeechPlayback.swift` | ~116 | Reads answers aloud with `AVSpeechSynthesizer`, sentence by sentence, on device. |
| `Voice/SpeechDictation.swift` | ~218 | On-device push-to-talk dictation, plus a level meter that detects a silent input device. |
| `Store/SavedContext.swift` | ~223 | SwiftData models (`SavedContext`, `Project`, `ConversationTurn`) and hashtag parsing. |
| `Store/TextDiff.swift` | ~168 | Line diff and fenced-code-block extraction. Pure. |
| `Store/EditableFile.swift` | ~128 | The one user-picked file Max may propose changes to, with a confirmed write and a session revert. |
| `Store/ReminderPhrase.swift` | ~150 | Decides whether a saved reason is asking to be brought back, and when. Pure logic, no notification machinery. |
| `Support/Reminders.swift` | ~80 | Schedules and cancels the local notification behind a reminder. |
| `Store/ContextStore.swift` | ~25 | Shared `ModelContainer`, with an in-memory fallback rather than refusing to launch. |
| `Store/ContextGraph.swift` | ~241 | Builds the node/edge view of saves, projects, topics and apps, and lays it out. Pure. |
| `Store/ContextRetriever.swift` | ~181 | Explainable relevance scoring against the current screen, including the optional meaning signal. |
| `Store/Embedding.swift` | ~58 | Normalized vector, cosine similarity, and blob storage. Pure. |
| `Store/InboxImporter.swift` | ~197 | Brings in captures from a phone through a user-chosen folder. |
| `Store/TodoBridge.swift` | ~240 | Read-only bridge to the Electron app’s `app-data.json`: tasks, notes, and quiet hours, via a security-scoped bookmark. |
| `Store/ProjectExport.swift` | ~90 | Publishes the project list as JSON for the Electron app to read. Write-only half of the bridge. |
| `Support/AppSettings.swift` | ~190 | `UserDefaults` keys, defaults, the provider choice, and `AnswerDestination`. |
| `Support/DesignSystem.swift` | ~59 | Spacing, radius, alpha, and status colour tokens. |
| `Support/FilePicker.swift` | ~43 | Open panels that actually appear from a menu-bar-only app. |
| `Support/Keychain.swift` | ~60 | Generic-password storage for the one secret the app has. |
| `Support/ImageCodec.swift` | ~46 | PNG encoding and downscaling for storage and vision prompts. |
| `Hotkey/GlobalHotkey.swift` | ~89 | Carbon hot key registration. Exposes registration failure. |
| `Hotkey/HotkeyChoice.swift` | ~45 | The vetted list of non-reserved shortcuts. |
| `Library/GraphView.swift` | ~203 | `Canvas` rendering of the graph, with hover to trace a connection. |
| `Library/LibraryView.swift` | ~656 | Browse by project, search, reassign, rename, and delete saved contexts. Project overview pairs what was kept with the project's open tasks. |

## Build & run

```bash
# Native companion
cd TodoCompanion
xcodebuild -project TodoCompanion.xcodeproj -scheme TodoCompanion \
           -configuration Release -destination 'platform=macOS' build

# Electron app
npm install
npm run dev
```

Terminal builds are safe here — see the TCC note above. Ollama must be running (`ollama serve`) for the
companion to answer anything.

## Tests

```bash
cd TodoCompanion
xcodebuild test -project TodoCompanion.xcodeproj -scheme TodoCompanion -destination 'platform=macOS'
```

`TodoCompanionTests/` uses Swift Testing (`import Testing`, `@Test`, `#expect`). The whole suite runs in
well under a second because it covers only pure logic — no screen, no microphone, no Ollama, no network.

What is covered, and why these pieces specifically:

| Suite | Covers | Why it needs a test |
|-------|--------|---------------------|
| `ScreenObservationTests` | Region crop coordinate math | Converts AppKit's bottom-left origin to CoreGraphics' top-left with a pixel scale factor. A flipped crop still returns a correctly sized image of the wrong thing, so the fixtures assert on **pixels**, not geometry. |
| `ContextRetrieverTests` | Relevance scoring and stated reasons | Decides what the app volunteers unprompted. Weights are unassertable by eye, and the failure modes are silent. |
| `TodoBridgeTests` | Parsing the Electron app's `app-data.json` | Another app owns that file and can change or truncate it. Also pins that the OpenAI key in the same file never reaches prompt data. |
| `QuietHoursTests` | The do-not-disturb window, and project↔task links | Must match the Electron implementation exactly; a silent disagreement between two notification systems is the failure mode. Also covers a task deleted in the other app leaving a dangling link. |
| `PromptTests` | Prompt construction | Where the "user intent outranks inference" rule actually lives. Regressions here surface as subtly worse answers, not errors. |
| `ConversationPromptTests` | Replaying earlier turns | The easy mistakes are handing the model the current question twice and letting the transcript grow until the screen text falls out of the context window, both of which degrade answers silently. |
| `PersonaPromptTests` | Max's tone, and the editing instructions | Pins that the persona sits *on top of* the grounding rules rather than replacing them, that editing instructions never reach a question with no file open, and that summaries stay persona-free. |
| `SavableReasonTests` | What a save is filed under | Decides which words get stored as the user's own. Pins that preset wording never can be, which is the app's central promise in the one place a convenience could quietly break it. |
| `TextDiffTests` | Line diff and hunk grouping | This is the safety mechanism for file edits, not a presentation detail — a diff that under-reported a change would get one applied that nobody agreed to. |
| `CodeBlockTests` | Pulling the file out of a reply | A model's reply is prose with a file inside it. Extracting wrongly means writing prose, or half a file, over the user's code, so an unterminated fence must yield nothing. |
| `ContextGraphTests` | Nodes and edges built from saves | A wrong edge is a wrong claim about how the user's material relates, and it is drawn large enough to be believed. Pins that shared tags collapse to one node and that filtering a kind removes its edges too. |
| `GraphLayoutTests` | Force-directed placement | No assertable "correct" coordinates, so it pins the properties that make it usable: everything placed, nothing off-canvas, connected nodes closer than unconnected, and the same picture every time. |
| `SavedContextTests` | `#tag` splitting, search haystack, hotkey choices | Runs on every save; mistakes are persisted. |
| `ReminderPhraseTests` | What counts as asking for a reminder, and at what time | Guards the line between a request and a mention. Also pins that a bare day becomes morning, since midnight would fire while the user is asleep. |
| `AnswerDestinationTests` | What the who-answers badge says, per provider and key state | Pins that the three states stay distinguishable, since collapsing "cloud selected, no key" into "local" is what made a provider switch look broken. Also pins the badge against `Brain.leavesTheMachine`, which is computed separately in another file. |
| `EmbeddingTests` | Vector normalization, cosine similarity, blob round trip | The only exactly checkable part of meaning matching. Pins that a degenerate or wrong-length vector compares as *nil* rather than as zero, since zero would still attach a "close in meaning" reason to something that is not. |
| `SemanticRetrievalTests` | How meaning feeds into scoring | Enforces the condition on using embeddings at all: additive, explained, and outranked by stated facts. Uses hand-built vectors, so it tests the integration rather than anyone's model quality. |
| `InboxImporterTests` | Parsing the phone's JSON manifest | Written by a Shortcut, over a syncing folder, with nothing here compiling against it. A bad import is persisted and then resurfaces, so every malformed shape must yield "not an item". Also pins that an image with no reason is refused. |
| `ProjectExportTests` | The published JSON's keys and date format | Half of a contract with a reader in another language that nothing here compiles against. A renamed key would still build and would just make project names quietly vanish from the to-do app, so these assert on the **encoded JSON**, not on the Swift types. |

The Electron side has its own suite, run with `npm test` (vitest), and
`electron/lib/companionProjects.test.ts` is the other half of that same contract: it pins that every
shape of bad or absent input lands on "no projects" rather than breaking the task list.

Two conventions worth keeping:

- Assert on **behaviour** — ordering, inclusion, the reason string — rather than exact scores, so weights
  stay tunable without rewriting tests.
- When a test pins a known rough edge rather than a desired property, say so in a comment. See
  `sameAppAloneClearsTheThreshold`, which exists so that changing that behaviour is a visible decision.

Anything requiring `NSScreen`, a real capture, or a running model is deliberately **not** tested; that is
why `cropped(to:inDisplayFrame:)` exists alongside the `NSScreen` convenience overload.

## Conventions

### Comments

Comment the **why**, never the what. A comment earns its place by recording something the code cannot
show: a platform constraint, a rejected alternative, a non-obvious ordering requirement. Do not write
comments that restate the next line, narrate a change, or explain to a reviewer why a diff is correct —
those become noise the moment the change merges.

### Naming

Prefer clarity to brevity. Names should be understandable to someone with no context on the codebase.
Keep argument names the same as the variables they came from rather than abbreviating at the boundary.

### Swift

- SwiftUI unless the feature genuinely requires AppKit
- All UI state on `@MainActor`; async/await for anything asynchronous
- C callbacks and statics touched from them must be `nonisolated`
- This project builds with `MemberImportVisibility`, so import every module you use directly —
  notably `import SwiftData` in any file touching `mainContext` or `modelContainer`
- Adding an early `return` to a `switch` expression means every branch now needs an explicit `return`

### Git

- Commit messages are prose explaining *why*, in the imperative mood. No bullet lists, no `feat:`
  prefixes, no emoji
- **Never** add `Co-authored-by` trailers or any attribution to an AI tool. History must show only
  the repository owner. Cursor's git wrapper re-injects this trailer, so commits are made with
  `git commit-tree` plumbing to bypass it, then verified with
  `git log --format='%B' | rg -i 'co-authored-by'`
- Do not force-push shared branches

### Do not

- Do not add cloud **transcription** or **speech synthesis**, or analytics. Voice and usage data stay
 on the machine
- Do not add a wake word or any always-listening mode. The mic opens when the user opens it. Note the
 Electron app's own wake word (`ilEnabled`) ships **off by default**, which is the evidence, not the
 counter-example
- Do not let inference write to disk. Max proposes a file change, the user is shown a diff, and only a
 button press writes anything. Do not extend editing past one explicitly-picked file
- Do not route background or automatic work to a cloud model. Foreground questions only, and only
  when the user has opted in. This rule replaced a blanket ban on hosted models once local vision
  proved too weak to explain what is on screen; the ban on *unprompted* export did not change
- Do not require Accessibility permission
- Do not add continuous or background screen capture. Capture is always explicit and user-initiated
- Do not make resurfacing proactive. Related material appears on summon and never otherwise; plan §
 Phase 6 is **closed at that form**, not pending. Without Accessibility the only free trigger is an
 app switch, which says nothing about need, and acting on it means either matching a window title
 (usually wrong) or capturing unasked (contradicts the rule above)
- Do not present model inference as though the user wrote it
- Do not add features beyond what was asked

## Distribution

`scripts/release-companion.sh` builds a DMG and publishes a GitHub Release. It stops short of Developer
ID signing, notarization, and Sparkle auto-updates, all of which need the paid Apple Developer Program.
Until that exists, downloaders must right-click → Open once to get past Gatekeeper, and the script says
so in the release notes it generates.

## Self-update

Keep this file accurate when you change the things it describes:

1. Add new source files to the key-files table with purpose and approximate line count
2. Remove entries for deleted files
3. Update the architecture section when introducing a new pattern, framework, or permission
4. Update build commands when the build changes
5. Record new conventions the owner establishes during a session
6. Refresh line counts that have drifted by more than ~50 lines

Do not update it for minor edits or bug fixes that leave the documented architecture unchanged.
