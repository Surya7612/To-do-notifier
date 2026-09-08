# Architecture

Companion notes for the high-level diagram in the [README](../README.md). Aimed at portfolio / code review — not a full design doc.

## Processes & windows

| Surface | Role |
| --- | --- |
| **Main window** | React app: Todos, Focus, Notes, Tutor, Review, Training, Settings |
| **Pet window** | Transparent, always-on-top companion (`type: "panel"` on macOS); sprite + speak chrome |
| **Panel window** | Small hover UI near the pet |
| **Tray** | Menu bar status, Talk / open / quit, focus timer label |

Main process owns lifecycle, reminders, IPC, and native integrations. Renderers talk only through a context-isolated preload (`electron/preload.cjs`).

## Main-process modules

```
electron/
  main.cjs              boot, single-instance lock, shared ctx
  windowFactory.cjs     BrowserWindows, broadcast, notifications
  petRuntime.cjs        placement, drag, flight modes, speak sizing
  trayRuntime.cjs       tray icon + menu
  registerIpc.cjs       all ipcMain handlers
  preload.cjs           renderer API surface
  lib/
    dataStore.cjs         load/save app-data.json
    dataMerge.cjs         merge + validation helpers
    defaults.cjs          default settings
    remindersService.cjs  due / overdue sweep
    ollamaService.cjs     local LLM HTTP
    sttService.cjs        OpenAI transcription
    ttsService.cjs        ElevenLabs + system voice fallback
    companionChat.cjs     chat prompt / empty-todo replies
    companionProjects.cjs reads the companion's published projects and reminder requests
    companionTasks.cjs    turns those requests into tasks this app owns
    voiceHotkeys.cjs      ⌘G / Esc global shortcuts
    safeWindow.cjs        isDestroyed-safe send / bounds
    safeExternal.cjs      external-URL allowlist
    audioWav.cjs          PCM16 → WAV
    random.cjs            line picking for the pet's copy
```

Shared mutable state lives on a single `ctx` object (windows, pet motion flags, timers). Pet motion and IPC are guarded so destroyed windows do not crash the process.

## Renderer

```
src/
  App.tsx                 tab shell
  components/             Todos, Pomodoro, Notes, Tutor, Review, …
  lib/voiceController.ts  mic, STT session, dictate vs conversation
  PetApp.tsx / PanelApp.tsx
```

Voice UX is driven from the renderer (`voiceController`) and reports status to main for the tray. Tutor Rubber Duck uses the same dictate path with Socratic / tip prompts via Ollama.

## Data

- Path: `~/Library/Application Support/todo-notifier/app-data.json`
- Contents: todos, notes, flashcards, training stats, settings (including API keys)
- Changes broadcast on `data:changed` so all windows stay in sync
- This process is the only writer. The companion publishes its own file instead and this app imports
  from it, because two processes rewriting one file whole, with no locking between them, eventually
  loses an edit

## Cross-app boundary

The native companion is read-only on the file above and publishes `companion-projects.json` in its own
container. This app reads that for project labels and for reminders the companion is asking to have
turned into tasks; `companionTasks.cjs` creates them, keyed on a stable id so a repeated import adds
nothing. The import runs at startup and on the same 30-second tick as the reminder sweep, so it does
not depend on a window being open.

## External boundaries

| Dependency | When used |
| --- | --- |
| **Ollama** | Tutor questions/notes, companion chat replies |
| **OpenAI** | Speech-to-text while conversation / dictate is active |
| **ElevenLabs** | Optional TTS; otherwise system voice or silent |

No cloud account for core todos/notes — those remain local.

## Quality gates

`npm run check` → TypeScript + ESLint + Vitest + production Vite build. CI runs the same pipeline on GitHub Actions.
