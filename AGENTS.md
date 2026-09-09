# To-Do Notifier — Agent Instructions

<!-- Single source of truth for AI coding agents working in this repo. -->
<!-- AGENTS.md spec: https://agents.md -->

## Overview

Two applications share this repository.

**`TodoCompanion/`** is the active work: a native macOS menu bar companion that answers questions about
what is currently on screen and remembers things you explicitly ask it to remember. The assistant is
called **Max**, which is a name and a tone in the prompt and the UI, *not* the bundle name. Summoning it with a
global hotkey captures every display, runs OCR, and asks a model. `⌘R` narrows the question to a region
you drag out. Saving with `⌘S` stores the screenshot alongside *your own stated reason* for keeping it,
so it can be resurfaced later when related material is on screen.

**Everything else** (`electron/`, `src/`, `*.html`) is the original Electron + Vite + React to-do and
reminder app. It still runs and is not deprecated, but new feature work is happening in the native app.
The companion reads its `app-data.json` read-only through `TodoBridge`, so open tasks, notes, and the
quiet-hours setting become context for answers. It never writes to it.

### Which app owns what

The dividing line is **not** Electron versus native. It is *study and motivation* versus *context and
memory*, and the two share exactly one thing: a task list.

The Electron app owns tasks, notes, due dates, flashcards, streaks, the pomodoro timer, the pet, and
notification preferences. It is where work is **created and completed**. The companion owns saved screen
context, projects, and retrieval. It is where context is **captured and connected**.

Full migration of the Electron app into the native one was considered and rejected. It is ~7,500 lines
of working code, of which ~1,300 is a pet built on copyrighted art that cannot be shipped and ~950 is a
voice stack using cloud TTS that this app's own rules forbid. Porting it would buy feature parity with
something that already works, and would give one app a split personality. Plan §9 says the same thing.

The consequence for anything that spans the two: **the companion stores the link, not the other app.**
`Project.linkedTodoIDs` holds the to-do app's identifiers on this side of the boundary, because the
grouping is this app's idea. A task deleted over there simply stops resolving. Completing a task stays in
the app that owns tasks, and the library says so rather than offering a checkbox that would not work.

That grouping is nonetheless **visible in both**, through a second file going the other way.
`ProjectExport` publishes the project list into the companion's own container; the Electron app reads it
through `electron/lib/companionProjects.cjs` and uses it to label and filter its task list. So each app
owns one file and reads the other's, and **neither ever writes the other's**. Making projects a field on
the to-do app's own tasks was the alternative and is the thing to avoid: it would put the companion in
the position of writing `app-data.json`, a file another process holds in memory and rewrites wholesale,
with no locking between them.

The governing design document is `docs/TO_DO_NOTIFIER_UPDATED_PLAN.md`. Read it before proposing
architecture; it records what was deliberately rejected and why.

## Core principle

The companion distinguishes what the **user** said from what the **model** inferred, everywhere, without
exception. `SavedContext.intent` holds the user's own words and is never overwritten by inference;
`SavedContext.aiSummary` holds the model's gloss and is always labelled as such in the UI. Retrieval
explains itself — every resurfaced item carries a human-readable reason like `same window` or `#tag`.
If a change would blur that line, it is the wrong change.

The second rule concerns what leaves the machine. **A cloud model may answer a question the user
explicitly asked. It may never do background work.** Summaries are generated unprompted across
everything the user keeps, so that body of material stays local — and a small local model compresses
OCR text into a sentence perfectly well, so there is no quality argument for exporting it either. This
is enforced structurally rather than by convention: `summarize` is not on the `Brain` protocol, it
exists only on `OllamaBrain`, so a cloud provider cannot be wired to it. Keep it that way.

## Architecture — native companion

- **App type**: menu bar only, no dock icon (`LSUIElement`)
- **UI**: SwiftUI, with AppKit bridging where SwiftUI cannot reach (`NSPanel`, overlay windows)
- **State**: `@Observable` view models, `@MainActor` isolation, async/await throughout
- **Hotkey**: Carbon `RegisterEventHotKey`. Chosen specifically because it needs **no Accessibility
  permission**, unlike a `CGEvent` tap
- **Capture**: ScreenCaptureKit, excluding this app's own windows so the panel never appears in its
  own screenshot
- **OCR**: Vision `VNRecognizeTextRequest`, on device
- **AI**: local Ollama by default; OpenAI as an opt-in for questions only. The key lives in the
  Keychain, never in `UserDefaults`. The panel always states which one will answer
- **Speech**: `AVAudioEngine` feeding either `SFSpeechRecognizer` with `requiresOnDeviceRecognition`
 or Parakeet on the Neural Engine via FluidAudio. Both on device
- **Persistence**: SwiftData, with screenshots in `.externalStorage`
- **Cross-app**: the Electron store is reached through a security-scoped bookmark from a user-chosen
 file, which is what keeps the sandbox intact
- **Off-Mac delivery**: EventKit, publishing dated tasks into an iCloud Reminders list so Apple can
 alert a phone this Mac cannot. Opt-in, write-only, and the only thing here that leaves the machine
 without a question having been asked — which is why it is a switch the user throws, not a default

### Key architecture decisions

**Hotkeys are picked from a fixed safe list.** macOS silently swallows reserved combos — `⌘Space`,
`⌥⌘Space`, `⌃⌘Space` — *before* a Carbon handler sees them, and `RegisterEventHotKey` still returns
success. A hotkey that appears registered but never fires is almost always a reserved combo, not a bug
in the registration. `HotkeyChoice.all` is the vetted set; add to it only after testing.

**TCC permissions are tied to the code signature.** Under ad-hoc signing the grant keys on the binary
hash, so every rebuild invalidates Screen Recording and the app appears enabled in System Settings while
actually being denied. The project sets `DEVELOPMENT_TEAM` for a stable identity, which fixes this.
Consequence: unlike some macOS projects, **running `xcodebuild` from the terminal here is safe** and does
not cost you your permissions.

**The panel is a non-activating `NSPanel`.** It takes keystrokes without pulling the whole app forward,
rides across Spaces and full-screen apps, and hands focus back to the previous app on dismiss. It sizes
itself to its content and pins its *top-left* corner, because AppKit resizes about the bottom-left and a
streaming answer would otherwise walk the window up and off the cursor.

**Retrieval is structured first, and meaning is one signal inside it.** `ContextRetriever` scores on
topic hits, same-window, same-app, and token overlap. Embeddings were added later under a condition
rather than as a replacement: a vector distance may only *contribute* to a score it can also explain,
so it carries the reason `close in meaning` like every other signal, and it can only ever add. It is
weighted below "same window" deliberately — a shared window title is a fact, a resemblance is not —
and in library search a literal match is never ranked below a resemblance. With the feature off,
scoring is byte-for-byte what it was before. If a change would let an unexplained score reorder the
list, it is the wrong change.

**A stored item and a search for it are prepared differently.** `nomic-embed-text` was trained with
asymmetric `search_document:` and `search_query:` prefixes, and Ollama's `/api/embed` passes input
through untouched, so nothing adds them unless `Embedding.prepared` does. They are applied by model
name rather than always: to a model not trained on them those words are simply content, and every
vector in the library would begin with the same phrase. Because changing how text is prepared changes
the vector, the scheme is part of the recorded identity — `Embedding.identifier` appends
`+task-prefix`, `needsEmbedding` sees the difference, and `backfillEmbeddings` re-embeds over a few
summons. Without that, prefixed queries would be compared against unprefixed documents, which is worse
than doing neither.

The similarity floor is 0.55 because embedding models have a high similarity floor rather than a
zero one: measured with `nomic-embed-text`, plainly unrelated pairs score 0.31–0.40 and related pairs
0.62–0.69. Contribution scales from the floor, not from zero, or everything above the line would
arrive with the same near-maximum boost.

**Embedding is local, structurally.** `embed` is absent from the `Brain` protocol and exists only on
`OllamaBrain`, exactly as `summarize` is. Embedding is the *worst* thing to export, because it runs
once per save rather than once per question — the volume is the user's whole library, not one
deliberate ask. It embeds intent, topics, and the AI summary, but deliberately **not** the raw OCR
text, which would swamp a one-sentence reason and make every save from the same app look alike.

**Phone capture is a folder, not iCloud.** An iCloud container needs an entitlement requiring the
paid Apple Developer Program. A *folder* inside iCloud Drive needs none and syncs identically, so
`InboxImporter` takes a user-chosen folder through a security-scoped bookmark, the same pattern as
`TodoBridge`. The image travels base64-encoded inside a single JSON manifest rather than as a paired
file, because two files sharing a name arrive independently over a syncing folder and a reader cannot
distinguish "image not yet synced" from "image never coming". Importing removes what it imported —
the folder is a transport — but a manifest that *fails* to parse is left in place, since that is the
only signal the user gets that something went wrong. An item with no stated reason is refused rather
than imported with an inferred one.

