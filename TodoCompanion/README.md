# TodoCompanion (native macOS)

A menu bar companion that answers questions about what is on your screen right now, and remembers
things you explicitly ask it to remember — along with *your own stated reason* for keeping them.

It runs alongside the Electron app in this repository rather than replacing it. See
[`docs/TO_DO_NOTIFIER_UPDATED_PLAN.md`](../docs/TO_DO_NOTIFIER_UPDATED_PLAN.md) for the design
document, including what was deliberately rejected and why.

## Asking

```text
⌃⌥Space
   ↓
Companion panel appears beside the cursor · a ring marks the capture
   ↓
ScreenCaptureKit grabs every attached display (this app's own windows excluded)
   ↓
Vision OCRs them on-device
   ↓
Related things you saved before are scored against the screen
   ↓
Question + screen + those memories + your open tasks go to the model
   ↓
Answer streams into the panel
```

Press **⌘R** to drag out one region and ask about that instead. It crops the screenshot already in
memory rather than capturing again. **Explain** and **Next step** are the two questions worth a
button.

**⌘D** dictates instead of typing, on-device, with a ring at the cursor driven by your actual input
level — so a microphone that is producing silence looks like silence rather than like a hang.

### Who answers

The badge in the panel header names the model that will answer, and is a menu you can change it
from. Two choices:

| | |
|---|---|
| **On this Mac** | Ollama, on `127.0.0.1`. The default. Nothing leaves the device. |
| **OpenAI** | Opt-in, for questions only. The key lives in the login Keychain, never in preferences. |

The choice is per-question in practice: the local model reads text back perfectly well, and is worth
leaving for a diagram or an interface it has never seen.

The same menu carries **Send the screenshot**, which decides whether a visual question can be
answered at all — without it OpenAI receives only the recognized text and guesses at anything that is
not words. Locally it needs a vision model (`llava`, `qwen2.5vl`) to be worth turning on.

Selecting OpenAI without saving a key falls back to the local model, and the badge says so rather
than quietly reading "Local".

## Remembering

Same panel, but instead of Return you press **⌘S**. What you typed is stored as your *reason* for
keeping the screen, alongside the screenshot, the OCR text, and the app and window it came from. Any
`#tags` in your sentence become topics.

```text
⌃⌥Space → "check this when I redo retrieval #engram" → ⌘S
```

Your own words and the model's interpretation are stored as separate fields and always labelled
differently in the UI. The model never gets to author your intent.

### Reminders

If your reason says something like "remind me tomorrow at 4", the panel offers a reminder and shows
the time it read, next to the words it read it from. It only arms itself by default when you actually
asked to be reminded — a date merely mentioned, as in "notes from tomorrow's standup", is offered
switched off. Tapping the notification opens the library at the thing it is about.

Reminders respect the quiet hours you configured in the To-Do Notifier, and a reminder landing inside
that window shows the moved time rather than the one you asked for.

### Projects

A project is a named thing you are working on. You pick the current one in the panel before saving,
and it stays picked until you change it — it is never guessed from the frontmost app, because a wrong
guess would silently misfile everything saved afterwards with nothing to reveal it.

A project can also hold tasks from the To-Do Notifier, which makes **Saved Context → project
overview** show what you kept next to what you still have to do. Those same projects appear back in
the To-Do Notifier as labels and a filter on its task list.

## Resurfacing

You don't have to go looking. Each time you summon the companion, it scores what you've kept against
the screen in front of you and shows the top few under "You kept this before" — each with the reason
it surfaced, such as "same window", "#engram", "in Engram", or "mentions retrieval". Those matches
are also handed to the model, labelled as your words.

Scoring is structured rather than semantic, deliberately: embeddings cannot tell you *why* something
came back, and unexplained resurfacing is indistinguishable from the app guessing.

This happens **only when you summon it**. Nothing polls in the background and no capture occurs that
you didn't ask for.

## Requirements

