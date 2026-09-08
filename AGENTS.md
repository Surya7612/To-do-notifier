# To-Do Notifier — Agent Instructions

<!-- Single source of truth for AI coding agents working in this repo. -->
<!-- AGENTS.md spec: https://agents.md — read by Cursor, Claude Code, Copilot, and others. -->

## Overview

Two applications share this repository.

**`TodoCompanion/`** is the active work: a native macOS menu bar companion that answers questions about
what is currently on screen and remembers things you explicitly ask it to remember. Summoning it with a
global hotkey captures every display, runs OCR, and asks a model. `⌘R` narrows the question to a region
you drag out. Saving with `⌘S` stores the screenshot alongside *your own stated reason* for keeping it,
so it can be resurfaced later when related material is on screen.

**Everything else** (`electron/`, `src/`, `*.html`) is the original Electron + Vite + React to-do and
reminder app. It still runs and is not deprecated, but new feature work is happening in the native app.
The companion reads its `app-data.json` read-only through `TodoBridge`, so open tasks and notes become
context for answers. It never writes to it.

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

**Retrieval is structured, not semantic.** `ContextRetriever` scores on topic hits, same-window,
same-app, and token overlap rather than embeddings. This is a deliberate trade: embeddings cannot tell
the user *why* something resurfaced, and unexplained resurfacing is indistinguishable from the app
guessing. Revisit only when the structured version demonstrably fails.

**Indicators are their own windows.** One-shot ScreenCaptureKit grabs get no system recording indicator,
so a capture would otherwise be completely invisible — the wrong property for a feature that reads your
screen. `CaptureIndicator` draws a ring at the cursor; it belongs to this app and is therefore excluded
from the screenshot along with the panel.

## Key files — `TodoCompanion/TodoCompanion/`

| File | Lines | Purpose |
|---|---|---|
| `TodoCompanionApp.swift` | ~62 | Entry point. `MenuBarExtra` scene, settings and library windows, accessory activation policy. |
| `App/AppDelegate.swift` | ~21 | Lifecycle. Registers the global hotkey and owns the panel controller. |
| `App/SettingsView.swift` | ~131 | Hotkey, provider choice, Ollama and OpenAI settings, and the to-do app link. |
| `Companion/CompanionPanelController.swift` | ~147 | Panel lifecycle, cursor-relative placement, wiring the view model to the capture indicator. Remembers the previously frontmost app so context is not attributed to us. |
| `Companion/CompanionPanel.swift` | ~43 | Borderless non-activating `NSPanel`. Pins top-left across content-driven resizes. |
| `Companion/CompanionView.swift` | ~244 | Panel UI: status header, ask field, dictation and save buttons, related-context strip, answer area. |
| `Companion/CompanionViewModel.swift` | ~389 | Orchestrates capture → OCR → retrieval → model → save. Owns phase state, dictation, region selection, and presets. |
| `Capture/ScreenCapture.swift` | ~218 | ScreenCaptureKit capture of every display, permission preflight, and region cropping. Excludes own windows. |
| `Capture/TextRecognizer.swift` | ~24 | Vision OCR. |
| `Capture/CaptureIndicator.swift` | ~196 | Cursor-tracking ring shown while capturing (blue) or listening (pink, driven by mic level). |
| `Capture/RegionSelector.swift` | ~137 | Drag-to-select overlay. Crops the screenshot already in memory rather than capturing again. |
| `Brain/Brain.swift` | ~112 | `Brain` protocol, `AskContext`, and the shared prompt text. |
| `Brain/OllamaBrain.swift` | ~84 | Streaming Ollama client. Also the only place summaries are generated. |
| `Brain/OpenAIBrain.swift` | ~95 | Streaming OpenAI client with vision. Opt-in; key from the Keychain. |
| `Voice/SpeechDictation.swift` | ~218 | On-device push-to-talk dictation, plus a level meter that detects a silent input device. |
| `Store/SavedContext.swift` | ~96 | SwiftData models (`SavedContext`, `Project`) and hashtag parsing. |
| `Store/ContextStore.swift` | ~25 | Shared `ModelContainer`, with an in-memory fallback rather than refusing to launch. |
| `Store/ContextRetriever.swift` | ~102 | Explainable relevance scoring against the current screen. |
| `Store/TodoBridge.swift` | ~153 | Read-only bridge to the Electron app's `app-data.json` via a security-scoped bookmark. |
| `Support/AppSettings.swift` | ~76 | `UserDefaults` keys, defaults, and the provider choice. |
| `Support/DesignSystem.swift` | ~49 | Spacing, radius, alpha, and status colour tokens. |
| `Support/Keychain.swift` | ~60 | Generic-password storage for the one secret the app has. |
| `Support/ImageCodec.swift` | ~46 | PNG encoding and downscaling for storage and vision prompts. |
| `Hotkey/GlobalHotkey.swift` | ~89 | Carbon hot key registration. Exposes registration failure. |
| `Hotkey/HotkeyChoice.swift` | ~45 | The vetted list of non-reserved shortcuts. |
| `Library/LibraryView.swift` | ~201 | Browse, search, and delete saved contexts. |

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
| `PromptTests` | Prompt construction | Where the "user intent outranks inference" rule actually lives. Regressions here surface as subtly worse answers, not errors. |
| `SavedContextTests` | `#tag` splitting, search haystack, hotkey choices | Runs on every save; mistakes are persisted. |

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

- Do not add cloud **transcription** or analytics. Voice and usage data stay on the machine
- Do not route background or automatic work to a cloud model. Foreground questions only, and only
  when the user has opted in. This rule replaced a blanket ban on hosted models once local vision
  proved too weak to explain what is on screen; the ban on *unprompted* export did not change
- Do not require Accessibility permission
- Do not add continuous or background screen capture. Capture is always explicit and user-initiated
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
