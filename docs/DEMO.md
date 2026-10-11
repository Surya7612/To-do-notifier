# Demo rehearsal (Max + To-Do Notifier)

Ten-minute live run for interviews. Do a cold rehearsal the day before with
the Mac freshly logged in so TCC prompts do not surprise you on stage.

## Preflight (5 minutes before)

| Check | How |
| --- | --- |
| Ollama | `ollama serve` in a terminal; `ollama list` shows a chat model (e.g. `llama3.2` or `qwen2.5`) |
| Screen Recording | System Settings → Privacy → Screen Recording → **TodoCompanion** on |
| Notifications | Allow for TodoCompanion when prompted |
| Reminders + Calendars | Needed only for the phone mirror beat |
| iCloud Reminders | System Settings → Apple Account → iCloud → Reminders **on** (or Settings copy stays orange “this Mac only”) |
| To-do link | Max → Settings → choose the Electron app’s `app-data.json` **before** flipping the mirror toggle |
| Summon hotkey | Menu bar Max → label shows the combo (default `⌃⌥Space`) |
| Talk hotkey | Settings → Talk: `⌥⌘Q` ×2 (or Tab+Q if Accessibility extras are on) |
| Cloud fallback | Optional: OpenAI/Claude/Gemini key in Keychain + “Send the screenshot” if you will show a diagram |

If the panel status line says Screen Recording or Ollama is down, fix that
*before* talking — that line is the cold-start contract ([USABILITY.md](USABILITY.md) §4).

## Demo spine (~8 minutes)

1. **Summon** with the hotkey. Point at the status line: it should name a
   blocker or invite capture with the hotkey — never sit silently empty.
2. **Explain** a real screen (Xcode, a tutorial page, a terminal error). Show
   quoted control names and the amber “Show me” box.
3. **Teach me** on the same screen. Progress strip, step boxes, optional
   **Guide cursor** if Accessibility extras are on. Board appears only if Max
   emits a `board` fence for an invented diagram.
4. **Remind me in two hours to …** — panel arms the reminder; Electron gets a
   `companion:` task after import; with mirror on + iCloud Reminders, phone
   gets Apple’s alert (Mac can sleep).
5. **Library** → Due soon / Overdue, open one save: *Why I kept this* is your
   words; AI summary is labelled separately. Optional: Graph view.
6. **Architecture one-liner** (see [INTERVIEW.md](INTERVIEW.md)): two apps,
   one task list, neither writes the other’s file; off-Mac alerts via Apple
   Reminders, not a custom push server.

## If something breaks live

| Symptom | Fix |
| --- | --- |
| Hotkey does nothing | Reserved combo — pick another in Settings; TCC not Screen Recording |
| Empty panel / no capture | Status line → Screen Recording; rebuild with stable `DEVELOPMENT_TEAM` |
| “Ollama isn’t running” | Start Ollama; or switch provider badge to cloud with a key |
| Teach sits on step 1 | Use strip arrows; speech is not required to advance |
| Mirror toggle flips off | Reminders + Calendars entitlement/TCC; Open System Settings from the caption |
| Mirror on, phone silent | Orange “this Mac only” copy — enable iCloud Reminders, toggle off/on |
| Dictation silent on first Parakeet press | Wait for “Loading the Parakeet model…” |

## Sample screens that photograph well

- A Swift file with a clear bug and named buttons/labels
- A shell error with a stack trace
- A web tutorial with numbered steps (Teach me)

Screenshots for slides live in [screenshots/](screenshots/).
