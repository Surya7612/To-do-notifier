# TodoCompanion (native macOS)

The native Swift companion described in [`docs/TO_DO_NOTIFIER_UPDATED_PLAN.md`](../docs/TO_DO_NOTIFIER_UPDATED_PLAN.md).
It runs alongside the Electron app rather than replacing it — the Electron build
stays the working product while native capability is added in vertical slices.

Two things work today: asking about the current screen (Phase 1) and keeping a
screen along with the reason it mattered (Phase 4).

## Asking

```text
⌥⌘Space
   ↓
Companion panel appears beside the cursor
   ↓
ScreenCaptureKit grabs the display under the cursor (this app excluded)
   ↓
Vision OCRs it on-device
   ↓
Question + screen text stream to a local Ollama model
   ↓
Answer renders token-by-token in the panel
```

## Remembering

Same panel, but instead of Return you press **⌘S**. What you typed is stored as
your *reason* for keeping the screen, alongside the screenshot, the OCR text, and
the app and window it came from. Any `#tags` in your sentence become topics.

```text
⌥⌘Space → "check this when I redo retrieval #engram" → ⌘S
```

Later, **Saved Context** in the menu bar searches across your reasons, the model's
summaries, topics, app names, and the text that was on screen.

Your own words and the model's interpretation are stored as separate fields and
always labelled differently in the UI. The model never gets to author your intent.

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

The app has no Dock icon. Look for the speech-bubble icon in the menu bar.

On first use macOS asks for **Screen Recording** permission. Grant it in System
Settings → Privacy & Security → Screen Recording, then relaunch. The global
hotkey deliberately uses Carbon's `RegisterEventHotKey`, so no Accessibility
permission is needed.

## Layout

| Path | Role |
|------|------|
| `App/` | `NSApplicationDelegate`, activation policy, hotkey wiring, Settings UI |
| `Companion/` | The `NSPanel`, its placement logic, view model, and SwiftUI bubble |
| `Capture/` | ScreenCaptureKit screenshot and Vision OCR |
| `Brain/` | Streaming Ollama client |
| `Store/` | SwiftData models for saved context and projects |
| `Library/` | Browse and search what you've kept |
| `Hotkey/` | Carbon global hotkey wrapper |
| `Support/` | Settings and image encoding |

New `.swift` files anywhere under `TodoCompanion/` are added to the target
automatically — the project uses a file-system synchronized group, so
`project.pbxproj` does not need editing.

## Privacy posture

By default the screenshot never leaves the machine: Vision extracts text
on-device and only that text is sent to Ollama on `127.0.0.1`. Settings has a
toggle to send the image itself, which is only useful once a vision-capable model
(`llava`, `qwen2.5vl`) is pulled. The App Sandbox is enabled with outgoing
network access as the only added entitlement.

## Not built yet

Voice (Phase 2), reading the existing Electron todo data (Phase 3), semantic
retrieval (Phase 5), proactive resurfacing (Phase 6), and remote reminders
(Phase 7). See the plan doc for the intended order.

Search is currently literal, not semantic — "screen capture" will not find a note
that says "display grabbing." Embeddings are deferred until the structured
version proves insufficient in real use.