The inbox is collected at launch, on every summon, **and when the library window opens**. That last
one is not symmetry for its own sake: the library is where someone goes to look at what they kept, so
being told to summon the panel first is the wrong answer in the one place the question gets asked.
Opening a window is as much a user-initiated moment as pressing the hotkey, which is what keeps this
from being the background collection the app otherwise refuses.

**A reminder asked for on the phone is carried out on arrival, at the same bar as one typed here.**
"Remind me to eat the same in 12 hours" cleared `isReminderInstruction` at the Mac and did nothing
from a phone, purely because the import path was written later and never consulted `ReminderPhrase` —
and which device a sentence was typed on is not a reason to read it differently. So
`InboxImporter.reminderDate` requires exactly what the panel requires: an explicit cue **and** a time
stated in the words themselves. The tomorrow-morning fallback is deliberately excluded, and so is a
date merely mentioned, because at the Mac those are shown before they are armed and here there is
nobody watching — "inference may suggest, not act" is a statement about *inference*, and both halves
of an explicit instruction are the user's own words.

Three things about it are load-bearing. The duration resolves against **`createdAt`, not the moment of
import**, which is the failure that would never be seen: this Mac may have been asleep for hours when
the file landed, and anchoring to import time slides every phone reminder later by exactly that long.
A resolved time **already past is recorded but not scheduled** — a non-repeating
`UNCalendarNotificationTrigger` whose date has gone by has no next matching date and never fires, so
scheduling it achieves nothing silently, whereas keeping `remindAt` makes the library print "already
passed" and still hands the to-do app something overdue, which is what that app is good at. And it
runs through **quiet hours** like any other reminder, since that window belongs to the other app and
arriving from a phone is not licence to ignore it.

Everything downstream comes free, because it all keys on `remindAt`: the save triggers
`ModelContext.didSave`, so `ProjectExport` publishes the request, the to-do app creates a real task,
and `anticipatedTasks` carries it to Apple Reminders. Wiring one call gets the notification, the task
and the phone.

**A reminder can be set on something already kept, not only as it is saved.** ⌘S was the single moment
at which a reminder could come into existence, so a missed or misparsed time could only be fixed by
saving the screen again, and an imported capture whose sentence did not clear the bar could never be
given one. The library's detail pane now sets, changes and cancels one. It schedules **before** it
stores, so a refused notification permission leaves the record alone and says so rather than showing a
reminder that will never fire — the same reasoning behind `scheduleReminder` clearing `remindAt` when
scheduling fails. This is also what makes arming on import acceptable rather than presumptuous: it is
visible and undoable after the fact, which is the one thing the panel's offer-before-arming gives that
an unattended import cannot.

**The current project is stated, not detected.** `AppSettings.currentProjectID` holds a project the user
picked, and it stays until they change it. Deriving it from the frontmost app or window was the obvious
alternative and was rejected: a wrong guess silently misfiles everything saved afterwards, and there is
no point at which the user would see that it had happened. Because the project is a stated fact rather
than something read off the pixels, it outscores every individual screen signal in retrieval (3.5) and
names itself in the reason — "in Engram". Deleting a project nullifies rather than cascades, so its
saves are unfiled instead of destroyed.

**A reminder becomes a task the other app owns, because Max proposes and the owner writes.** A
reminder set here is a time on a kept screenshot, not a to-do, and it used to leave no trace in the app
that owns tasks — so "remind me to text voice bugs" was invisible in the only list the user actually
works from. `ProjectExport` therefore publishes `requestedTasks` alongside the projects, and
`electron/lib/companionTasks.cjs` creates real tasks from them. Importing rather than mirroring is the
whole point: a task created over there is genuinely that app's, so it can be completed, rescheduled and
notified like any other, where a read-only mirror would have looked identical and done none of it. This
is the same rule as file edits — the companion still never writes `app-data.json`, because that file
belongs to a process holding it in memory and rewriting it whole.

Idempotency rests entirely on the id: the task is `companion:` plus `SavedContext.reminderIdentifier`,
which is stable across launches and store migrations. The importer runs repeatedly by design, so
anything less stable would add the same task over and over. An already-imported id counts whether the
task is open or **done** — re-adding something the user has ticked off is the failure that would make
the feature unusable. `importCompanionTasks` returns the original array when nothing is new, so the
caller skips the write rather than rewriting the file and re-rendering the list on every tick.

**The import runs in the main process, not behind the window.** It is on the same tick as the reminder
sweep and runs once at startup, because it must not depend on which panel is on screen or on there
being a window at all — the app can start hidden into the tray. Hanging it off the to-do panel mounting
was the actual bug behind "the reminder never showed up": Max published the request correctly, and
nothing on the other side ever asked. The IPC handler survives only so that returning to the window
picks up a reminder set moments ago instead of waiting for the next tick.

A fired reminder keeps being offered for `offerWindowAfterDue`, and that is not a nicety: offering only
*future* ones meant "remind me in one minute" left the export a minute later, so unless the to-do app
happened to be open inside that minute the task was never created. An overdue task is exactly what
that app is good at putting in front of someone. The window is bounded rather than indefinite because
the import keys on a stable id — a task deleted over there would otherwise return on every launch,
forever. The prefixed id is *also* appended to its project's `todoIDs`, which is derivable before the
task exists, and that is what carries the project label across without teaching the importer anything
about projects.

**Max announces its own reminders; the other app only shows them.** It scheduled a notification when
the user set the reminder, so `remindersService` skips a `companion:` task in its sweep — the two apps
would otherwise alert separately for one thing asked about once, and nothing on screen would say which
of them to go and silence. The skip is per task rather than a bail-out, since stopping the sweep on
meeting one would silence every task after it. This replaced a hand-over in which Max watched for the
task through `TodoBridge` and then cancelled its own notification: it worked, but it made a reminder's
delivery depend on whether a second app had run yet, which is a lot of machinery to decide something
the user has an opinion about anyway. Ownership stated once, in the app that took the request, is the
simpler answer.

**A reminder that has to arrive off this Mac is written into Apple Reminders.** This is the one thing
`UNUserNotificationCenter` cannot do — it needs this machine awake at the due time, which plan §Phase 7
admits outright and earmarks a hosted scheduler to fix. Apple already runs that scheduler: a reminder in
an **iCloud** list is delivered to the phone and the watch with no server, no push certificate, and no
paid developer programme. `ReminderMirror` decides what belongs there and `AppleReminders` writes it, on
the same publish-only footing as `ProjectExport` — completion is never read back, because that would
make Reminders a second source of truth for what is done. Off by default, since it is the only feature
here that puts the user's task titles into another company's sync.

**The mirror runs at launch and when a reminder is set, not only on summon.** Tying it to the summon
alone broke it in its own motivating case: a reminder reaches Apple only after the to-do app has turned
it into a task and this app has been summoned *again* to read it back, and "remind me in two hours" is
usually said just before walking away from the Mac. There was no next summon, so the phone was never
told. `AppDelegate` therefore sweeps once at launch, beside the phone-inbox import, and
`saveCurrentContext` hands a new reminder over immediately. Still not a background poll — it acts when
something happens, not on a timer.

That early hand-over needs `ProjectExport.anticipatedTasks`, and the reason is not obvious:
`ReminderMirror.plan` withdraws anything absent from the to-do app's open list, so a reminder given to
Apple before that app created the task would be **deleted by the very next sweep** — and that app may
not be running at all. So a reminder stands in for itself, under the `companion:` id the importer will
independently arrive at, until the real task appears and reconciles. It stands down as soon as the id
is known over there in *any* state, which is what lets a task the user completed withdraw normally
instead of being kept alive by the reminder that created it.

Four things about it are load-bearing. **Only tasks still ahead of us are copied**: an `EKAlarm` whose
date has passed is delivered as soon as it syncs, so mirroring a backlog would fire every overdue task
at once on every device the moment the switch was flipped. **Withdrawal keys on the task leaving the
to-do app's open list, not on it ceasing to be mirrorable** — a task simply falling due drops out of
`mirrorable`, and treating that as withdrawal deletes each reminder at the moment it was worth having.
**The list is created in a syncing source**, preferring iCloud, because `defaultCalendarForNewReminders`
may sit in the *local* account, where every part of this works and the phone never hears about any of
it; `Destination.thisMacOnly` is its own state and Settings says so. And **Max stands down for a
mirrored reminder of its own**, but only once `sync` confirms it, since standing down for something that
turned out not to be mirrored loses the reminder altogether. That is not the local hand-over the plan
rejected: this one swaps a Mac-only notification for delivery to every device, where that one swapped
one Mac notifier for another.

The permission needs a **hand-written entitlements file**, which is why `TodoCompanion.entitlements`
exists at all. Xcode has no build setting that emits a Reminders entitlement, and without
`com.apple.security.personal-information.reminders` macOS refuses even to *show* the prompt. Because
that file replaces generation, the keys the `ENABLE_*` settings used to produce are restated in it and
have to be kept in step; a mismatch surfaces as a sandbox violation at runtime, not as a build failure.

