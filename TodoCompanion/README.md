# TodoCompanion (native macOS)

A menu bar companion that answers questions about what is on your screen right now, and remembers
things you explicitly ask it to remember — along with *your own stated reason* for keeping them.

The assistant is called **Max**. That is a name and a tone in the prompt and the interface, not a
separate thing from the app: the bundle stays `surya.TodoCompanion`, because renaming it would
invalidate the Screen Recording permission and move the database.

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
Answer streams into the panel · ⌘P boxes the control it named, on screen
```

Press **⌘R** to drag out one region and ask about that instead. It crops the screenshot already in
memory rather than capturing again. The region stays selected across follow-ups, so you can keep
asking about the same rectangle.

**Explain** and **Next step** are the two questions worth a button, and they are shortcuts for when
you have nothing specific to ask. If you have already typed or dictated something, that is what gets
asked — a preset never overwrites your own words, so with text in the field both buttons do the same
thing as pressing Return.

**⌘D** dictates instead of typing, on-device, with a ring at the cursor driven by your actual input
level — so a microphone that is producing silence looks like silence rather than like a hang.

Two recognizers are available under Settings → Dictation, and both run on this Mac. **Apple** is the
default and needs nothing downloaded, but it ends a phrase at every pause. **Parakeet** runs on the
Neural Engine and keeps up across pauses, at the cost of fetching a model of a little over a hundred
megabytes the first time you use it. The choice is quality against disk space; your voice is not sent
anywhere either way.

### Keeping asking

The answer is not the end of it. Ask a follow-up and the earlier turns go with it, so "why that one?"
or "now what?" resolve against what Max just told you instead of starting from nothing.

A conversation outlives the panel. Clicking into the app you are asking about dismisses the panel —
that is how every floating panel on the system behaves — and the transcript is kept, so summoning
again picks the conversation back up with a fresh capture. It is dropped after five minutes of not
being touched, so a summon after lunch is not answered against what you were doing this morning.
Without that, follow-up questions were impossible in exactly the situation they exist for: reaching
DaVinci to do the step you were just given *is*, from this app's side, a click outside it.

**⌘L** captures the screen again without dismissing, for when the screen changed on its own. That is the whole point of the feature:
you do the thing you were told to do, the screen changes, and you ask what is next without losing the
thread. The prompt says a fresh capture describes the screen *now*, so Max does not keep describing a
screen that has moved on. **⌘K** starts a new conversation about the same capture.

Only the last few turns are sent. The text on your screen already dominates the prompt, and an
unbounded transcript would push it out of a smaller local model's context window — answers would get
worse the longer you talked, which is the opposite of what this is for.

Two things worth knowing about the second case. Asking moves your words out of the field, so **⌘S**
afterwards files the save under the first question you typed rather than refusing. And preset wording
is never used that way: "Explain what this is" is the app's sentence, not yours, and only your own
words are ever stored as your reason for keeping something.

Pressing **⌘S** keeps the transcript along with the screen it was about. Conversations are never
saved on their own: most summons are throwaway, and filling the library with material you did not
choose to keep is the opposite of how the rest of this works. It rides along with the decision you
already make.

### Hearing it

Turn on **Have Max read answers out loud** in Settings and answers are spoken as they arrive, a
sentence at a time, using the speech voices built into macOS. Nothing is sent anywhere for this —
the ban on cloud transcription applies just as much in reverse, since a hosted voice would export
whatever is on your screen to a company that is not even answering the question.

It is off by default, stops the moment you dictate, ask something else, or close the panel, and there
is a button in the panel header to stop it mid-sentence. Code blocks are announced rather than read
aloud, because hearing a function read out character by character is unbearable and too long to
interrupt.

### Working on one file

Open a file from the panel header and Max can propose a change to it. You are shown a diff, and
nothing is written until you press **Apply**.

This is deliberately not an agent that edits your project. It sees a screenshot, has no file tree,
and cannot run your tests, so the editor you already have open is better at that in every respect.
What it can do instead is answer a question about the code that is on your screen and hand back a
concrete change.

The scope is one file, picked by you through a file dialog — there is no way for it to reach a file
you have not pointed at. Max returns the whole file rather than a patch, because models get diff line
numbers wrong far more often than they mangle an entire file, and the diff you see is computed here
from the two versions, so it cannot be wrong about what changed. A reply whose code block was cut off
is refused rather than applied. **Revert my last applied change** puts the file back as it was before
the conversation touched it, which is a convenience and not a substitute for version control.

### Showing you where

When an answer names a control that is on screen, a **Show me "Fairlight"** button appears under it.
Press it, or **⌘P**, and a box is drawn around those words on your actual screen for a couple of
seconds. The panel does not need to stay open, so you can press it, click into the application, and
still see where you were pointed.

It finds things by reading pixels — the words Vision already recognized, with each word's position
kept — rather than by asking the application through the accessibility tree. That sounds like the
lesser option and is not, for one reason: **Max can only name what it can read.** It is shown a
screenshot, so the words it uses are words the OCR has. An accessibility tree mostly knows about
controls Max could never have referred to, needs a permission this app declines to require, and is
thin or missing in precisely the applications this helps with most — DaVinci Resolve, Blender, games,
anything drawing its own interface. Reading pixels works wherever you can see.

It would rather show you nothing than the wrong thing. Max is asked to quote a control's label
exactly, and a quoted label beats any unquoted guess; an unquoted one has to be long or multi-word,
and words Max uses to *describe* controls — "menu", "panel", "button" — can never match. So an
unlabelled icon is not findable, and the button simply does not appear. That is deliberate: Max
describes those by position, and a confident box over the wrong icon is worse than no box at all.

Your pointer is never moved. The box shows you where to look, and your hands stay yours.

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
not words. Locally it needs a vision model (`qwen3-vl`) to be worth turning on.

Selecting OpenAI without saving a key falls back to the local model, and the badge says so rather
than quietly reading "Local".

Which OpenAI model answers is chosen in Settings, from a short list with a note on what each is good
for. The list is fixed rather than read from your account, so it is useful before a key is saved;
pick **Custom…** to name a model released after this build.

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

You do not have to press ⌘S for that. When what you typed is plainly an instruction — an explicit
"remind me" **and** a time stated in the sentence — pressing Return sets it, rather than asking Max
about it:

```text
⌃⌥Space → "remind me to text voice bugs at 10 AM today" → Return
        → "Saved · reminder today at 10:00 AM"
