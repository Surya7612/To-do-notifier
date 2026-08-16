# To-Do Notifier

Private **macOS** menu-bar companion: floating Goku pet, deadline reminders, Pomodoro, notes, flashcards, and local **Ollama** tutoring.

Built with Electron + Vite + React. Data stays on your Mac (`~/Library/Application Support/todo-notifier/`).

## Features

- Todos with lead-time and overdue reminder nags (tray + notifications)
- Always-on Goku pet (corner / patrol / body-double modes)
- Voice companion: **“Hey Goku”** → commands + short chat (OpenAI Whisper + Ollama)
- Tutor dictation → notes / quiz / flashcards
- Pomodoro focus timer with optional ambient sound
- Settings → **Readiness** check (mic, OpenAI, ElevenLabs, Ollama, notifications)

## Requirements

- macOS (Apple Silicon builds are the primary target)
- Node.js 18+
- [Ollama](https://ollama.com) + a model, e.g. `ollama pull llama3.2`
- OpenAI API key (for listening / Whisper)
- Optional: ElevenLabs API key + a **My Voices** voice ID (library voices need a paid ElevenLabs plan)

## Install (normal Mac app)

```bash
npm install
npm run install:app
```

That packs `To-Do Notifier.app`, ad-hoc signs it, copies it to `/Applications`, and opens it.

Or build a DMG:

```bash
npm run dist
# then open release/*.dmg and drag the app into Applications
```

### First launch

1. Allow **Microphone** and **Notifications** when prompted (or System Settings → Privacy).
2. Open **Settings → Voice** and paste your **OpenAI** key.
3. For Goku speech without ElevenLabs: enable **Allow system voice if ElevenLabs fails** (or skip ElevenLabs entirely).
4. Click **Run full check** and fix any red items.
5. Click **Arm voice**, then say **“Hey Goku”**.

## Voice modes

| Mode | How to enter | What it does |
|------|----------------|--------------|
| Companion | “Hey Goku” | Commands + short chat using open todos & notes. Mic pauses while Goku speaks. |
| Dictation | Tutor tab → **Dictate**, or say “dictate” / “tutor mode” | Speech → transcript only. Say “stop”. |

## Soft-block

“Pause upcoming reminders during focus” only suppresses **reminder nags**. It does **not** block other apps or websites.

## Development

```bash
npm install
env -u ELECTRON_RUN_AS_NODE npm run dev
```

Quality gates:

```bash
npm run check   # typecheck + lint + tests + build
```

Useful scripts:

| Script | Purpose |
|--------|---------|
| `npm run dev` | Vite + Electron hot reload |
| `npm test` | Unit tests (Vitest) |
| `npm run lint` | ESLint on `src/` |
| `npm run typecheck` | TypeScript |
| `npm run pack` | Unpackaged `.app` under `release/` |
| `npm run dist` | DMG + zip |
| `npm run install:app` | Pack, install to `/Applications`, open |

## Privacy notes

- Todos / notes / settings are local JSON only.
- With voice on, mic audio is sent to **OpenAI Whisper**.
- If ElevenLabs is configured, spoken replies are synthesized via their API.
- Never commit API keys. Keys live in Settings (stored in local `app-data.json`).

## License

MIT — see [LICENSE](LICENSE).