**Reminders also needs the Calendars entitlement, and this was measured rather than reasoned.** With
`personal-information.reminders` alone, `requestFullAccessToReminders()` throws `NSMachErrorDomain`
4099 — the XPC connection refused — immediately, before any prompt appears. An iCloud reminder list is
served by CalendarAgent over CalDAV, and the sandbox will not let the app reach that agent on the
reminders key alone, so `personal-information.calendars` is required too. Worth knowing because of how
it presents: the switch turns itself back off in a fraction of a second, `tccd` logs nothing, and
nothing is thrown that reaches the user. It reads as a dead control rather than a missing entitlement.
Two things follow. `requestAccess` propagates its error instead of swallowing it with `try?`, since
"refused" and "threw" need different words in front of someone — one is fixable in System Settings and
the other is not. And the activation-policy dance `FilePicker` needs is **not** needed here: a TCC
prompt is presented by the system rather than by this app, so it appears for an accessory app
perfectly well. That was tried while chasing this bug and removed once the entitlement proved to be
the cause; it only made the Settings window lose focus mid-click.

A grant is also keyed to the code signature, so stale `kTCCServiceReminders` records from earlier
builds accumulate and a denial among them makes the request fail instantly with no prompt. Clear them
with `tccutil reset Reminders surya.TodoCompanion` when the symptom looks like the above.

**Quiet hours are mirrored, not reinvented.** The user configured a do-not-disturb window once, in the
app that owns notification preferences. `QuietHours.contains` deliberately reproduces `inQuietHours` in
`electron/lib/dataMerge.cjs`, down to treating an equal start and end as *never* quiet rather than always
— two notification systems disagreeing about one setting is worse than one of them ignoring it, because
the disagreement is invisible. A reminder landing inside the window moves to the end of it, and the panel
shows the moved time rather than the requested one.

**An explicit reminder instruction is carried out, not asked about.** `CompanionViewModel.submit`
routes to the save path when `isReminderInstruction` holds, which needs an explicit cue *and* a time
stated in the sentence, with the offered reminder still armed. "Remind me to text voice bugs at 10 AM
today" was otherwise sent to the model, which replied by explaining how to create a reminder in some
other application — the app declining to do the one thing it had plainly been told to do. This is not
the parser acting on inference; it is the user's own instruction, which is why a stated time is required
rather than `ReminderPhrase`'s fallback guess of tomorrow morning. "Remind me what a closure is" names
no time and stays a question, and switching the offered reminder off makes the sentence a question
again. Preset wording can never qualify.

**The cue and the time may arrive in two messages, because Max asks for the second one.** "Remind me
to record demo" states no time, so it stays a question — and Max answers it by asking when. It could
not then act on the reply: a bare "in 10 minutes" carries no cue, so each half alone was only ever a
question and the conversation Max itself opened could not be finished. `ReminderPhrase.pendingRequest`
holds the outstanding request and `isInstruction` lets a stated time complete it. This is still not
inference acting: both halves are the user's own words, and Max asked for the second. Two bounds keep
it that way. A message stating **no** time closes the request rather than leaving it open, or a time
mentioned much later would attach itself to a subject the user had walked away from. And the save is
filed under the *original* request rather than the typed field, because "in 10 minutes" is a time and
not a reason anyone would want to read back later — which is why `saveCurrentContext` takes a `reason`
override at all. Both functions are pure and tested; the view model only holds the outstanding string.

**A reminder is set by the user, never by the parser.** `ReminderPhrase` reads a saved reason and may
*offer* a time, but it only arms the reminder by default when the user actually used words like "remind
me". A date noticed in passing — "notes from tomorrow's standup" — is offered switched off. The chosen
time is always displayed, along with the words it came from, so the app's reading is visible rather than
applied silently. This is the core principle applied to scheduling: inference may suggest, not act.
Note that `NSDataDetector` takes no reference date and always resolves relative words against the system
clock, which is why the tests assert relative facts instead of fixed timestamps. A fixture that states a
clock time has to state a future day alongside it for the same reason: a stated hour already gone is
rejected by design, so `"at 10 AM today"` made the suite pass every morning and fail every afternoon.

**`NSDataDetector` does not understand durations shorter than a day, at all.** Measured, not assumed:
it matches `in 3 days`, `in 2 weeks`, `next tuesday at 4` and `tomorrow`, and returns *nothing* for
`in an hour`, `in 10 min`, `in 90 seconds` or `in 1 hour 30 minutes`. It also requires digits, so
`in three days` and `in a week` fail while `in 3 days` works. This is why `ReminderPhrase` carries its
own `durationPattern`, and why that runs **before** the detector rather than after: a stated duration
is the user saying when they want something back, whereas a clock time elsewhere in the sentence is
usually part of what they are describing — "remind me in an hour about the 3pm meeting" means an hour.
A duration of a day or more still gets the morning treatment a bare "friday" does, because it states
no time of day; anything shorter means exactly what it says and must not be moved. The failure this
fixes was total rather than partial: with no time found, "remind me to send an email in one minute"
fell to the tomorrow-morning fallback, and because a fallback states no time it also failed
`isReminderInstruction`, so it went to the model — which replied that it could not set reminders.

**A notification trigger built from date components must include `.second`.** Truncating to the minute
fires every reminder up to 59 seconds early, and for anything less than a minute out it rounds the
target into the *past*, where a non-repeating `UNCalendarNotificationTrigger` has no next matching
date and so never fires at all — silently, since scheduling itself succeeds.

**Who answers is switchable from the panel, not only from Settings.** The badge in the panel header is a
menu, because the choice is per-question in practice: the local model reads text back fine and is worth
leaving for a diagram or an unfamiliar interface. It also carries the "Send the screenshot" toggle, which
is the setting that decides whether a visual question can be answered *at all* — OpenAI sees the screen
only if the screenshot goes with it, and otherwise receives OCR text and guesses at anything that is not
words. Both were previously only reachable through a settings window, which the click that opens it
dismisses.

**A choice that cannot be honoured is stated, not silently downgraded.** Selecting OpenAI with no key
in the Keychain falls back to the local model. Labelling that "Local" was a real bug rather than an
honest simplification: the user flipped a switch, nothing on screen moved, and the fallback was
indistinguishable from the control being broken. `AppSettings.AnswerDestination` therefore has three
cases, not two — `cloudWithoutKey` is its own state, reads "OpenAI — no key" in the problem colour,
and names what is answering instead. It is a pure function of the provider and whether a key exists,
so it is testable without a Keychain, and it is derived from the same two facts as `makeBrain()` so
the badge cannot name one model while another answers.

**File dialogs need the app to stop being an accessory for a moment.** An
`LSUIElement` app has no Dock presence and is never a normal foreground application, so macOS
declines to give it the focus a modal file dialog requires: `NSOpenPanel.runModal()` returns
`.cancel` without the panel ever appearing, logging nothing and throwing nothing. The button simply
looks dead. `FilePicker.choose` switches the activation policy to `.regular` for the duration and
restores it afterwards, which is why every open panel goes through it rather than constructing
`NSOpenPanel` directly. The cost is a Dock icon visible while the dialog is open — worse-looking than
this app otherwise is, and strictly better than a control that does nothing.

Consequence for the sandbox: user-selected files are entitled **read-write**, not read-only, because
`InboxImporter` deletes what it has imported. Read-only would have let the import succeed and the
delete fail silently, re-importing the same capture on every summon.

The same rule reaches ordinary windows, which is subtler because they look fine. An accessory app is
never frontmost, so macOS gives its windows no key focus: they draw correctly and they take mouse
clicks, so toggles, buttons and pickers all work, and only **text fields** are dead — they accept the
click, show no caret, and silently swallow typing. `SettingsView` therefore activates on appear, as
`LibraryMenuButton` already did. A window where every control works except the ones needing a keyboard
is this bug, not a SwiftUI binding problem.

**The OpenAI model is picked from a list, not typed.** `OpenAIModelChoice.all` is fixed rather than
fetched from `/v1/models`, because that endpoint only answers for a key that already works — the
picker would be empty in exactly the state a new user is in — and it returns every model the key can
reach, including embedding, audio and image models this app cannot call, so most of the list would be
wrong answers presented as choices. `Selection.custom` keeps a model newer than the build reachable
without an update, and the legacy default is listed so an existing setting shows as itself rather than
as something the user typed. The blurbs describe the tier and deliberately quote **no prices**: these
rates were cut twice in one quarter, and a stale number in the UI is worse than none.