```

Both halves are required, so "remind me what a closure is" names no time and is still answered as the
question it is. Switching the offered reminder off before you press Return also makes it a question
again.

Reminders are local notifications, so they need this Mac awake when they fire.

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

This happens **only when you summon it**. Nothing polls in the background and no capture occurs that
you didn't ask for.

### Matching by meaning

Turn on **Match saved context by meaning** in Settings and "screen capture" will also find a note
that says "display grabbing". It needs a second Ollama model:

```sh
ollama pull nomic-embed-text
```

Meaning is one signal among several rather than a replacement for them, and it obeys the same rule as
everything else here: it carries a reason, shown as **close in meaning**. That was the condition on
using embeddings at all — a match that can't say why it surfaced is indistinguishable from the app
guessing. So a vector distance is only allowed to *contribute* to a score it can also explain, it can
only ever add, and in library search a save that literally contains your words is never pushed below
a mere resemblance.

Embedding runs on this Mac and is never sent anywhere, even when OpenAI is answering your questions.
That is enforced the same way summaries are: `embed` is absent from the `Brain` protocol and exists
only on `OllamaBrain`, so no cloud provider can be attached to it. Embedding is in fact the worst
thing to export, because it runs once per *save* rather than once per question — the volume is your
whole library, not a single deliberate ask.

Off by default, because it needs that second model and a feature that silently does nothing until an
unrelated command is run is worse than one you turned on deliberately.

## Seeing how it connects

The library has a **Connections** button. It draws what you kept as a graph: each save, the project
it belongs to, the `#tags` you gave it, and the app it came from. Hovering a node dims everything it
does not touch, so you can follow one thread; clicking a save opens it. Projects, topics and apps can
each be switched off when the picture gets busy.

There is no graph database behind this and there isn't going to be. Those relationships already exist
in SwiftData, so Neo4j would add a server and a query language without adding a single edge — the
plan says as much. What was actually missing was a way to look at them.

The layout is deterministic. Reopening the window gives you the same picture, which is what makes it
worth learning the shape of; a simulation that settles somewhere new every time is impressive once.

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

This is an Apple Silicon app. A **Release** build additionally needs `ARCHS=arm64 EXCLUDED_ARCHS=x86_64`
on the command line, because FluidAudio has no x86_64 support and Xcode compiles a Swift package for
every architecture in the build request regardless of what the depending project asks for. Debug builds
only the active architecture already, so they need nothing extra.

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

## Capturing from your phone

Point **Capture from your phone** in Settings at a folder, put that folder in iCloud Drive, and a
Shortcut on your iPhone can save into it. Anything it drops there is brought in when the app launches
and each time you summon the panel, and then **removed from the folder** — it is a transport, not
storage, and the screenshot lives in the app's own store once imported.

