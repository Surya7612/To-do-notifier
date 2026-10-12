# Demo rehearsal (Max + To-Do Notifier)

About eight minutes. Rehearse once cold the night before so TCC prompts
happen at home, not on stage.

## Your setup (not the defaults in older notes)

You answer with **OpenAI** and speak with **Kokoro**. Teach needs that cloud
model — on an 8 GB M1, local `llama3.2` took ~95 s and came back as prose
with no lesson. Switch from the badge if it ever reads Local. Leave
"Send the screenshot" on.

Use the **MacBook mic** as input. AirPods are fine for output. Opening the
mic on AirPods can switch them to headset mode and silence Kokoro.

## Preflight (5 minutes before)

| Check | How |
| --- | --- |
| Badge | OpenAI, not "— no key". Send the screenshot **on** |
| Screen Recording | System Settings → Privacy → **TodoCompanion** on |
| Accessibility | Granted **before** you sit down, or Guided opens Settings on stage |
| Notifications | Allow for TodoCompanion |
| Quiet hours | Off in the to-do app, or a reminder lands at the end of the window |
| To-do link | Max → Settings → linked to the **`todo-notifier` folder** (not the file). Check `~/Library/Application Support/todo-notifier/companion-projects.json` exists |
| Both apps running | Max in the menu bar; To-Do Notifier 1.6+ open (hidden to tray is fine) |
| iCloud Reminders | On, only if you will show the phone. Settings must not stay orange "this Mac only" |
| Summon | Menu bar label shows the combo (default `⌃⌥Space`) |
| Screens | LeetCode LRU Cache, one Xcode file or terminal error, to-do window ready |

If the panel status line names a blocker, fix that before you talk.

## Spine (~8 minutes)

1. **Summon** (20 s). Status line names a blocker or invites a question — never empty.
2. **Ask** (1 min) on a real screen. Quoted control names, then **Show me** for the amber box. *Line:* "The model names. Vision decides where it is."
3. **Teach** (2–3 min) on LeetCode LRU, OpenAI, Guided if Accessibility is granted. Concept first, then the question, then the example. Box moves on the word; LRU is spelled out. Board panel flips with the voice.
4. **Follow-up** (45 s). "Why is get O(1)?" Short answer from where the lesson is — not a new lecture.
5. **Save** (45 s). ⌘S with your own reason. Library: *Why I kept this* is you; *What the model thinks it shows* is labelled as the model's.
6. **Remind** (1 min). "Remind me in two minutes to stretch." Panel shows the time. To-do app gets a **From Max** row, title stripped of the cue. Phone gets Apple's alert if the mirror is on; Max does not alert twice.
7. **Recall** (30 s). "What did I save today?" Strip reads *Found in your library* with a reason. Empty window → it says so.
8. **Close** (20 s). Two apps, one task list, neither writes the other's file. Off-Mac alerts via Apple Reminders, not a push server.

Cut the graph, "what should I work on", and the phone inbox unless you have spare time.

## If something breaks live

| Symptom | What you do |
| --- | --- |
| No box / cursor still | Step arrows re-read the screen. "It refuses to point when the quote is not on screen." |
| Silent voice | MacBook mic. Arrows still advance the lesson. |
| Teach is plain prose | Badge is Local — switch to OpenAI. |
| First answer hangs | Cold model. Narrate; you should have summoned once already. |
| Hotkey dead | Menu bar icon. Reserved combo → pick another in Settings. |
| No **From Max** row | Is the to-do app running? Unlink and choose the `todo-notifier` folder in Max Settings, set the reminder again. It also imports on focus and a 30 s tick. |
| Mirror toggle flips off | Reminders + Calendars in System Settings. |
| Phone silent, Mac fine | Orange "this Mac only" — enable iCloud Reminders, toggle the mirror off/on. |
| Recall talks about the screen | Past tense. "What did I save" searches the library; "how do I save" is a screen question. |

A refusal narrated calmly ("it would not invent a box") is worth more than a perfect run.

## Architecture one-liner

Max captures only when you press a key, answers only when you ask, and stores
your words separately from the model's. Tasks stay in the to-do app. A reminder
is published beside that app's file; Apple Reminders is the away-from-Mac
scheduler. See [INTERVIEW.md](INTERVIEW.md).
