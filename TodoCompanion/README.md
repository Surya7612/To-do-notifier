# TodoCompanion (native macOS)

The native Swift companion described in [`docs/TO_DO_NOTIFIER_UPDATED_PLAN.md`](../docs/TO_DO_NOTIFIER_UPDATED_PLAN.md).
It runs alongside the Electron app rather than replacing it — the Electron build
stays the working product while native capability is added in vertical slices.

This is **Phase 1**: one complete loop from a keystroke to an answer about what is
on screen.

## The loop

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
| `Hotkey/` | Carbon global hotkey wrapper |
| `Support/` | UserDefaults-backed settings |

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

Voice (Phase 2), the productivity/context layer (Phases 3–6), and remote
reminders (Phase 7). See the plan doc for the intended order.
