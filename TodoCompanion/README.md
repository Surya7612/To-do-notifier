# TodoCompanion (native macOS)

A menu bar companion that answers questions about what is on your screen right now, and remembers
things you explicitly ask it to remember — along with *your own stated reason* for keeping them.

The assistant is called **Max**. That is a name and a tone in the prompt and the interface, not a
separate thing from the app: the bundle stays `surya.TodoCompanion`, because renaming it would
invalidate the Screen Recording permission and move the database.

It runs alongside the Electron app in this repository rather than replacing it. See
[`docs/PLAN.md`](../docs/PLAN.md) for the design
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
Answer streams in, formatted · ⌘P boxes the control it named, on screen
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

**⌥⌘Q ×2** skips straight to that without Accessibility: press the combo twice quickly and it brings
the panel up with the microphone already open; twice again stops it. A single press does nothing, so an
accidental brush does not start listening.

With **Accessibility extras** enabled in Settings (and granted in System Settings), **Tab+Q** does
the same — hold Tab, press Q — and **Show me** also moves the pointer onto the named control. **Guided**
Teach warps the cursor from step to step as Max speaks. OCR boxing stays available either way.

This is not a wake word and will not become one. Nothing listens until you press the key; what the
rule protects is whether the microphone is ever open when you did not open it, and a shortcut is you
opening it. You can set the Carbon talk shortcut to **Off** in Settings, unlike the summon shortcut,
which has to exist.

Two recognizers are available under Settings → Dictation, and both run on this Mac. **Apple** is the
default and needs nothing downloaded, but it ends a phrase at every pause. **Parakeet** runs on the
Neural Engine and keeps up across pauses, at the cost of fetching a model of a little over a hundred
megabytes the first time you use it. The choice is quality against disk space; your voice is not sent
anywhere either way.

Parakeet loads onto the Neural Engine on the first **⌘D** of each run of the app, which takes a few
seconds and is captioned while it happens. Every press after that opens the microphone immediately.

Because the question is about the screen, Apple's recognizer is told which words to expect: the
distinctive ones OCR just read off it, plus your project names. It is the difference between "Swift
data" and `SwiftData`, or "fair light" and Fairlight — the proper nouns you are most likely to say are
the ones a general English model is least likely to get right, and this app happens to have already
read them.

### Keeping asking

The answer is not the end of it. Ask a follow-up and the earlier turns go with it, so "why that one?"
or "now what?" resolve against what Max just told you instead of starting from nothing.

A conversation outlives the panel. Clicking into the app you are asking about dismisses the panel —
that is how every floating panel on the system behaves — and the transcript is kept, so summoning
again picks the conversation back up with a fresh capture. It is dropped after five minutes of not
being touched, so a summon after lunch is not answered against what you were doing this morning.
Without that, follow-up questions were impossible in exactly the situation they exist for: reaching
DaVinci to do the step you were just given *is*, from this app's side, a click outside it.

**⌘T**, or the pin in the header, stops it dismissing at all. That is worth having whenever you are
meant to be working *underneath* the panel rather than between bouts of it — walking a lesson, reading
a proposed change, following a list of steps. The pin is not remembered across launches: a panel that
comes back pinned is a window you have to remember pinning, and behaving like every other floating
panel is the state that cannot strand you.

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
sentence at a time. Nothing is sent anywhere for this — the ban on cloud transcription applies just as
much in reverse, since a hosted voice would export whatever is on your screen to a company that is not
even answering the question.

Two voices are offered, and both run on this Mac. **System** is the default and uses the voices built
into macOS: nothing to download, and audibly robotic even on the premium ones. **Kokoro** runs
Kokoro-82M on the Neural Engine and sounds markedly more natural, at the cost of fetching about 174 MB
of model the first time you use it. It is refused on **macOS 26.4 and 26.5**, which carry an Apple bug
that crashes this kind of synthesis intermittently; Settings says so rather than risking the app taking
itself down mid-sentence. Every other release runs it.

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

