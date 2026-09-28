# Max usability upgrades

Working notes for making the *current* companion more usable — independent of
`PLAN.md` roadmap phases. Point 10 is a non-goals list; the rest are
product upgrades that land in code.

## 1. Teaching feels like one surface

Explain / Teach / Guided / board / OCR boxes should read as one loop: ask → Max
talks → something moves → you act → next. One progress strip (“step 2 of 5”),
one stop, one Look again. Guided is an option on Teach (cursor follow), not a
third preset that people miss.

## 2. Speech that never lies about the screen

No numbering theatre, no fence narration, no clause running a sentence ahead of
the voice. Teach without speech still advances (buttons / arrow keys). Speak answers
stays a preference; teaching does not brick when it is off.

## 3. Panel that stays out of the way

Prefer a stable answer height band and internal scroll over growing into the
work. Pin is one-click obvious; starting a lesson auto-pins for that session so
working underneath does not dismiss the panel.

## 4. First successful ask in under a minute

Cold start must name the blocker: Screen Recording needed, Ollama not running,
or the hotkey that summons. A silent empty panel reads as broken.

## 5. Save / remind without thinking

After a good answer, offer Keep this with the question as the reason when the
field is empty. “Remind me …” with no time still asks when, then arms on the
reply — that two-turn path is the default, not an edge case.

## 6. Library as memory, not a file browser

Search already covers intent, tags, and meaning. Surface Due soon and Overdue
(Max reminders) as first-class scopes so unfinished loops have somewhere to go.

## 7. Pointing that recovers when the screen moved

Show me re-reads the screen when the named control is gone, then says so instead
of boxing the wrong line. Board stays for invented diagrams; OCR stays for UI.

## 8. Provider choice that matches the question

Stay local by default. For questions that are clearly about a diagram or image,
nudge once toward cloud + screenshot when local OCR-only will guess. Badge
failures (no key, vision off) stay one click to fix from the panel.

## 9. Dictation as the primary ask path

Talk hotkey reliability matches summon. First Parakeet load says “loading
models…” so the key does not feel dead. OCR hints stay aggressive for
identifiers.

## 10. What we will not chase

These make demos and break the trust model that makes Max usable next to a
private screen:

- Wake words or always-listening modes
- Continuous or background screen capture
- Proactive resurfacing (anything beyond related items on summon)
- Multi-file autonomous agents
- Cloud transcription or cloud speech synthesis

## Implementation map

| # | Primary code |
|---|---|
| 1 | `CompanionView` presets + lesson bar; `guidedTeachThisAnswer` toggle |
| 2 | `SpeechPlayback`; lesson bar arrows (no global shortcuts); teach no longer forces speech |
| 3 | `DesignSystem.Size.maxAnswerHeight`; auto-pin in `beginLesson` |
| 4 | `CompanionViewModel.statusText` + Ollama reachability probe |
| 5 | Keep-this chip in `CompanionView`; existing `ReminderPhrase.pendingRequest` |
| 6 | `LibraryView` Due soon / Overdue scopes |
| 7 | `showPointerTarget` re-capture + miss message |
| 8 | Vision nudge after ask; destination badge already fixes key/vision |
| 9 | Existing `willLoadModel` status (kept visible on talk hotkey) |
| 10 | This section; mirrored in `AGENTS.md` Do not |