- macOS 26.5 or later (the project's deployment target)
- Xcode 26
- [Ollama](https://ollama.com) running locally with at least one model:
  ```sh
  ollama serve
  ollama pull llama3.2
  ```

## Running it

Open `TodoCompanion.xcodeproj` and press ⌘R, or build from the command line:

```sh
xcodebuild -project TodoCompanion.xcodeproj -scheme TodoCompanion \
  -configuration Debug -destination 'platform=macOS' build
```

Tests:

```sh
xcodebuild test -project TodoCompanion.xcodeproj -scheme TodoCompanion -destination 'platform=macOS'
```

The suite covers pure logic only — no screen, microphone, model, or network — and runs in a fraction
of a second.

The app has no Dock icon. Look for the icon in the menu bar.

On first use macOS asks for **Screen Recording** permission. Grant it in System Settings → Privacy &
Security → Screen Recording, then relaunch. The global hotkey deliberately uses Carbon's
`RegisterEventHotKey`, so no Accessibility permission is needed. Dictation additionally asks for
Microphone and Speech Recognition.

The project sets `DEVELOPMENT_TEAM` so the signature is stable across rebuilds. This matters more than
it sounds: TCC keys its permission grants to the code signature, so under ad-hoc signing every rebuild
silently invalidates Screen Recording while the app continues to *look* enabled in System Settings.

The shortcut defaults to `⌃⌥Space` and can be changed in Settings. The options are restricted to
combos macOS does not reserve: a reserved combo such as `⌘Space` or `⌥⌘Space` is consumed by the
system before the app sees it, and `RegisterEventHotKey` *still returns success*, so the shortcut
silently does nothing rather than reporting an error.

Run only one copy at a time. Carbon hot keys are exclusive, so a second instance fails to claim the
shortcut and the first one to launch keeps it.

## Connecting it to the To-Do Notifier

In Settings, point **Your to-do app** at the Electron app's `app-data.json`, normally at
`~/Library/Application Support/todo-notifier/app-data.json`. That file picker is what grants a
sandboxed app access, so it cannot be done silently.

The companion then reads your open tasks, notes, and quiet-hours setting — and only ever reads them.
Traffic in the other direction is a separate file it writes with its project list, which the Electron
app reads. Each app owns one file and reads the other's; neither writes the other's.

## Layout

| Path | Role |
|------|------|
| `App/` | `NSApplicationDelegate`, activation policy, hotkey wiring, Settings UI |
| `Companion/` | The `NSPanel`, its placement logic, view model, and SwiftUI panel |
| `Capture/` | ScreenCaptureKit capture, Vision OCR, region selector, cursor indicator |
| `Brain/` | The `Brain` protocol, shared prompt text, Ollama and OpenAI clients |
| `Voice/` | On-device dictation and input level metering |
| `Store/` | SwiftData models, retrieval scoring, reminder parsing, both halves of the to-do bridge |
| `Library/` | Browse, search, and manage what you've kept |
| `Hotkey/` | Carbon global hotkey wrapper and the vetted shortcut list |
| `Support/` | Settings, design tokens, Keychain, notifications, image encoding |

New `.swift` files anywhere under `TodoCompanion/` are added to the target automatically — the project
uses a file-system synchronized group, so `project.pbxproj` does not need editing.

## Privacy posture

Captures are always explicit and user-initiated. There is no background or continuous capture, and a
capture is never invisible: one-shot ScreenCaptureKit grabs get no system recording indicator, so the
app draws its own ring at the cursor.

By default nothing leaves the machine. Vision extracts text on-device and only that text goes to
Ollama on `127.0.0.1`. Dictation is on-device where the system supports it.

Choosing OpenAI sends the question, and the screenshot if you enabled that, for **that question
only**. Background work is never routed to a cloud model, and this is enforced structurally rather
than by convention: `summarize` is absent from the `Brain` protocol and exists only on `OllamaBrain`,
so no cloud provider can be attached to it. That is why summaries of everything you keep stay local
even when OpenAI is answering your questions.

The App Sandbox is enabled, with outgoing network and microphone access as the only added
entitlements.

## Not built yet

- **Semantic search.** Retrieval and library search are literal — "screen capture" will not find a
  note that says "display grabbing". Embeddings are deferred until the structured version
  demonstrably fails, since it can explain itself and they cannot.
- **Remote reminders.** Reminders are local, so they need this Mac awake when they fire. A hosted
  scheduler is the one thing that would fix that, and the only reason to build one.
- **Voice responses.** Dictation is in; spoken answers are not, and are no longer obviously wanted.
- **iPhone capture.** Intended to start as a Shortcut rather than an app.
- **Signing and notarization.** `scripts/release-companion.sh` builds a DMG and publishes a release,
  but stops short of Developer ID signing, notarization, and auto-updates, all of which need the paid
  Apple Developer Program. Until then, downloaders must right-click → Open once.