If Max is reading answers aloud, **Box each control on screen as Max names it** makes the box keep up
with the voice: it moves from one control to the next as they come up in the sentence being read, and
disappears when the voice stops. This is the only thing in the app that draws on your screen without a
press immediately before it, so it is off until you switch it on, and while it is on it will only box a
label Max **quoted exactly**. The unquoted guesses that the ⌘P button is willing to make — a long name
like "Fairlight" that is probably a label — are refused here, because that button shows you its match
and waits, and this one cannot.

### Being taught, a step at a time

**Teach me** is the third preset, and it asks for the screen to be walked rather than explained. The
answer comes back as numbered steps, and instead of just printing them the app plays them: each step's
boxes go up on your actual screen, numbered, with the steps you have already covered left faint behind
you. A bar at the bottom of the panel steps forward and back, and **Done** takes the marks off.

```text
⌃⌥Space → "Teach me" → Return
   ↓
1. The recursion starts at "backtrack(0, [])" …          ← boxed on screen, captioned
2. "res" collects every complete path …
3. "return res" hands the finished list back …
```

Each step also prints its opening words beside its first box. Without that, the teaching was in the
panel and the screen had only rectangles on it, so anyone actually looking at their code was reading
shapes. It is the step's opening rather than the whole sentence — the sentence is already in the
panel, and the caption is there to say which step this box belongs to, not to reproduce the lesson on
top of your work.

Max can also draw an **arrow** between two boxes, and only where it wrote one itself. Two labels
appearing in the same step is not a claim that one becomes the other — "look at `res` and `nums`" is
two places to look — and an arrow asserts much more than a box does, so it is drawn when the reply
joins the two quoted labels with `→` and not otherwise.

If answers are being read aloud, the lesson follows the voice: the step advances as Max reaches the
labels it quoted. Stepping by hand reads the screen again first, because a few keystrokes reflow an
editor and every box below the caret would otherwise be a line out — pointing confidently at the wrong
line is worse than pointing at nothing.

The format is the whole mechanism, and that is the point: it is an ordinary numbered answer, parsed by
the same code that already draws numbered lists, with the same quoted labels the **Show me** button
already finds. Nothing in the reply says *where* anything is; Max names things and the OCR boxes decide
the pixels. A reply that ignored every teaching instruction is therefore still a perfectly good
answer, drawn the way answers always are, rather than a broken mode.

Which is also why it refuses easily. Fewer than three steps is a list, not a lesson, and is not worth
a mode you have to escape from. A numbered answer that quotes nothing on screen — "1. sort 2. recurse
3. backtrack" — is an ordinary answer that happens to be numbered, and starting a lesson on it would
put a bar over the panel that never draws anything. A lesson stays up for a few minutes after the
panel goes away, since reaching the code being taught means clicking outside this app.

### Answers that look like what they are

Code comes back in a fenced block: monospaced, syntax-coloured, on its own background, with the
language named and a copy button, because the panel floats over the editor the code is headed for.
Steps come back as a numbered list, and the labels Max quotes are picked out in the same amber as the
box drawn on your screen — those are exactly the words the app is willing to point at.

Amber rather than blue, and that is legibility rather than decoration. Almost every interface is
mostly blue, so a blue box competes with whatever it is drawn over, and syntax highlighting makes it
worse: a box marking a variable ends up the same family of colour as the variable. Warm sits against
all of it.

The model is asked for this rather than left to choose: without a language tag on the fence there is
nothing to colour by, and a model left alone fences code about half the time and indents it the rest,
which arrives as a paragraph in a proportional font. What is on screen also shapes the request — a
terminal is asked for the cause before the fix, source code for exact identifiers, a document for a
quoted passage. That is a guess about your screen, so it is confined to *how* an answer is written;
it never becomes your stated reason for a save, and it never draws anything.

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

They do not have to be in the same sentence, though, because Max will ask. Leave the time out and it
replies "when should I remind you?" — and answering that sets it:

```text
"remind me to record demo" → "When should I remind you to record the demo?"
"in 10 minutes"            → "Saved · reminder at 6:49 PM"
```

The save is filed under the first sentence rather than the second, since "in 10 minutes" is a time and
not a reason you would want to read back later. Asking Max something else instead drops the request,
so a time mentioned much later never attaches itself to a subject you had moved on from.

Reminders are local notifications, so they need this Mac awake when they fire.

Reminders respect the quiet hours you configured in the To-Do Notifier, and a reminder landing inside
that window shows the moved time rather than the one you asked for.

A reminder also **becomes a real task in the To-Do Notifier**, so "remind me to text voice bugs" shows
up in the list you actually work from and can be ticked off there like anything else. The companion
cannot write that app's data file, so it publishes the request and the To-Do Notifier creates the task
itself — the same "propose, don't write" rule that governs file edits. If the save was filed under a
project, the task carries that project's label.

The **notification comes from the companion**, which scheduled it the moment you set the reminder. The
To-Do Notifier shows the task, sorts it and lets you complete it, but stays quiet about it, so one
thing pings once and you always know which app to go to if you want that changed.

The To-Do Notifier picks up new requests when it starts and every half minute after, so it does not
have to be open at the time. A reminder whose time has already passed still becomes a task — overdue,
which is how that list already talks about anything you missed.