**A question is a conversation, not a lookup.** Every summon used to be one-shot, which made the panel
useless for the thing it is best at: standing next to an unfamiliar interface and being asked "now
what?" three times in a row. `CompanionViewModel.turns` holds the exchange and `Prompt.user` replays it,
so a two-word follow-up resolves against what was just said. Two consequences worth knowing. History is
capped at `Prompt.historyLimit` because the screen text already dominates the prompt and an unbounded
transcript would push it out of a small local model's window — answers would get *worse* the longer you
talked, which is the opposite of the point. And `lookAgain` re-captures while keeping the transcript,
because the screen changing is the normal case between turns rather than a reason to start over; the
prompt says so, so the model does not describe a screen that has moved on.

**A conversation outlives the panel.** `hide()` calls `endSession()`, not a full reset, because
reaching the app being discussed means clicking outside this one and the click-outside monitor treats
that as a dismissal. Wiping `turns` there made follow-ups impossible in the one situation they exist
for — the panel could hold a conversation only while the user never touched the app they were asking
about. It is resumed on the next summon within `conversationResumeWindow` and dropped after, keyed on
*time* rather than on the frontmost app: the screen changing between turns is the intended case, so
"different app" would end the conversation exactly when it was working. A turn dismissed before it
was answered is removed rather than kept, or it would sit in the transcript showing an ellipsis and
go back to the model as something Max failed to answer.

**An answer is drawn as the thing it is.** The panel used to render every reply as one run of
proportional body text, which put backticks and asterisks on screen as literal characters and set code
in a font where alignment carries meaning. `AnswerContent.blocks` splits a reply into paragraphs,
headings, lists and fenced code, and `CodeHighlighter` colours the last of those. The parser runs again
on every streamed chunk rather than incrementally, because a reply is a few hundred characters and the
alternative is keeping a parser and a view in agreement about a half-written document — which is also
why an *unclosed* fence is a first-class state rather than a parse failure: mid-stream it is the normal
case, and treating it as unparseable would show raw backticks until the last token arrived and then
snap them into place.

The prompt is the other half of this and is not optional. A model left alone sometimes fences code and
sometimes indents it, so `Prompt.formatting` asks outright for a fenced block with a language tag —
without the tag there is nothing to colour by. The four-sentence cap had to say that code blocks and
list items do not count towards it, or asking for brevity and asking for a code block are contradictory
instructions. The highlighter is deliberately lexical and shallow: almost all of the value is in
separating comments and string literals from structure, which needs no grammar, and its one hard
guarantee is that the text comes back byte-for-byte — the user copies it into their editor.

Quoted labels are coloured the same blue the on-screen box is drawn in. That is not decoration: those
are the words the app is willing to point at, so the emphasis in the panel and the emphasis on the
screen are making one claim.

**The prompt is shaped by the kind of screen, and that is all inference may do here.** `ScreenKind`
reads the OCR text and appends one paragraph to the system prompt — a terminal gets "lead with what
went wrong", code gets "spell identifiers exactly", a document gets "quote the passage". It is bounded
so that being wrong is cheap: every branch narrows *how* to answer and none of them changes whether to,
so a misread screen costs an oddly-shaped answer rather than a refusal. This is the same line the rest
of the app draws — inference may suggest, never act — and the reason it lands on the permitted side is
that nothing here is stored as the user's words or drawn on their screen. Terminal is tested before
code because a shell displays code, and "contains the word error" is deliberately *not* a terminal
signal: an editor showing a diagnostic, a browser on Stack Overflow and a form with a failed validation
all contain it.

**Max is a name and a tone, never a licence.** The persona lives in `Prompt.system` and in UI copy. It
is emphatically *not* the bundle name: renaming the bundle would invalidate the Screen Recording grant,
which TCC keys to the signature and identifier, relocate the SwiftData container, and break
`electron/lib/companionProjects.cjs`, which hardcodes `surya.TodoCompanion`. The prompt states outright
that a persona does not permit inventing what is on screen or softening an "I don't know", because a
friendly voice is the classic way grounding rules get quietly loosened. `Prompt.summarySystem` exists
for the same reason in reverse: a background one-line gloss is a label in a list, not something said to
anyone, so it gets no persona at all — `summarize` was routed through `answerStream` and inherited the
teacher's instructions, which made for visibly worse summaries.

**Asking empties the field, so saving needs a stated fallback.** `Turn.savableReason` prefers the typed
field and otherwise uses the first question the user actually typed, since ⌘S straight after asking
would otherwise refuse with the field looking empty for no visible reason. Preset wording is
**ineligible**: "Explain what this is, in plain language" is this app's sentence, and storing it as the
user's reason for keeping something would break precisely the stated-versus-inferred distinction the
app exists to maintain. That is what `Turn.isFromPreset` is for; the model never sees it.

**A preset never overwrites what the user typed.** `presetAsk` returns the typed text when there is
any, and the preset's wording only when the field is empty — a preset is a shortcut past typing
"explain this", not a replacement for a question already asked. Assigning `preset.question` over the
field discarded the user's own words, and did so most damagingly right after dictation, where a
sentence vanishing gives no hint that a button caused it. It also mislabelled the turn as
`isFromPreset`, which put the wrong sentence in front of `savableReason`. Consequence: with text in
the field both presets do the same thing, so the buttons say as much in their tooltip rather than
appearing to offer a choice that no longer exists.

**`stopSpeaking` on an idle synthesizer wedges it.** `AVSpeechSynthesizer.stopSpeaking(at:)` called
when nothing is being spoken leaves the instance in a state where every later `speak` is accepted and
silently never heard. `SpeechPlayback.stop()` runs at the top of every question, so the unconditional
version meant answers were *never* read aloud and the setting looked inert. It now returns early unless
the synthesizer is actually speaking, and replaces the instance after a real stop rather than reusing
it, since recovery is undocumented and evidently version-dependent. `isSpeaking` is driven by a delegate
rather than set on enqueue, or the stop button stays lit after the answer ends.

**The microphone is shared; the recognizer is swappable.** Opening the input device, metering it,
naming it and watching it for silence is identical whoever transcribes, and it was the fiddly part to
get right, so `SpeechDictation` keeps all of it and hands buffers to a `DictationRecognizer`. Apple's
backend stays the default because it needs nothing downloaded — asking for a hundred megabytes before
anyone has tried the feature is the wrong trade for a default — and `AppSettings.DictationEngine`
switches to Parakeet, which runs on the Neural Engine through FluidAudio, this project's only Swift
package dependency — it later earned its place twice over by also supplying the Kokoro voice. Both run
on this Mac; the choice is quality against disk space, never privacy, and neither may be swapped for a
hosted service.

The recognizer is **kept between sessions**, and rebuilt only when the setting changes. Parakeet's
models take tens of seconds to load onto the Neural Engine, so constructing one per session paid that
on every single press of the dictation key and made its own `modelsLoaded` guard unreachable — the
object never survived to read it. `willLoadModel` exists so the first press of a session can say what
the wait is, since an unexplained pause on a key press reads as the key having been ignored.

Parakeet's transcript is **cumulative**: the model keeps its own accumulated tokens across pauses, so
the problem described next is absent by construction there rather than stitched back together. Its
audio is *copied* rather than its buffer retained, which is not an optimization detail — a tap's
buffer is only valid for the duration of the callback, and this backend looks at the audio a fraction
of a second later, on an interval, because the recognizer is an actor and the render thread cannot
await. Apple's backend escapes this only because `append` copies synchronously.

**The screen is a vocabulary, not just a subject.** The user is dictating a question *about the
window in front of them*, and OCR has already read it, so the proper nouns they are most likely to say
are sitting in the capture — and those are exactly the words a general English model gets wrong.
`SFSpeechAudioBufferRecognitionRequest.contextualStrings` takes them, so `DictationHints` picks the
distinctive ones and `SpeechDictation.start` passes them down. Only distinctive: `contextualStrings` is
a small budget that *biases* the model, so spending it on ordinary English both wastes the slot and
skews the model towards a word it was going to get right anyway. Interior capitals and letter-digit
mixes (`SwiftData`, `qwen3`) are the whole point — a recognizer hears "Swift data" — and are kept in
preference to plain capitalised nouns when the list has to be cut, since OCR produces those in bulk
from every line of UI text. Project names come first and are never truncated away, being the user's own
coinages by definition. Parakeet's streaming manager takes no vocabulary, so it ignores them rather
than the caller having to know which backend it holds.

`addsPunctuation` is likewise **off** by default, which is why dictated text arrived as one
unpunctuated run-on. That is not only how the sentence reads: this text becomes a saved reason, a
reminder phrase and a prompt, so a missing full stop degrades everything downstream. `taskHint` is set
to `.dictation` for the same reason — the default assumes a search query. Neither affects where audio
goes; `requiresOnDeviceRecognition` still decides that.