This is a folder rather than an iCloud container on purpose. A real iCloud container needs an
entitlement that requires the paid Apple Developer Program, which this project does not have. A
*folder* inside iCloud Drive needs no entitlement at all and syncs just as well — and as a side
effect the same mechanism works with Dropbox, Syncthing, or a plain local folder.

### The Shortcut

Build it once on the phone, in the Share Sheet so it can accept a screenshot:

1. **Shortcut Details** → accept **Images** and **Text** from the share sheet.
2. **Ask for Input** (Text) → prompt "Why keep this?". This is the intent field, so it holds *your*
   words. Dictation works here.
3. **Base64 Encode** the shortcut input (the image).
4. **Dictionary** with four keys:

   | Key | Value |
   |---|---|
   | `intent` | the Ask for Input result |
   | `imageBase64` | the Base64 Encode result |
   | `createdAt` | Current Date, formatted ISO 8601 |
   | `source` | `iPhone` |

5. **Save File** into the folder you linked, with **Ask Where to Save** off and the name set to
   anything unique — the date works.

Use the **Dictionary** action rather than building the JSON as text. Shortcuts serializes a dictionary
correctly, whereas a text template breaks the moment your reason contains a quote or a newline.

The image travels base64-encoded inside the JSON rather than as a second file, which matters over a
syncing folder: two files sharing a name arrive independently, so a reader can see a manifest whose
image hasn't landed yet and can't distinguish that from an image that is never coming.

`#tags` you type on the phone become topics exactly as they do on the Mac. A reason with no image is
accepted — a thought captured on a walk is what this is for. An image with **no** reason is refused,
because the reason is the thing this app is built around and inventing one would be inference posing
as your words. A file that fails to parse is left in the folder rather than deleted, since its staying
put is the only signal anything went wrong.

## Layout

| Path | Role |
|------|------|
| `App/` | `NSApplicationDelegate`, activation policy, hotkey wiring, Settings UI |
| `Companion/` | The `NSPanel`, its placement logic, view model, and SwiftUI panel |
| `Capture/` | ScreenCaptureKit capture, Vision OCR, region selector, cursor indicator, on-screen highlight |
| `Brain/` | The `Brain` protocol, shared prompt text, Ollama and OpenAI clients |
| `Voice/` | The shared microphone, the Apple and Parakeet recognizers, input level metering, and spoken answers |
| `Store/` | SwiftData models, retrieval scoring, embeddings, reminder parsing, the to-do bridge, phone import, diffing and the editable file |
| `Library/` | Browse, search, graph, and manage what you've kept |
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

Answers are spoken by the speech voices built into macOS, so enabling that sends nothing anywhere.
There is no wake word and no always-listening mode: the microphone opens when you open it.

Max can write to exactly one file, chosen by you through a file dialog, and only when you press Apply
on a diff. Inference never writes to disk on its own.

Nothing is drawn over your screen unless you ask for it, and your pointer is never moved. No
Accessibility permission is requested or used — the global hotkey, the click-outside dismissal, and
the on-screen highlight were each built to avoid needing it.

The App Sandbox is enabled, with outgoing network, microphone, and user-selected file access as the
only added entitlements.

## Not built yet

- **Remote reminders.** Reminders are local, so they need this Mac awake when they fire. A hosted
  scheduler is the one thing that would fix that, and the only reason to build one.
- **A wake word.** Saying "hey Max" would mean an always-hot microphone, which sits badly beside an
  app whose screen capture is explicit and whose mic state is deliberately visible. The hotkey is one
  keystroke and needs no Accessibility permission. The Electron app in this repository has a wake word
  and ships it off by default, which is the evidence rather than the counter-example.
- **Editing more than one file.** No project-wide agent, no running your tests, no applying a change
  you were not shown. See above for why that is a product judgement and not only a cautious one.
- **Moving your cursor for you.** Clicky flies the pointer to the element it names. Max draws a box
  around it instead and leaves your hands alone — see "Showing you where" above.
- **Speaking up on its own.** Related material appears when you summon the panel and never otherwise.
  Without Accessibility the only trigger left is "the user switched apps", which says nothing about
  whether they need anything; acting on it would mean either matching on a window title, which is
  usually wrong, or capturing unasked, which contradicts the rule that makes this safe to leave
  running. Being summonable is not a weaker version of being proactive — for a tool like this it is
  the better one.
- **An iPhone app.** Phone capture is a Shortcut writing to a folder, deliberately, and that is
  expected to stay true for a long time.
- **Signing and notarization.** `scripts/release-companion.sh` builds a DMG and publishes a release,
  but stops short of Developer ID signing, notarization, and auto-updates, all of which need the paid
  Apple Developer Program. Until then, downloaders must right-click → Open once.