⌘S is not the only moment a reminder can exist. Anything in the library can be given one, or have its
time changed or cancelled, from the **Reminder** row in its detail pane — which is how you fix a time
the app read wrong, or add one to something you kept before you knew you would need it. A capture
[sent from your phone](#reminders-asked-for-on-the-phone) can arrive with one already set.

### Getting reminded away from this Mac

A local notification needs this Mac awake when it fires. If you are out and a task comes due, nothing
happens — which is the honest limit of doing this without a server.

Turn on **Copy dated tasks into Apple Reminders** in Settings and Apple delivers them instead. Tasks
with a due time are written into a "To-Do Notifier" list in your iCloud account, so your iPhone and
Watch alert you at the right moment whether this Mac is asleep, shut, or somewhere else. There is no
server involved, nothing to pay for, and no account beyond the iCloud one you already have.

Worth knowing:

- **Only tasks still ahead of them are copied.** An alarm set to a time already gone is delivered the
  moment it syncs, so copying a backlog would set off every overdue task at once on every device.
- **Reminders has to be on iCloud.** If it is using a local account, Settings says so rather than
  leaving you to discover that nothing reached your phone.
- **Ticking one off on your phone silences that alert and leaves the task open here.** Reminders is a
  way of delivering the alert, not a second copy of your list.
- **A reminder is handed over the moment you set it**, and the list is swept again each time Max
  launches or is summoned. That matters because "remind me in two hours" is usually said on the way
  out of the door: waiting for the next summon meant the phone never heard about the one reminder you
  most needed it to. Anything already copied keeps its alarm regardless, since Apple takes it from
  there.
- Reminders it copies are ones **it** stops announcing, so one thing still pings once. Your own tasks
  keep being nagged about by the To-Do Notifier as before.
- Turning the switch off takes back everything it added and leaves anything you wrote yourself alone.

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
Security → Screen Recording, then relaunch. The default global hotkeys use Carbon's
`RegisterEventHotKey`, so no Accessibility permission is needed for basic use. **Accessibility extras**
in Settings are opt-in and unlock Tab+Q plus Show me / Guided Teach pointer warps. Dictation additionally asks for
Microphone and Speech Recognition.

Signing is per-developer, so copy `Local.xcconfig.example` to `Local.xcconfig` and put your Apple
Developer Team ID in it. Xcode's Signing & Capabilities tab does the same thing. Without it the build
asks for a team rather than failing against somebody else's. Shipping a Gatekeeper-clean DMG also
needs a **Developer ID Application** certificate and a `notarytool` keychain profile — see
`scripts/release-companion.sh` and the distribution notes in `AGENTS.md`.

Set a team once and the signature is stable across rebuilds. This matters more than
it sounds: TCC keys its permission grants to the code signature, so under ad-hoc signing every rebuild
silently invalidates Screen Recording while the app continues to *look* enabled in System Settings.

Two Carbon shortcuts are registered, and both are picked from a list in Settings. Summoning defaults
to `⌃⌥Space`; summoning straight into dictation defaults to `⌥⌘Q` pressed **twice** and can be set to
**Off**. The options are restricted to combos macOS does not reserve: a reserved combo such as
`⌘Space` or `⌥⌘Space` is consumed by the system before the app sees it, and `RegisterEventHotKey`
*still returns success*, so the shortcut silently does nothing rather than reporting an error.

Turn on **Accessibility extras** for Tab+Q (summon + listen) and for Show me / Guided Teach to move
the pointer. Without that grant, Carbon shortcuts and OCR boxing keep working as before.

Run only one copy at a time. Carbon hot keys are exclusive, so a second instance fails to claim the
shortcut and the first one to launch keeps it.

## Connecting it to the To-Do Notifier

In Settings, point **Your to-do app** at the Electron app's `app-data.json`, normally at
`~/Library/Application Support/todo-notifier/app-data.json`. That file picker is what grants a
sandboxed app access, so it cannot be done silently.

The companion then reads your open tasks, notes, and quiet-hours setting — and only ever reads them.
Traffic in the other direction is a separate file it writes, carrying its project list and any
reminders it would like turned into tasks, which the Electron app reads and acts on. Each app owns one
file and reads the other's; neither writes the other's.

That asymmetry is the reason for the shape of it. `app-data.json` belongs to a running Electron process
that holds it in memory and rewrites it whole, with no locking between the two apps, so a second writer
would eventually lose an edit or truncate the file.

## Capturing from your phone

Point **Capture from your phone** in Settings at a folder, put that folder in iCloud Drive, and a
Shortcut on your iPhone can save into it. Anything it drops there is brought in when the app launches,
when the Mac wakes from sleep, each time you summon the panel, and when you open the library — and then
**removed from the folder**; it is a transport, not storage, and the screenshot lives in the app's own
store once imported.

Waking matters more than it sounds, because this app is meant to stay running: launch happens once and
then not again for days, so without it a capture that landed overnight waited for you to summon the
panel — at the exact moment you have no reason to, having just sat down to deal with the thing you sent
yourself. It reads the folder a few times over the first two minutes awake, since Wi-Fi and iCloud both
start up *after* macOS says the Mac is awake, and then stops. Nothing polls in the background.

If a capture is sitting in the phone's Files app under iCloud Drive but never appears on the Mac,
check Low Power Mode and the battery first. iOS holds iCloud Drive uploads while the phone is in Low
Power Mode, so the Info panel can honestly say `iCloud Drive > Companion Inbox` while the file has
not left the device. Plugging in — or turning Low Power Mode off — is what actually starts the upload;
the Mac cannot import what Apple's servers have never seen. The library window also refreshes itself
when something does arrive, including if it was already open, so you should not need to quit the app
to see a new capture.

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
   anything unique that **ends in `.json`** — the date works, so `2026-09-08T15-06-00.json`. The
   extension is not cosmetic: the importer only looks at `.json` files, so a manifest saved without
   it is skipped silently and Settings will report nothing waiting while the file sits in the folder.

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

### Reminders asked for on the phone

"Dinner for today, remind me to eat the same in 12 hours" sets a reminder when it is brought in. The
bar is the same one a sentence typed at the Mac has to clear: an explicit cue like *remind me*, **and**
a time stated in the words themselves. A date merely mentioned does not arm anything, and neither does
a request that names no time — at the Mac both are shown to you before they are armed, and on import
there is nobody there to see them.

The duration counts from **when you said it**, not when the Mac noticed. If this machine was asleep for
three hours when the file landed, "in 12 hours" still means twelve hours from the capture. If the
capture sat there longer than the time it named, the reminder is recorded but not announced — the
library shows it as "already passed", and it still becomes a task in the To-Do Notifier, which is the
better place for something overdue. Quiet hours apply exactly as they do to a reminder set here.

From there it behaves like any other reminder: Max announces it, the To-Do Notifier gets a real task
you can tick off, and if the Apple Reminders mirror is on it reaches your phone.

## Layout

| Path | Role |
|------|------|
| `App/` | `NSApplicationDelegate`, activation policy, hotkey wiring, Settings UI |
| `Companion/` | The `NSPanel`, its placement logic, view model, and SwiftUI panel |
| `Capture/` | ScreenCaptureKit capture, Vision OCR, region selector, cursor indicator, on-screen highlight, and the layer a lesson draws its marks on |
| `Brain/` | The `Brain` protocol, shared prompt text, Ollama and OpenAI clients |
| `Voice/` | The shared microphone, the Apple and Parakeet recognizers, input level metering, and the system and Kokoro voices |
| `Store/` | SwiftData models, retrieval scoring, embeddings, reminder parsing and the Apple Reminders mirror, the to-do bridge, phone import, diffing and the editable file |
| `Library/` | Browse, search, graph, and manage what you've kept |
| `Teaching/` | Reading a lesson out of a numbered answer, and following the voice through it |
| `Hotkey/` | Carbon global hotkey wrapper and the vetted shortcut list |
| `Support/` | Settings, design tokens, Keychain, notifications, EventKit, file dialogs, image encoding |

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

Both voices that can read an answer aloud run on this Mac — the macOS system voices and Kokoro-82M on
the Neural Engine — so enabling that sends nothing anywhere. There is no wake word and no
always-listening mode: the microphone opens when you open it.

Max can write to exactly one file, chosen by you through a file dialog, and only when you press Apply
on a diff. Inference never writes to disk on its own.

Nothing is drawn over your screen unless you ask for it. Your pointer is never moved unless you press
**Show me** or **Guided** (Accessibility extras). Follow-along and plain Teach me never move it.
Carbon hotkeys and OCR highlighting work with no Accessibility grant; Tab+Q and pointer warps are
opt-in.

The App Sandbox is enabled. The only added entitlements are outgoing network, microphone,
user-selected file access, and — for the Apple Reminders mirror — Reminders and Calendars. Calendars
is there because an iCloud reminder list is served by CalendarAgent, not because anything here reads
your calendar; nothing does.

## Not built yet

- **Reminders that know whether they arrived.** Copying them into Apple Reminders covers being away
  from this Mac, which was the part that actually hurt, but nothing here tracks delivery, retries a
  failure, or escalates one you ignored. Those still need a hosted scheduler.
- **A wake word.** Saying "hey Max" would mean an always-hot microphone, which sits badly beside an
  app whose screen capture is explicit and whose mic state is deliberately visible. Tab+Q or ⌥⌘Q ×2
  is one deliberate gesture. The Electron app in this repository has a wake word and ships it off by
  default, which is the evidence rather than the counter-example.
- **Editing more than one file.** No project-wide agent, no running your tests, no applying a change
  you were not shown. See above for why that is a product judgement and not only a cautious one.
- **Auto-moving your cursor while Max talks (except Guided).** Show me warps on a press; Guided Teach
  follows steps because you pressed Guided. Plain Teach me and follow-along only draw OCR boxes, so
  your hands stay yours mid-drag. Max never types into other apps or clicks Run for you.
- **Speaking up on its own.** Related material appears when you summon the panel and never otherwise.
  An app-switch trigger says nothing about whether they need anything; acting on it would mean either
  matching on a window title, which is usually wrong, or capturing unasked, which contradicts the rule
  that makes this safe to leave running. Being summonable is not a weaker version of being proactive —
  for a tool like this it is the better one.
- **An iPhone app.** Phone capture is a Shortcut writing to a folder, deliberately, and that is
  expected to stay true for a long time.
- **Sparkle auto-updates.** Releases are Developer ID signed and notarized via
  `scripts/release-companion.sh`, but the app does not yet check for updates on its own.