**A dictation pause starts a new segment from empty.** `SFSpeechRecognizer` finalizes a segment when
the speaker pauses, and the next result's `bestTranscription` begins again from nothing. Assigning it
straight to the field erased everything said before the pause. `SpeechDictation` accumulates finalized
segments in `settledTranscript` and appends the in-progress one. A finished segment also used to end
the whole session, which made dictating anything with a pause in it impossible — stopping to think
stopped the recording — so a new task is started instead, and only the user ends it. The audio tap keeps
feeding buffers across that swap, so the live request is held behind a lock in `RequestHolder`.

**A crop is measured against the area currently shown, not the display.** `ScreenObservation`
records `primaryScreenFrame`, and `cropped(to:on:)` uses it in preference to `screen.frame`. Selecting a
second region measured the new selection against the whole display while the image was already a crop,
scaling by the wrong factor and offsetting by the first crop's origin — so re-selecting after a mis-drag
cropped somewhere unrelated or failed as "too small to read".

**Speech out is local, like speech in.** The ban on cloud transcription applies in reverse — routing
every answer through a speech vendor would export the contents of the user's screen to a third party
that is not even answering the question. So the picker has two entries rather than three, and
`VoiceEngineTests` pins that neither describes a hosted service. It speaks a sentence at a time so
playback starts about a second in, rather than per word, which comes out as a stilted list because
prosody needs a full clause. It is off by default, stops on `.immediate`, and stops when dictation
starts: the voice plays through the speakers and the mic would transcribe it, so Max would otherwise
dictate to itself. Markup is stripped before speaking, and a fenced block is announced rather than
read, since reading code aloud character by character is both unbearable and too long to interrupt.

`SpeechPlayback` decides *what* is spoken and when; a `VoiceSynthesizer` says it, on the same split as
dictation and for the same reason — clause-breaking and markup-stripping are identical whoever talks.
The system voices stay the default because they need nothing downloaded, and **Kokoro-82M** is the
answer to their being audibly robotic. It is reached through **FluidAudio**, which is already here for
Parakeet, so the better voice costs no new dependency. The two Swift ports of Kokoro that look like the
obvious choice were both tried and rejected: their manifests declare local path dependencies, which SPM
rejects in a remote package, and the grapheme-to-phoneme engine underneath them (`MisakiSwift`, for its
out-of-vocabulary fallback network) pulls in MLX, which needs a Metal toolchain that Xcode no longer
ships by default. That would have put a multi-gigabyte toolchain download between a clone and a build.
FluidAudio runs the same model with its own CoreML phonemizer and none of that.

The clause is also the unit of work: Kokoro synthesizes one at a time on the Neural Engine, so one
sentence is generated while the previous plays, and audio is queued through an `AVAudioPlayerNode`
because scheduling buffers keeps them in order for free. `isSpeaking` only clears when the queue is
empty *and* nothing is still playing — the worker finishes generating well before the sound ends, so
the obvious version turned the stop button off mid-sentence.

**How the answer is cut up is what makes it sound human, and one clause per synthesis is too fine a
cut.** Sending each clause the moment it ended was right for `AVSpeechSynthesizer`, which queues
utterances and shapes them itself, and audibly wrong for Kokoro: every piece gets its own intonation
contour and its own padding of near-silence at both ends, so a paragraph arrived as a sequence of
announcements. `SpeechPlayback.nextChunk` therefore sends the *first* sentence immediately — that is
what makes speech start about a second in — and accumulates to `minimumChunk` after it.

It is bounded at the other end too, and that bound is not cosmetic: Kokoro **throws** on a phoneme
sequence over 510 characters and a failed clause is dropped rather than spoken, so an unbounded chunk
is silently missing speech. Hence `maximumChunk`, a break at a word gap when a single sentence
exceeds it, and a test asserting nothing longer ever leaves. A colon is deliberately not a boundary —
it introduces the clause after it, so splitting there puts the pause in the wrong place — and a period
only counts when whitespace follows, or every decimal point and file extension ends a sentence.

`trimmedWithTail` cuts the model's padding off both ends and appends a fixed one. Taking the tail from
whatever the synthesis happened to leave was the same bug in a quieter form, because some clauses come
back with almost none and those ran together.

**Kokoro is refused outright on macOS 26.4 and 26.5.** Those releases carry an Apple bug that crashes
Kokoro synthesis inside libBNNS *intermittently*, whatever the compute units are set to; 26.6 fixes it.
FluidAudio only logs a warning. A wrong answer here does not look like a broken voice, it looks like the
app vanishing once in a while, which is a far worse outcome than a plainer voice — so
`isSupportedBySystem` decides for itself, Settings says so before the switch is flipped, and the
deployment target being lower than 26.6 is exactly why the check has to exist.

No Kokoro **voice** picker, though, unlike the OpenAI model list: voice packs are fetched individually
and nothing in the app can see which ones the downloaded bundle actually carries, so a list would be
offering choices that may not resolve — and a voice that fails to resolve drops the clause silently.
The bundle's own default is used until that is verifiable.

**Max may propose a file edit; only the user writes one.** This is deliberately *not* the autonomous
computer-use agent the plan rejects, and the argument is about product quality as much as safety: this
app sees a screenshot, has no file tree, and cannot run the tests, so a whole-project agent here would
be strictly worse than the editor the user already has open. What it can do that the editor cannot is
answer a question about the thing currently on screen. So `EditableFile` holds exactly one file, chosen
through a picker — there is no path to a file the user has not pointed at — and `apply` runs only from a
button press, after a diff. `Prompt.editingSystem` is appended only when a file is open, so a question
about the screen never arrives with instructions about rewriting files attached.

The model returns a **whole file**, not a patch, because models emit unified diffs with wrong line
numbers far more often than they mangle an entire file, and `TextDiff` computes the diff locally — a
diff derived from the two texts cannot be wrong about what changed, because it *is* what changed. For
the same reason `CodeBlock.extract` takes the **last** fenced block (explanations quote the broken lines
first) and refuses an unterminated fence outright, since a truncated file written over the user's own is
the worst outcome available here. An identical rewrite is discarded rather than offered, and `revert`
restores the file as it was before the conversation touched it rather than undoing one step of several.

**A conversation is kept because the screen was kept.** `ConversationTurn` is written only by ⌘S,
never automatically. Most summons are throwaway, and storing every one would fill the library with
material nobody chose to keep — the opposite of how the rest of the app works, where the user states
what matters. Ordering is an explicit `order` field because SwiftData to-many relationships come back
unordered, which would otherwise print a follow-up before the question it followed. The transcript
joins `searchHaystack`, since "I remember discussing this" is a real way to look for something, but is
deliberately kept out of `embeddingSource`: most of its length is the *model's* words, and embedding
those would let what Max said decide what gets resurfaced, when that field exists so the user's stated
reason drives retrieval.

**The graph is a view, not a database.** The plan rejects Neo4j, and the edges already exist in
SwiftData — a save belongs to a project, carries the user's `#tags`, and records the app it came from.
A graph store would add a server and a query language without adding one edge. What was missing was a
way to *see* them, so `ContextGraph` flattens the models into value types and `GraphLayout` runs a
deterministic Fruchterman–Reingold placement over them. Deterministic matters: reopening the window
gives the same picture, so spatial memory of your own material is worth building. A layout that
settles somewhere new each time looks impressive once and is useless twice. Rendered in a `Canvas`
rather than as views, because a few hundred `View` identities with their own animation machinery
stutter where an immediate-mode draw does not.

**Indicators are their own windows.** One-shot ScreenCaptureKit grabs get no system recording indicator,
so a capture would otherwise be completely invisible — the wrong property for a feature that reads your
screen. `CaptureIndicator` draws a ring at the cursor; it belongs to this app and is therefore excluded
from the screenshot along with the panel. `ScreenHighlight` is a second such window.

**Pointing at a control reads pixels, not the accessibility tree.** Clicky flies the cursor to a named
element through `AXUIElement`, and that route was rejected twice over. It needs the Accessibility
permission this app declines to require, and it fails in exactly the applications the feature is most
useful for — Qt, Electron, games, anything drawing its own interface — with DaVinci Resolve, the
motivating case, among them.

The argument that settles it is a symmetry: **Max can only name what it can read.** It is shown a
screenshot, so its words are words Vision already has, which means an accessibility tree's extra
coverage is mostly controls Max could never have referred to. So `TextRecognizer` keeps a per-word
`TextRegion` — asked of Vision by character range, because a recognized "line" is often a whole menu
bar and its box would cover half the screen — and `ScreenTextLocator` matches the answer against them.
Vision normalizes from the bottom left and so does AppKit, so `screenRect` needs **no** vertical flip,
unlike `cropped(to:)` which targets a `CGImage`; the two conversions look alike and are not.

It highlights rather than moving the pointer, because moving it would be inference *acting* and would
fight anyone mid-drag, and it runs from a button rather than after every answer. The match is named on
that button, so the user sees which words will be boxed before anything is drawn on their screen.

