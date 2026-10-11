# Demo rehearsal (Max + To-Do Notifier)

Ten-minute live run for interviews. Do a cold rehearsal the day before with
the Mac freshly logged in so TCC prompts do not surprise you on stage.

## Pick the model before you pick the screen

Measured on an 8 GB M1 MacBook Air with `llama3.2`:

| | Local `llama3.2` | Why it matters |
| --- | --- | --- |
| Cold load | ~17–23 s | Max now warms the model when the panel opens, and keeps it 30 min |
| Plain question | a few seconds once loaded | Fine for Explain |
| Teach me | **~95 s, and no lesson** | The reply came back as prose — no numbered steps, no board |

So: **ask locally, teach on a cloud model.** Switch from the who-answers badge
in the panel header just before the Teach beat. That is inside the app's rules
— a question you asked, in the foreground, with the badge saying who answers —
and it is a better story than hiding it: local by default, cloud only when you
choose.

## Preflight (5 minutes before)

| Check | How |
| --- | --- |
| Ollama | `ollama serve`; `ollama list` shows `llama3.2` |
| Warm it | Summon Max once. Status says "Loading llama3.2 on this Mac…" the first time |
| Cloud key | Claude or Gemini key in Settings, for Teach. Badge must not read "— no key" |
| Send the screenshot | On, if you will Teach over a diagram or UI rather than text |
| Screen Recording | System Settings → Privacy → Screen Recording → **TodoCompanion** on |
| Accessibility | Granted *before* the demo if you want the cursor to follow Teach. Otherwise Teach opens System Settings once, on stage |
| Notifications | Allow for TodoCompanion when prompted |
| Reminders + Calendars | Needed only for the phone mirror beat |
| iCloud Reminders | System Settings → Apple Account → iCloud → Reminders **on** (or Settings copy stays orange "this Mac only") |
| Quiet hours | Off in the to-do app, or a "remind me" lands at the end of the window instead of when you said |
| To-do link | Max → Settings → choose the Electron app's `app-data.json` **before** flipping the mirror toggle |
| To-do app running | It imports Max's reminders as tasks within about a second of the save |
| Summon hotkey | Menu bar Max → label shows the combo (default `⌃⌥Space`) |
| Voice | Leave Parakeet and Kokoro **off** on 8 GB unless rehearsed with them |

If the panel status line names a blocker — Screen Recording, Ollama not
running, a model that is not pulled — fix that *before* talking. That line is
the cold-start contract ([USABILITY.md](USABILITY.md) §4).

## Demo spine (~10 minutes)

1. **Summon** with the hotkey. Point at the status line: it names a blocker
   or invites a question — never sits silently empty.
2. **Explain** a real screen (Xcode, a tutorial page, a terminal error) on the
   local model. The answer appears as it is written. Show quoted control names
   and the amber "Show me" box.
3. **Switch the badge to the cloud model, then Teach me** on the same screen.
   Expect a progress bar while the lesson is prepared (Teach holds the reply
   until it is complete), then the step strip, numbered boxes, spoken steps,
   and the board panel. Teach always asks for a board; if none comes back the
   status line says so and the steps still play.
4. **"Remind me in two minutes to …"** — the panel arms it and shows the time.
   Within about a second the to-do app shows the task with a **From Max** badge,
   titled without the "Remind me in two minutes" part. With the mirror on and
   iCloud Reminders, the phone gets Apple's alert and the Mac does not alert
   twice. Without the mirror, Max's own notification fires.
5. **Snooze it from the banner** when it fires. The library then reads
   "seen …" for that reminder rather than "no response yet", and opening the
   banner jumps straight to the keep.
6. **"What did I save yesterday?"** (or "…about <topic> this week"). The strip
   reads *Found in your library* with the reason each one matched — "kept
   yesterday · mentions retrieval" — and Max answers from those alone. With
   nothing in that window, it says so instead of inventing.
7. **"I have 45 minutes. What should I work on?"** — Max picks from the to-do
   app's open tasks, overdue first, quoting titles exactly and saying its time
   estimate is its own. Prep mode → Briefs offers the same at 30 min / 1 h / 2 h.
8. **Library** → open the save: *Why I kept this* is your words; *What the
   model thinks it shows* is the model's. In a project, the arrow beside a task
   opens the To-Do Notifier at that row. The Connections graph links keeps
   through words their reasons share, so it is worth showing even without
   tags. The footer says how often Max brought keeps back and how often you
   used them.
9. **Architecture one-liner** (see [INTERVIEW.md](INTERVIEW.md)): two apps,
   one task list, neither writes the other's file; off-Mac alerts via Apple
   Reminders, not a custom push server.

## If something breaks live

| Symptom | Fix |
| --- | --- |
| Hotkey does nothing | Reserved combo — pick another in Settings |
| Empty panel / no capture | Status line → Screen Recording; rebuild with stable `DEVELOPMENT_TEAM` |
| "Ollama isn't running" | Start Ollama; or switch the badge to a cloud model |
| "Ollama has no llama3.2" | `ollama pull llama3.2` |
| Bar sits still with "Loading … on this Mac" | Cold model; it is loading, not hung. Warm it before going on |
| Teach answers as plain prose, no step strip | The model ignored the lesson format — expected on the local model. Switch the badge |
| Teach sits on step 1 | Use the strip arrows; speech is not required to advance |
| Task not in the to-do app | Is it running? It also imports on a 30 s tick and when its window is focused |
| Mirror toggle flips off | Reminders + Calendars entitlement/TCC; Open System Settings from the caption |
| Mirror on, phone silent | Orange "this Mac only" copy — enable iCloud Reminders, toggle off/on |
| Dictation silent on first Parakeet press | Wait for "Loading the Parakeet model…" |
| Recall answers about the screen instead | Ask in the past tense — "what did I save", "what was I working on". Present tense is a screen question by design |
| Arrow to the to-do app opens it but not at the row | The installed To-Do Notifier predates the link; install the new build |

## Sample screens that photograph well

- A Swift file with a clear bug and named buttons/labels
- A shell error with a stack trace
- A web tutorial with numbered steps (Teach me)

Screenshots for slides live in [screenshots/](screenshots/).