**The box may follow the voice, and only a quoted label lets it.** Reading an answer aloud while the
control it names sits unmarked on screen wastes the one advantage this app has over a chat window, so
`AppSettings.followsAlongWhileSpeaking` moves the box from control to control as Max names them. That
is drawing on the screen without a press immediately before it, which is the rule above, and two things
are what keep it inside rather than beside that rule. It is off until the user throws the switch. And
it matches with `requiringQuoted`, which drops the inferred-from-prose path entirely — so the only
thing it can box is a label Max put in double quotes, which is Max stating what it meant rather than
this app guessing from a sentence. The unquoted heuristics stay available to the button, where the
match is named beforehand and the user chooses; they are exactly what must never draw unannounced.

Three details follow from the mechanism. The clause is reported when it *starts being heard*, not when
it is queued: Kokoro synthesizes a sentence ahead of the sound, so `KokoroVoiceSynthesizer` keeps
`scheduledClauses` in playback order and names the head — reporting at enqueue would run the box a
sentence ahead of the voice. A clause naming nothing leaves the previous box alone instead of clearing
it, since most sentences of an answer are about the one control it already named and blinking the box
off for each of them is worse than not having it. And the box is shown `untilHidden` rather than on the
button's 2.4-second timer, because a clause takes longer to say than that — it comes down when
`onSpeakingClause` reports silence.

Matching is deliberately reluctant: a **quoted** label outranks everything, since `Prompt.system` asks
Max to quote a control's label character for character, and that is the model stating what it meant
rather than us inferring it from prose. An unquoted candidate must be six characters or multi-word, must
not be one of `descriptiveWords` — "menu", "panel", "button" are how Max talks *about* controls, so
matching them points at whatever unrelated place the word happens to be printed — and must be
**printed on screen the way a label is printed**, meaning a capital, an interior capital or a digit.

That last rule replaced length doing the job alone, which was a poor proxy for being a name: "should",
"before" and "because" all clear six characters. The observed failure was Max asking "When should I
remind you?" and offering to point at "should" wherever it appeared. The cost is that an entirely
lowercase label is now unfindable, which is the cheaper mistake — no box, rather than a confident one
over unrelated running text — and quoting still overrides it, since that is Max stating what it meant.

An unlabelled glyph is likewise unfindable, which is the right failure: Max describes those
positionally, and a confident box over the wrong icon is worse than no box. If a change would let an
unexplained or unquoted guess draw on the screen, it is the wrong change.

## Key files — `TodoCompanion/TodoCompanion/`

| File | Lines | Purpose |
|---|---|---|
| `TodoCompanionApp.swift` | ~90 | Entry point. `MenuBarExtra` scene, settings and library windows, accessory activation policy. |
| `App/AppDelegate.swift` | ~87 | Lifecycle. Registers the global hotkey, owns the panel controller, handles reminder taps, and republishes the project export on every store save. |
| `App/SettingsView.swift` | ~409 | Hotkey, provider choice, Ollama and OpenAI settings, voice and follow-along, the to-do app link, and the Apple Reminders mirror. |
| `Companion/CompanionPanelController.swift` | ~160 | Panel lifecycle, cursor-relative placement, wiring the view model to the capture indicator. Remembers the previously frontmost app so context is not attributed to us. |
| `Companion/CompanionPanel.swift` | ~43 | Borderless non-activating `NSPanel`. Pins top-left across content-driven resizes. |
| `Companion/CompanionView.swift` | ~780 | Panel UI: status header with the who-answers and open-file menus, ask field, dictation and save buttons, save options, related-context strip, conversation transcript, the offer to point at a named control, and the diff of a proposed edit. |
| `Companion/CompanionViewModel.swift` | ~1165 | Orchestrates capture → OCR → retrieval → model → save. Owns phase state, the conversation transcript, dictation, speech playback, region selection, presets, the current project, reminders, proposed file edits, the control an answer named, and the box that follows the voice. |
| `Companion/AnswerContent.swift` | ~226 | Splits a reply into paragraphs, headings, lists and fenced code, and styles inline Markdown. Streaming-safe. Pure. |
| `Companion/CodeHighlighter.swift` | ~246 | Lexical token colouring for a fenced block, with no dependency. Pure. |
| `Capture/ScreenCapture.swift` | ~240 | ScreenCaptureKit capture of every display, permission preflight, and region cropping. Excludes own windows. Records the captured area in screen coordinates so a text box can be placed. |
| `Capture/TextRecognizer.swift` | ~100 | Vision OCR, keeping a per-word box alongside the text. |
| `Capture/ScreenTextLocator.swift` | ~218 | Finds the control an answer named among those boxes, and maps one onto the screen. `requiringQuoted` narrows it to labels Max quoted, for the follow-along box. Pure. |
| `Capture/ScreenHighlight.swift` | ~101 | The box drawn around it, briefly on a button press or until hidden while Max is talking. |
| `Capture/CaptureIndicator.swift` | ~196 | Cursor-tracking ring shown while capturing (blue) or listening (pink, driven by mic level). |
| `Capture/RegionSelector.swift` | ~137 | Drag-to-select overlay. Crops the screenshot already in memory rather than capturing again. |
| `Brain/Brain.swift` | ~286 | `Brain` protocol, `AskContext`, `Turn`, and the shared prompt text — including Max's persona, the conversation rules, the Markdown formatting rules, and the file-editing rules. |
| `Brain/ScreenKind.swift` | ~148 | What sort of material is on screen, and the paragraph of prompt guidance it earns. Pure. |
| `Brain/OllamaBrain.swift` | ~182 | Streaming Ollama client. Also the only place summaries and embeddings are generated. |
| `Brain/OpenAIBrain.swift` | ~95 | Streaming OpenAI client with vision. Opt-in; key from the Keychain. |
| `Brain/OpenAIModelChoice.swift` | ~51 | The vetted list of OpenAI models Settings offers, and whether a stored name is one of them. Pure. |
| `Voice/SpeechPlayback.swift` | ~277 | Decides what of a streaming answer gets read aloud, and when. Strips markup, sizes clauses, and reports which clause is being heard. |
| `Voice/VoiceSynthesizer.swift` | ~152 | The `VoiceSynthesizer` protocol, the shared `VoiceFailure`, and the `AVSpeechSynthesizer` backend. |
| `Voice/KokoroVoiceSynthesizer.swift` | ~234 | Kokoro-82M on the Neural Engine through FluidAudio, queued through an audio player node. |
| `Voice/SpeechDictation.swift` | ~190 | Owns the microphone for push-to-talk dictation: the engine, the level meter, the named input device, and the silent-input watchdog. Delegates recognition, and keeps the recognizer between sessions. |
| `Voice/DictationRecognizer.swift` | ~241 | The `DictationRecognizer` protocol, the shared `DictationFailure`, and the Apple `SFSpeechRecognizer` backend. |
| `Voice/DictationHints.swift` | ~96 | Picks the words on screen worth telling the recognizer to expect. Pure. |
| `Voice/ParakeetDictationRecognizer.swift` | ~148 | The Parakeet backend, on the Neural Engine through FluidAudio. |
| `Store/SavedContext.swift` | ~223 | SwiftData models (`SavedContext`, `Project`, `ConversationTurn`) and hashtag parsing. |
| `Store/TextDiff.swift` | ~168 | Line diff and fenced-code-block extraction. Pure. |
| `Store/EditableFile.swift` | ~128 | The one user-picked file Max may propose changes to, with a confirmed write and a session revert. |
| `Store/ReminderPhrase.swift` | ~272 | Decides whether a saved reason is asking to be brought back, and when. Pure logic, no notification machinery. |
| `Store/ReminderMirror.swift` | ~140 | Which of the to-do app's tasks belong in Apple Reminders, and what to withdraw. Pure. |
| `Store/ContextStore.swift` | ~25 | Shared `ModelContainer`, with an in-memory fallback rather than refusing to launch. |
| `Store/ContextGraph.swift` | ~241 | Builds the node/edge view of saves, projects, topics and apps, and lays it out. Pure. |
| `Store/ContextRetriever.swift` | ~181 | Explainable relevance scoring against the current screen, including the optional meaning signal. |
| `Store/Embedding.swift` | ~110 | Normalized vector, cosine similarity, blob storage, and the task prefixes a model is fed. Pure. |
| `Store/InboxImporter.swift` | ~258 | Brings in captures from a phone through a user-chosen folder, arming a reminder when the capture asked for one. |
| `Store/TodoBridge.swift` | ~240 | Read-only bridge to the Electron app’s `app-data.json`: tasks, notes, and quiet hours, via a security-scoped bookmark. |
| `Store/ProjectExport.swift` | ~188 | Publishes the project list and the reminders offered as tasks, for the Electron app to read. Write-only half of the bridge. |
| `Support/Reminders.swift` | ~80 | Schedules and cancels the local notification behind a reminder. |
| `Support/AppleReminders.swift` | ~200 | Writes the mirrored list through EventKit, into a syncing account so it reaches the phone. |
| `Support/AppSettings.swift` | ~304 | `UserDefaults` keys, defaults, the provider choice, and `AnswerDestination`. |
| `Support/DesignSystem.swift` | ~80 | Spacing, radius, alpha, status and code-token colours. `nonisolated`, so pure layout code can read it. |
| `Support/FilePicker.swift` | ~43 | Open panels that actually appear from a menu-bar-only app. |
| `Support/Keychain.swift` | ~60 | Generic-password storage for the one secret the app has. |
| `Support/ImageCodec.swift` | ~46 | PNG encoding and downscaling for storage and vision prompts. |
| `Hotkey/GlobalHotkey.swift` | ~89 | Carbon hot key registration. Exposes registration failure. |
| `Hotkey/HotkeyChoice.swift` | ~45 | The vetted list of non-reserved shortcuts. |
| `Library/GraphView.swift` | ~203 | `Canvas` rendering of the graph, with hover to trace a connection. |
| `Library/LibraryView.swift` | ~718 | Browse by project, search, reassign, rename, and delete saved contexts. Sets, changes and cancels a reminder on anything kept. Project overview pairs what was kept with the project's open tasks. |

## Build & run

```bash
# Native companion. The architecture override is required for Release — see below.
cd TodoCompanion
xcodebuild -project TodoCompanion.xcodeproj -scheme TodoCompanion \
 -configuration Release -destination 'platform=macOS' \
 ARCHS=arm64 EXCLUDED_ARCHS=x86_64 build

# Electron app
npm install
npm run dev
```

Terminal builds are safe here — see the TCC note above. Ollama must be running (`ollama serve`) for the
companion to answer anything.

**Release builds are Apple Silicon only, and the architecture must be forced on the command line.**
FluidAudio does not compile for x86_64 — it reaches for `Float16`, which the standard library marks
unavailable there — so the app is arm64-only now, which the project states through `ARCHS` and
`EXCLUDED_ARCHS`. Those settings do *not* reach the package: Xcode builds a Swift package for every
architecture in the build request and ignores the arch settings of the project depending on it, which
was verified against `ARCHS`, `EXCLUDED_ARCHS` and `ONLY_ACTIVE_ARCH` at project level and a
`arch=arm64` destination, all of which still produced an x86_64 compile of FluidAudio. Only a
build-request-level override works. Debug escapes this because `ONLY_ACTIVE_ARCH` is already `YES`,
which is why `xcodebuild test` needs no override.

## Tests

```bash
cd TodoCompanion
xcodebuild test -project TodoCompanion.xcodeproj -scheme TodoCompanion -destination 'platform=macOS'
```

`TodoCompanionTests/` uses Swift Testing (`import Testing`, `@Test`, `#expect`). The whole suite runs in
well under a second because it covers only pure logic — no screen, no microphone, no Ollama, no network.

What is covered, and why these pieces specifically. The table is keyed by the **file** a suite lives
in, and several files hold more than one `@Suite` — `PromptTests.swift` alone carries the conversation,
persona, savable-reason and preset suites — so a suite name absent here is usually grouped rather than
untested. `TestSupport.swift` is fixtures, not a suite.

| Suite | Covers | Why it needs a test |
|-------|--------|---------------------|
| `ScreenObservationTests` | Region crop coordinate math | Converts AppKit's bottom-left origin to CoreGraphics' top-left with a pixel scale factor. A flipped crop still returns a correctly sized image of the wrong thing, so the fixtures assert on **pixels**, not geometry. |
| `ContextRetrieverTests` | Relevance scoring and stated reasons | Decides what the app volunteers unprompted. Weights are unassertable by eye, and the failure modes are silent. |
| `TodoBridgeTests` | Parsing the Electron app's `app-data.json` | Another app owns that file and can change or truncate it. Also pins that the OpenAI key in the same file never reaches prompt data. |
| `QuietHoursTests` | The do-not-disturb window, and project↔task links | Must match the Electron implementation exactly; a silent disagreement between two notification systems is the failure mode. Also covers a task deleted in the other app leaving a dangling link. |
| `PromptTests` | Prompt construction | Where the "user intent outranks inference" rule actually lives. Regressions here surface as subtly worse answers, not errors. |
| `ConversationResumeTests` | Whether a dismissed conversation is resumed | Decides whether follow-up questions work at all, since reaching the app being asked about dismisses the panel. |
| `ConversationPromptTests` | Replaying earlier turns | The easy mistakes are handing the model the current question twice and letting the transcript grow until the screen text falls out of the context window, both of which degrade answers silently. |
| `PersonaPromptTests` | Max's tone, and the editing instructions | Pins that the persona sits *on top of* the grounding rules rather than replacing them, that editing instructions never reach a question with no file open, and that summaries stay persona-free. |
| `SavableReasonTests` | What a save is filed under | Decides which words get stored as the user's own. Pins that preset wording never can be, which is the app's central promise in the one place a convenience could quietly break it. |
| `TextDiffTests` | Line diff and hunk grouping | This is the safety mechanism for file edits, not a presentation detail — a diff that under-reported a change would get one applied that nobody agreed to. |
| `CodeBlockTests` | Pulling the file out of a reply | A model's reply is prose with a file inside it. Extracting wrongly means writing prose, or half a file, over the user's code, so an unterminated fence must yield nothing. |
| `ContextGraphTests` | Nodes and edges built from saves | A wrong edge is a wrong claim about how the user's material relates, and it is drawn large enough to be believed. Pins that shared tags collapse to one node and that filtering a kind removes its edges too. |
| `GraphLayoutTests` | Force-directed placement | No assertable "correct" coordinates, so it pins the properties that make it usable: everything placed, nothing off-canvas, connected nodes closer than unconnected, and the same picture every time. |
| `ScreenTextLocatorTests` | Which words in an answer may point at the screen | This one draws on the user's display, so a wrong match is a confident claim about the wrong pixels. Most cases pin what must yield **nothing** — a short unquoted word, a match inside a longer word, a label Vision never saw — rather than a best guess. |
| `FollowAlongMatchingTests` | What the box may point at while Max is speaking | The one path that draws on the screen without a press in front of it, so it pins the narrowing that makes that acceptable: a name the button believes on its own terms must be refused here unless Max quoted it. Also pins that the button's own behaviour is unchanged, since this added a parameter to the function it calls. |
| `AnswerContentTests` | Splitting a reply into what the panel draws | Runs on every streamed chunk, against a document whose last fence is usually still open — so an unclosed fence must parse as code rather than as failure. The wrong-parse failures are silent: a block simply renders as the wrong thing. Found the bug where "3.5 GB free" parsed as list item three. |
| `CodeHighlighterTests` | Colouring a fenced block | Colouring wrongly costs nothing, but the highlighter rebuilds the text character by character, so a scanner bug silently *drops* code the user is about to copy into their editor. Nearly all of it pins that the text survives intact; which token got which colour is barely asserted, so the palette stays free to change. |
| `ScreenKindTests` | What sort of screen is being looked at, and what that adds to the prompt | Inference deciding how a question is answered, so the property that matters is harmlessness rather than accuracy: every branch must contribute guidance and none may withhold an answer. Pins that a shell outranks the code it displays, and that the word "error" alone is not a terminal. |
| `ScreenRectTests` | Normalized box → screen coordinates | Vision and AppKit share a bottom-left origin where `cropped(to:)` needs a flip, so the mistake is a box a mirrored distance up the screen, which looks plausible. Also pins that a cropped capture maps into the *selection*. |
| `SavedContextTests` | `#tag` splitting, search haystack, hotkey choices | Runs on every save; mistakes are persisted. |
| `ReminderMirrorTests` | What is copied into Apple Reminders, and what is taken back | The only place this app writes into something Apple syncs, so every failure lands in the user's pocket rather than on screen. Pins that a backlog is *not* copied, since an alarm already past is delivered on sync and would alert for everything at once, and that a task merely falling due is not mistaken for one that was finished. |
| `ReminderPhraseTests` | What counts as asking for a reminder, and at what time | Guards the line between a request and a mention. Also pins that a bare day becomes morning, since midnight would fire while the user is asleep. |
| `OpenAIModelChoiceTests` | Which model the Settings picker shows for a stored name | The failure is silent in both directions: an unlisted name must reach Custom rather than be quietly replaced, and the legacy default must stay listed or an existing setting reads as though the user typed it. Also pins that no blurb quotes a price. |
| `AnswerDestinationTests` | What the who-answers badge says, per provider and key state | Pins that the three states stay distinguishable, since collapsing "cloud selected, no key" into "local" is what made a provider switch look broken. Also pins the badge against `Brain.leavesTheMachine`, which is computed separately in another file. |
| `VoiceEngineTests` | Which systems the Kokoro voice will run on, how an answer is cut into things to say, and the join between them | The version check guards an *intermittent* libBNNS crash on macOS 26.4–26.5, so getting it wrong reads as the app vanishing occasionally rather than as a broken voice. The chunking decides whether the delivery sounds like a person or a station announcement, which is inaudible from the code, and an over-long chunk is *dropped* rather than spoken — so it pins the upper bound as well as the lower. Also pins that neither offered voice is a hosted service. |
| `EmbeddingPreparationTests` | Task prefixes, and the identity of a stored vector | Both failure modes are invisible at runtime: a prefix sent to a model that never saw one silently degrades every vector, and a scheme change without an identity change leaves prefixed queries scoring against unprefixed documents. Pins that the backfill is triggered rather than skipped. |
| `EmbeddingTests` | Vector normalization, cosine similarity, blob round trip | The only exactly checkable part of meaning matching. Pins that a degenerate or wrong-length vector compares as *nil* rather than as zero, since zero would still attach a "close in meaning" reason to something that is not. |
| `SemanticRetrievalTests` | How meaning feeds into scoring | Enforces the condition on using embeddings at all: additive, explained, and outranked by stated facts. Uses hand-built vectors, so it tests the integration rather than anyone's model quality. |
| `DictationHintsTests` | Which on-screen words are offered to the recognizer | Both failure modes are invisible: too few and the feature does nothing, too many and the budget is spent biasing towards words that were never going to be misheard. Pins that ordinary capitalised UI text is dropped and that an identifier survives truncation. Asserts nothing about recognition accuracy, which is Apple's model rather than this logic. |
| `InboxImporterTests` | Parsing the phone's JSON manifest, and the reminder an import may arm | Written by a Shortcut, over a syncing folder, with nothing here compiling against it. A bad import is persisted and then resurfaces, so every malformed shape must yield "not an item". Also pins that an image with no reason is refused. The second suite pins the reminder bar, where two failures would be invisible rather than wrong-looking: a duration resolved against the import clock is off by however long the Mac was asleep, and arming from a date merely mentioned would fire for something nobody asked about. |
| `ProjectExportTests` | The published JSON's keys and date format, and the reminders offered as tasks | Half of a contract with a reader in another language that nothing here compiles against. A renamed key would still build and would just make project names quietly vanish from the to-do app, so these assert on the **encoded JSON**, not on the Swift types. |

The Electron side has its own suite, run with `npm test` (vitest), and
`electron/lib/companionProjects.test.ts` is the other half of that same contract: it pins that every
shape of bad or absent input lands on "no projects" rather than breaking the task list, and that a
missing `requestedTasks` — which older versions of the file have — does not take the projects with it.

`electron/lib/companionTasks.test.ts` covers the import itself, where the failure is *persisted and
compounding* rather than merely wrong once: an import that is not idempotent adds the same task on
every tick, and one that is too eager brings back a task the user has already completed. It also pins
that nothing is written when nothing is new, since that is what keeps a 30-second tick from rewriting
the file.

`electron/lib/remindersService.test.ts` pins who announces what. An imported reminder must produce no
notification here, because Max already scheduled one — and the same sweep must go on announcing every
ordinary task around it. Both failures are inaudible from the code and obvious to the user: one alert
arriving twice, or a task going quiet for no stated reason.

The rest of that suite predates the companion and covers the Electron app's own edges:
`dataMerge.test.ts` on merging a stored file with current defaults and on the external-URL allowlist,
`safeWindow.test.ts` on not addressing a destroyed `BrowserWindow`, `companionChat.test.ts` on the
chat helpers, and `src/lib/voiceParse.test.ts` on turning a spoken sentence into a command. They are
listed here so "what is tested" can be answered from this file alone.

Two conventions worth keeping:

- Assert on **behaviour** — ordering, inclusion, the reason string — rather than exact scores, so weights
  stay tunable without rewriting tests.
- When a test pins a known rough edge rather than a desired property, say so in a comment. See
  `sameAppAloneClearsTheThreshold`, which exists so that changing that behaviour is a visible decision.

Anything requiring `NSScreen`, a real capture, or a running model is deliberately **not** tested; that is
why `cropped(to:inDisplayFrame:)` exists alongside the `NSScreen` convenience overload.

## Conventions

### Comments

Comment the **why**, never the what. A comment earns its place by recording something the code cannot
show: a platform constraint, a rejected alternative, a non-obvious ordering requirement. Do not write
comments that restate the next line, narrate a change, or explain to a reviewer why a diff is correct —
those become noise the moment the change merges.

### Naming

Prefer clarity to brevity. Names should be understandable to someone with no context on the codebase.
Keep argument names the same as the variables they came from rather than abbreviating at the boundary.

### Swift

- SwiftUI unless the feature genuinely requires AppKit
- All UI state on `@MainActor`; async/await for anything asynchronous
- C callbacks and statics touched from them must be `nonisolated`
- This project builds with `MemberImportVisibility`, so import every module you use directly —
  notably `import SwiftData` in any file touching `mainContext` or `modelContainer`
- Adding an early `return` to a `switch` expression means every branch now needs an explicit `return`
- **The language mode is Swift 6**, so a data-race diagnostic is a build failure rather than a
  warning. Two consequences come up constantly. `SWIFT_DEFAULT_ACTOR_ISOLATION` is `MainActor`, so a
  pure value type needs an explicit `nonisolated` or merely *constructing* one in a default argument,
  or reading its properties from a child task, is a main-actor call — `QuietHours`, `MirroredTask` and
  `DisplayShot` are all marked for this reason. And a `[weak self]` capture is *mutable*, so a nested
  `Task` must capture `self` in its own list rather than reading the enclosing closure's copy
- Prefer proving a transfer to asserting one. `sending` on a return states that a freshly-built value
  is disconnected, which is checked; `@unchecked Sendable` states it on your authority, which is not.
  The three unchecked boxes here all wrap **framework** objects that cannot be made `Sendable` —
  `EKReminder`, `SCDisplay`, `SCRunningApplication` — and each carries the specific reason it is
  sound. Do not reach for one to move this project's own types around; that is a design problem
  wearing a concurrency costume

### Git

- Commit messages are prose explaining *why*, in the imperative mood. No bullet lists, no `feat:`
  prefixes, no emoji
- **Never** add `Co-authored-by` trailers or any other attribution. History shows the repository
  owner. Some tooling appends one unasked, so verify with
  `git log --format='%B' -1 | rg -i 'co-authored-by'` and amend if it appears
- Do not force-push shared branches

### Do not

- Do not add cloud **transcription** or **speech synthesis**, or analytics. Voice and usage data stay
 on the machine
- Do not add a wake word or any always-listening mode. The mic opens when the user opens it. Note the
 Electron app's own wake word (`wakeWordEnabled`) ships **off by default**, which is the evidence, not the
 counter-example
- Do not let inference write to disk. Max proposes a file change, the user is shown a diff, and only a
 button press writes anything. Do not extend editing past one explicitly-picked file
- Do not route background or automatic work to a cloud model. Foreground questions only, and only
  when the user has opted in. This rule replaced a blanket ban on hosted models once local vision
  proved too weak to explain what is on screen; the ban on *unprompted* export did not change
- Do not require Accessibility permission. This holds even though the owner has granted it to this
 bundle by hand: a grant on one machine is not a property of the product, and the permission still
 has to be earned from everyone who downloads it. Pointing at a control was built on OCR boxes for
 this reason, and `AXUIElement` stays out of the source
- Do not draw on the user's screen unasked, or move their pointer at all. `ScreenHighlight` runs from
 a button press and names its match beforehand; a highlight after every answer would be the app
 acting on inference, which is the same rule that governs file edits. Follow-along is the single
 exception and shows the shape any future one has to take: switched on deliberately, and restricted to
 labels Max quoted, so what reaches the screen is still something stated rather than something
 inferred
- Do not add continuous or background screen capture. Capture is always explicit and user-initiated
- Do not make resurfacing proactive. Related material appears on summon and never otherwise; plan §
 Phase 6 is **closed at that form**, not pending. Without Accessibility the only trigger left is an
 app switch, which says nothing about need, and acting on it means either matching a window title
 (usually wrong) or capturing unasked (contradicts the rule above)
- Do not present model inference as though the user wrote it
- Do not add features beyond what was asked

## Distribution

`scripts/release-companion.sh` builds a DMG and publishes a GitHub Release. It stops short of Developer
ID signing, notarization, and Sparkle auto-updates, all of which need the paid Apple Developer Program.
Until that exists, downloaders must right-click → Open once to get past Gatekeeper, and the script says
so in the release notes it generates.

## Self-update

Keep this file accurate when you change the things it describes:

1. Add new source files to the key-files table with purpose and approximate line count
2. Remove entries for deleted files
3. Update the architecture section when introducing a new pattern, framework, or permission
4. Update build commands when the build changes
5. Record new conventions the owner establishes during a session
6. Refresh line counts that have drifted by more than ~50 lines

Do not update it for minor edits or bug fixes that leave the documented architecture unchanged.
