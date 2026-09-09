import AppKit
import Observation
import SwiftData

@MainActor
@Observable
final class CompanionViewModel {
    enum Phase: Equatable {
        case idle
        case reading
        case startingDictation
        case thinking
        case answering
        case saved(String)
        case needsPermission
        case failed(String)
    }

    /// Set by the panel controller so the cursor ring tracks capture exactly.
    var onCaptureBegan: (() -> Void)?
    var onCaptureEnded: (() -> Void)?
    var onListeningBegan: (() -> Void)?
    var onListeningEnded: (() -> Void)?
    /// Draws a box around a place on screen, in global AppKit coordinates.
    /// `untilHidden` leaves it up rather than fading it out on a timer.
    var onHighlight: ((CGRect, Bool) -> Void)?
    /// Takes that box back down.
    var onHighlightEnded: (() -> Void)?

    private let dictation = SpeechDictation()
    private let regionSelector = RegionSelector()

    /// Mirrored as stored properties rather than read through to
    /// `SpeechDictation`: that type isn't `@Observable`, so computed
    /// pass-throughs would never redraw the UI when listening started.
    var isListening = false
    var dictationIsOnDevice = true
    var inputDeviceName = ""
    /// Polled by the cursor indicator to drive the voice ring.
    var currentInputLevel: CGFloat { dictation.currentLevel }
    /// Surfaced when the chosen input is producing no audio at all.
    var dictationHint = ""
    /// True while a recognizer loads its model, which the status line explains.
    var isLoadingDictationModel = false

    var phase: Phase = .idle
    var contextLabel: String = "Nothing captured yet"

    /// The conversation so far, oldest first. The last turn's answer is what
    /// `answer` is streaming into.
    private(set) var turns: [Turn] = []

    /// Reads answers aloud when the user has asked for that.
    let speech = SpeechPlayback()

    /// The one file the user opened for Max to work on, if any.
    let editableFile = EditableFile()

    /// A rewrite Max produced, waiting to be accepted or discarded. Never
    /// written without the user pressing Apply.
    private(set) var proposedEdit: ProposedEdit?

    struct ProposedEdit: Equatable {
        let fileName: String
        let contents: String
        let lines: [TextDiff.Line]
        let summary: TextDiff.Summary
    }

    /// Re-reads the reminder suggestion on every keystroke, so the offer
    /// appears and disappears as the sentence changes.
    var question: String = "" {
        didSet { refreshReminderSuggestion() }
    }

    /// The reason a save would be filed under, or nil if there isn't one yet.
    ///
    /// The typed field when it has something in it, otherwise the first
    /// question the user actually typed this session. Asking something moves it
    /// out of the field and into the transcript, and without this fallback
    /// pressing ⌘S straight after asking would refuse for no visible reason.
    ///
    /// Preset wording is skipped rather than used, because `intent` is a
    /// promise that the words in it are the user's own.
    var savableReason: String? {
        Turn.savableReason(typed: question, turns: turns)
    }

    var canSave: Bool { savableReason != nil && observation != nil }

    /// What the app thinks the typed reason is asking for, if anything.
    private(set) var reminderSuggestion: ReminderSuggestion?

    /// An explicit "remind me" that named no time, held until the user says
    /// when.
    ///
    /// Max answers such a sentence by asking "when should I remind you?", and
    /// without this it could not act on the reply: the cue and the time would
    /// sit in two different messages, and each half alone is only ever a
    /// question. Max was asking something it could not do anything with.
    ///
    /// This is not the parser inferring a request. Both halves are still the
    /// user's own words — "remind me to record demo" and then "in 10 minutes" —
    /// and Max asked for the second one, so answering it is an instruction in
    /// exactly the way the single sentence is. What it must not do is survive
    /// the user moving on, which is why any message that states no time clears
    /// it.
    private var pendingReminderRequest: String?

    /// The time a reminder will actually be set for. Separate from the
    /// suggestion so choosing a preset does not have to fight the parser on the
    /// next keystroke.
    private(set) var reminderDate: Date?

    /// Whether saving will also set a reminder.
    ///
    /// Armed automatically only when the user literally asked to be reminded.
    /// A date noticed in passing is offered switched off, because acting on
    /// inference is the one thing this app does not do.
    var reminderIsArmed = false

    /// When a reminder would land inside the do-not-disturb window the user set
    /// in the to-do app, it is pushed to the end of it — and the panel shows the
    /// moved time, because a reminder that fires an hour later than it claimed
    /// is its own small betrayal.
    var effectiveReminderDate: Date? {
        reminderDate.map { linkedWork.quietHours.firstMomentAfter($0) }
    }

    var reminderIsDeferredByQuietHours: Bool {
        guard let reminderDate else { return false }
        return linkedWork.quietHours.contains(reminderDate)
    }

    /// Whether what the user typed is a reminder *instruction* rather than a
    /// question about one.
    ///
    /// "Remind me to text voice bugs at 10 AM today" was being sent to the
    /// model, which answered by explaining how to set a reminder in some other
    /// application — the app declining to do the one thing it was plainly told
    /// to do. This is not the parser overreaching: it requires the words "remind
    /// me" (or another explicit cue) *and* a time actually stated in the
    /// sentence, so it is the user's own instruction being carried out.
    ///
    /// Both halves matter. "Remind me what a closure is" names no time and
    /// stays a question, which is why a stated time is required rather than the
    /// parser's fallback guess of tomorrow morning.
    /// Switching the offered reminder off is also an instruction, so the
    /// sentence goes back to being an ordinary question.
    /// The cue may also have been given a message earlier, when Max asked when.
    var isReminderInstruction: Bool {
        ReminderPhrase.isInstruction(suggestion: reminderSuggestion,
                                     isArmed: reminderIsArmed,
                                     hasPendingRequest: pendingReminderRequest != nil)
    }

    /// Every project, for the picker.
    private(set) var projects: [Project] = []

    /// What the user says they are working on. New saves join it, and anything
    /// already in it is favoured when deciding what to resurface.
    private(set) var currentProject: Project?

    /// Things saved earlier that look relevant to the screen in front of the user.
    var related: [RetrievalMatch] = []

    /// Open tasks from the Electron app, when the user has linked it.
    private var linkedWork = LinkedWork()

    /// True once the user has narrowed the capture to a region they dragged.
    var hasRegion: Bool { observation?.isCropped ?? false }

    /// Whether a key is stored for the cloud provider.
    ///
    /// Cached rather than read from the Keychain inside `destination`, which is
    /// evaluated on every redraw — and the panel redraws on every streamed
    /// token. Refreshed at each summon and whenever the provider changes, which
    /// covers every moment it could have become true.
    private(set) var hasCloudKey = AppSettings.openAIKey != nil

    func refreshCloudKey() {
        hasCloudKey = AppSettings.openAIKey != nil
    }

    /// Who will answer, as the panel states it. Derived from the same two facts
    /// `makeBrain()` uses, so the badge cannot claim one thing while a different
    /// model answers.
    var destination: AppSettings.AnswerDestination {
        AppSettings.AnswerDestination.resolve(provider: AppSettings.provider,
                                              hasCloudKey: hasCloudKey,
                                              cloudModel: AppSettings.openAIModel)
    }

    var localModelName: String { AppSettings.model }

    private let modelContext: ModelContext
    private var observation: ScreenObservation?
    private var captureTask: Task<Void, Never>?
    private var answerTask: Task<Void, Never>?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        reloadProjects()
        speech.onSpeakingClause = { [weak self] clause in self?.followAlong(with: clause) }
    }

    var isBusy: Bool { phase == .thinking || phase == .answering }
    var hasCapture: Bool { observation != nil }

    var statusText: String {
        if isListening {
            if !dictationHint.isEmpty { return dictationHint }
            let mic = inputDeviceName.isEmpty ? "mic" : inputDeviceName
            return dictationIsOnDevice
                ? "Listening via \(mic) (on-device)"
                : "Listening via \(mic) (Apple servers)"
        }
        // A voice that could not load is stated rather than left as silence,
        // for the same reason the badge names a provider with no key: the user
        // switched something on and nothing happened.
        if let voiceFailure = speech.failure, phase == .idle { return voiceFailure }

        switch phase {
        case .idle: return contextLabel
        case .reading: return "Reading your screen…"
        case .startingDictation:
            // Loading Parakeet onto the Neural Engine takes tens of seconds the
            // first time in a session, and an unexplained wait on a key press
            // reads as the key having been ignored.
            return isLoadingDictationModel
                ? "Loading the Parakeet model — first time only…"
                : "Turning the microphone on…"
        case .thinking: return "Thinking…"
        case .answering: return "Answering…"
        case let .saved(message): return message
        case .needsPermission: return "Screen Recording permission needed"
        case let .failed(message): return message
        }
    }

    /// Snapshots the screen behind the companion. Called as the panel appears so
    /// an answer can start the moment the user hits return.
    func captureScreen(frontmostApp: NSRunningApplication?) {
        captureTask?.cancel()
        phase = .reading
        // The boxes it was resolved against belong to the screen being replaced.
        pointerTarget = nil
        onCaptureBegan?()
        // A key may have been added in Settings since the last summon.
        refreshCloudKey()
        // Before retrieval reads the store, so something captured on the phone
        // an hour ago can resurface on this summon rather than the next one.
        InboxImporter.importAll(into: modelContext)

        captureTask = Task {
            defer { onCaptureEnded?() }
            do {
                var fresh = try await ScreenCapture.captureAllDisplays(frontmostApp: frontmostApp)
                let read = await Self.readText(in: fresh.primary.image)
                fresh.primary.recognizedText = read.text
                fresh.primary.textRegions = read.regions
                for index in fresh.others.indices {
                    // Boxes are kept for the focused display only: pointing at
                    // a monitor the user is not looking at would move their
                    // attention rather than direct it.
                    fresh.others[index].recognizedText = await Self.readText(in: fresh.others[index].image).text
                }
                guard !Task.isCancelled else { return }
                observation = fresh
                contextLabel = fresh.contextLabel
                // Re-read here rather than only at init: the library can add or
                // remove projects while the panel object stays alive.
                reloadProjects()
                related = ContextRetriever.related(to: fresh,
                                                   among: recentContexts(),
                                                   inProject: currentProject)
                linkedWork = TodoBridge.load()
                if phase == .reading { phase = .idle }
                mirrorTasksToAppleReminders()

                // Both run after the panel is already usable. Meaning matching
                // needs a round trip to the local model, and making every
                // summon wait on it would trade a visible delay for a signal
                // the user has not asked for yet.
                backfillEmbeddings()
                await addMeaningMatches(for: fresh)
            } catch ScreenCaptureError.permissionDenied {
                guard !Task.isCancelled else { return }
                phase = .needsPermission
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Re-scores the related strip once the screen itself has a vector.
    ///
    /// A second pass rather than part of the first: the structured matches are
    /// already on screen by now, and this can only add to them or reorder them.
    /// If the embedding model is missing or Ollama is down, the first pass is
    /// simply what the user keeps.
    private func addMeaningMatches(for observation: ScreenObservation) async {
        guard AppSettings.semanticEnabled else { return }

        let query = [observation.contextLabel, observation.recognizedText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !query.isEmpty else { return }

        let embeddingModel = AppSettings.embeddingModel
        let prepared = Embedding.prepared(query, as: .query, for: embeddingModel)
        guard let vector = try? await localBrain().embed(prepared, model: embeddingModel) else {
            return
        }
        guard !Task.isCancelled, observation.contextLabel == self.observation?.contextLabel else {
            return
        }

        related = ContextRetriever.related(to: observation,
                                           among: recentContexts(),
                                           inProject: currentProject,
                                           screenEmbedding: vector)
    }

    /// Vision is CPU-heavy enough to stall the panel's appearance if it runs
    /// inline, so each display is recognized off the main actor.
    private static func readText(in image: CGImage) async -> RecognizedScreen {
        await Task.detached { TextRecognizer.recognize(in: image) }.value
    }

    /// Retries after the user grants permission, so they don't have to guess
    /// whether it took effect.
    func retryCapture(frontmostApp: NSRunningApplication?) {
        captureScreen(frontmostApp: frontmostApp)
    }

    /// Ready-made questions for the two things worth asking about a region.
    /// Typing "explain this" every time is friction on the most common action.
    ///
    /// `nonisolated` because it is pure data read from `presetAsk`, which is
    /// itself nonisolated so the choice can be tested without a container.
    nonisolated enum Preset: String, CaseIterable, Identifiable {
        case explain
        case nextStep

        var id: String { rawValue }

        /// Kept short deliberately. These sit in a row with the region controls
        /// inside a 420pt panel, and the full question does not fit.
        var buttonLabel: String {
            switch self {
            case .explain: "Explain"
            case .nextStep: "Next step"
            }
        }

        var glyph: String {
            switch self {
            case .explain: "text.book.closed"
            case .nextStep: "arrow.turn.down.right"
            }
        }

        var question: String {
            switch self {
            case .explain:
                "Explain what this is, in plain language. Define any jargon."
            case .nextStep:
                "Based on this, what is the single next thing I should do? Be specific."
            }
        }
    }

    /// What pressing a preset button should actually ask.
    ///
    /// A preset is wording for the case where the user has nothing specific to
    /// ask — "Explain" is a shortcut past typing "explain this" every time.
    /// Once they have typed or dictated a question, that *is* the question, and
    /// overwriting the field with this app's sentence threw their words away
    /// silently. Discarding the user's own words is the one thing this app must
    /// not do, and it is worse here than anywhere: dictating a sentence and
    /// watching it vanish gives no hint that a button was the cause.
    ///
    /// Pure so the decision is testable without a model container.
    nonisolated static func presetAsk(typed: String,
                                      preset: Preset) -> (question: String, isFromPreset: Bool) {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return (trimmed, false) }
        return (preset.question, true)
    }

    func ask(_ preset: Preset) {
        let asked = Self.presetAsk(typed: question, preset: preset)
        question = asked.question
        submit(isFromPreset: asked.isFromPreset)
    }

    /// Whether the preset buttons would ask the user's own words instead.
    /// The buttons say so, since otherwise both would appear to do the same
    /// thing once something has been typed.
    var presetWouldAskTypedText: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Narrows the capture to a rectangle the user drags out.
    ///
    /// The panel hides during selection so it is not in the way. It does not
    /// need to hide for correctness — the screenshot was taken before the panel
    /// appeared and excludes this app's windows regardless.
    func selectRegion(hidingPanel: @escaping (Bool) -> Void) {
        guard let current = observation else {
            phase = .failed("Nothing captured yet.")
            return
        }

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main
        else { return }

        Task {
            hidingPanel(true)
            let selection = await regionSelector.selectRegion(on: screen)
            hidingPanel(false)

            guard let selection else { return }
            guard let narrowed = current.cropped(to: selection, on: screen) else {
                phase = .failed("That selection was too small to read.")
                return
            }

            var updated = narrowed
            let read = await Self.readText(in: narrowed.primary.image)
            updated.primary.recognizedText = read.text
            updated.primary.textRegions = read.regions
            observation = updated
            pointerTarget = nil
            contextLabel = "Selected region of \(updated.contextLabel)"
            if phase == .failed("") || phase == .idle { phase = .idle }
        }
    }

    /// Returns to the whole screen after a region was selected.
    func clearRegion(frontmostApp: NSRunningApplication?) {
        captureScreen(frontmostApp: frontmostApp)
    }

    /// Dictates into the same field used for typing, so speech and text are the
    /// same input rather than two separate flows.
    func toggleDictation() {
        if isListening {
            dictation.stop()
            endListening()
            return
        }

        // Half duplex. The synthesizer plays through the speakers and the mic
        // would transcribe it, so Max would end up dictating to itself.
        speech.stop()

        // Stated before anything can go wrong, so a failure that arrives later
        // replaces a visible "starting" rather than appearing out of nowhere.
        isLoadingDictationModel = dictation.willLoadModel
        phase = .startingDictation

        Task {
            onListeningBegan?()
            do {
                try await dictation.start(
                    // The question is about the screen, so the words on it are
                    // the ones most likely to be said and least likely to be
                    // recognized. Project names come too, being the user's own
                    // coinages by definition.
                    expecting: DictationHints.from(
                        screenText: observation?.recognizedText ?? "",
                        projectNames: projects.map(\.name)
                    ),
                    onTranscript: { [weak self] text in
                        self?.question = text
                        self?.dictationHint = ""
                    },
                    onSilence: { [weak self] device in
                        self?.dictationHint =
                            "No sound from “\(device)”. Pick a different mic in System Settings → Sound → Input."
                    }
                )
                isLoadingDictationModel = false
                isListening = dictation.isListening
                dictationIsOnDevice = dictation.isOnDevice
                inputDeviceName = dictation.inputDeviceName
                if phase == .startingDictation { phase = .idle }
                if !isListening { endListening() }
            } catch {
                isLoadingDictationModel = false
                endListening()
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func endListening() {
        isListening = false
        dictationHint = ""
        onListeningEnded?()
    }

    // MARK: Proposed edits

    /// Pulls a rewrite out of the finished answer, if there is one.
    ///
    /// Nothing is written here. An identical rewrite is discarded rather than
    /// offered, because "Apply" on a diff with no changes in it is a button
    /// that does nothing and implies the model achieved something.
    private func captureProposedEdit(from reply: String) {
        guard editableFile.isOpen,
              let proposed = CodeBlock.extract(from: reply)
        else { return }

        let lines = TextDiff.compare(editableFile.contents, to: proposed)
        let summary = TextDiff.summary(of: lines)
        guard !summary.isEmpty else { return }

        proposedEdit = ProposedEdit(fileName: editableFile.name,
                                    contents: proposed,
                                    lines: lines,
                                    summary: summary)
    }

    func openFileToEdit() {
        guard editableFile.open() else { return }
        proposedEdit = nil
    }

    func closeEditableFile() {
        editableFile.close()
        proposedEdit = nil
    }

    func applyProposedEdit() {
        guard let proposedEdit else { return }

        if editableFile.apply(proposedEdit.contents) {
            self.proposedEdit = nil
            phase = .saved("Applied to \(proposedEdit.fileName)")
        } else {
            phase = .failed("Couldn't write \(proposedEdit.fileName).")
        }
    }

    func discardProposedEdit() {
        proposedEdit = nil
    }

    func revertAppliedEdit() {
        guard editableFile.revert() else {
            phase = .failed("Couldn't put \(editableFile.name) back.")
            return
        }
        phase = .saved("Reverted \(editableFile.name)")
    }

    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        if let url { NSWorkspace.shared.open(url) }
    }

    func submit() { submit(isFromPreset: false) }

    private func submit(isFromPreset: Bool) {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isBusy else { return }

        // A typed instruction to set a reminder is carried out rather than
        // asked about. Never for a preset, whose wording is this app's own and
        // could not be asking for anything.
        if !isFromPreset, isReminderInstruction {
            // Filed under the original request when this message is only the
            // answer to "when?", since "in 10 minutes" is a time and not a
            // reason anyone would want to read back later.
            saveCurrentContext(reason: pendingReminderRequest)
            pendingReminderRequest = nil
            return
        }

        if !isFromPreset {
            pendingReminderRequest = ReminderPhrase.pendingRequest(message: prompt,
                                                                   suggestion: reminderSuggestion)
        }

        answerTask?.cancel()
        speech.stop()
        proposedEdit = nil
        pointerTarget = nil
        phase = .thinking

        // The question moves into the transcript immediately so a follow-up
        // reads as a conversation rather than as the field having been cleared.
        let turnID = UUID()
        turns.append(Turn(id: turnID, question: prompt, isFromPreset: isFromPreset))
        question = ""
        refreshReminderSuggestion()

        let brain = makeBrain()
        let context = AskContext(
            observation: observation,
            memories: ContextRetriever.promptLines(for: related),
            tasks: taskLines(),
            includeImage: AppSettings.sendsImage,
            // Everything before the turn just added, so the model is not shown
            // the question it is currently answering twice.
            history: turns.dropLast(),
            editableFile: editableFile.context
        )

        answerTask = Task {
            // Accumulated locally rather than in a property: the turn is the
            // one place an answer lives, and a second copy of it that has to be
            // kept in step is the sort of thing that silently drifts.
            var streamed = ""
            do {
                let stream = brain.answerStream(question: prompt, context: context)
                for try await chunk in stream {
                    if Task.isCancelled { return }
                    streamed += chunk
                    recordAnswer(streamed, for: turnID)
                    if phase != .answering { phase = .answering }
                    speech.speakArriving(streamed)
                }
                guard !Task.isCancelled else { return }

                speech.finish(streamed)
                captureProposedEdit(from: streamed)
                findPointerTarget(in: streamed)
                lastTurnAt = Date()
                phase = .idle
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Stores what was said about the screen being saved.
    ///
    /// Preset turns are kept here even though preset wording may never become
    /// the *stated reason* — the transcript is a record of what happened, and
    /// pressing "Explain" is part of what happened. The distinction the app
    /// protects is about whose words are presented as the user's, and a
    /// transcript attributes every line to whoever said it.
    private func attachConversation(to record: SavedContext) {
        // An in-flight turn has no answer yet. Storing half an exchange would
        // read later as Max having been asked something and said nothing.
        let finished = turns.filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !finished.isEmpty else { return }

        for (order, turn) in finished.enumerated() {
            let stored = ConversationTurn(question: turn.question, answer: turn.answer, order: order)
            stored.context = record
            modelContext.insert(stored)
        }
    }

    /// The control the finished answer named, if it named one that is on screen.
    ///
    /// Resolved once the answer is complete rather than per streamed chunk: the
    /// search runs over every word Vision found, and a half-arrived sentence
    /// would match on words the answer is still in the middle of writing.
    private(set) var pointerTarget: ScreenTextLocator.Match?

    private func findPointerTarget(in answer: String) {
        guard let observation, observation.primaryScreenFrame != nil else {
            pointerTarget = nil
            return
        }
        pointerTarget = ScreenTextLocator.locate(named: answer, in: observation.primary.textRegions)
    }

    /// Draws a box around what the answer named.
    ///
    /// Deliberately a button press rather than something that happens on its
    /// own: drawing over the user's screen after every answer would be the app
    /// acting unasked, and most answers are not directions to a control.
    func showPointerTarget() {
        guard let pointerTarget,
              let frame = observation?.primaryScreenFrame
        else { return }

        onHighlight?(ScreenTextLocator.screenRect(for: pointerTarget.boundingBox, in: frame), false)
    }

    /// Moves the box to whatever control the clause now being spoken names.
    ///
    /// The one place in the app that draws on the screen without a press
    /// immediately before it, and the two conditions on it are what make that
    /// acceptable rather than a hole in the rule. It is off unless the user
    /// switched it on, and it matches with `requiringQuoted`, so the only thing
    /// it can ever box is a label Max put in double quotes — Max stating which
    /// words it meant, not this app inferring them from prose. A clause naming
    /// nothing leaves the previous box where it is rather than clearing it,
    /// since an answer is mostly sentences about the one control it named and
    /// flickering the box off for each of them would be worse than useless.
    private func followAlong(with clause: String?) {
        guard AppSettings.followsAlongWhileSpeaking else { return }

        guard let clause else {
            onHighlightEnded?()
            return
        }

        guard let observation,
              let frame = observation.primaryScreenFrame,
              let match = ScreenTextLocator.locate(named: clause,
                                                   in: observation.primary.textRegions,
                                                   requiringQuoted: true)
        else { return }

        onHighlight?(ScreenTextLocator.screenRect(for: match.boundingBox, in: frame), true)
    }

    private func recordAnswer(_ text: String, for turnID: UUID) {
        guard let index = turns.firstIndex(where: { $0.id == turnID }) else { return }
        turns[index].answer = text
    }

    /// Clears the conversation but keeps the capture, so the user can start a
    /// fresh line of questioning about the same screen.
    func startNewConversation() {
        answerTask?.cancel()
        speech.stop()
        turns = []
        lastTurnAt = nil
        proposedEdit = nil
        pointerTarget = nil
        phase = .idle
    }

    /// Grabs the screen again while keeping the conversation.
    ///
    /// The point of the whole feature: the user does what they were told, the
    /// screen changes, and they ask "now what?" without losing the thread.
    func lookAgain(frontmostApp: NSRunningApplication?) {
        speech.stop()
        captureScreen(frontmostApp: frontmostApp)
    }

    /// Persists the current screen with whatever the user typed as the reason.
    /// The typed text is the record's intent; `#tags` inside it become topics.
    /// - Parameter reason: overrides the typed field. Used when the message on
    ///   screen is the answer to Max asking when, so the save is filed under
    ///   what was asked for rather than under the time.
    func saveCurrentContext(reason: String? = nil) {
        guard let observation else {
            phase = .failed("Nothing captured yet.")
            return
        }

        guard let raw = reason ?? savableReason else {
            phase = .failed("Type why this matters, then save.")
            return
        }

        let (intent, topics) = raw.splittingHashtags()
        let record = SavedContext(
            intent: intent,
            recognizedText: observation.recognizedText,
            imageData: ImageCodec.pngData(from: observation.image),
            sourceApp: observation.appName ?? "",
            windowTitle: observation.windowTitle ?? "",
            topics: topics
        )

        let reminder = reminderIsArmed ? effectiveReminderDate : nil
        record.remindAt = reminder
        record.project = currentProject

        modelContext.insert(record)
        attachConversation(to: record)
        do {
            try modelContext.save()
        } catch {
            phase = .failed("Couldn't save: \(error.localizedDescription)")
            return
        }

        let tagSuffix = topics.isEmpty ? "" : " · \(topics.map { "#\($0)" }.joined(separator: " "))"
        let destination = currentProject.map { "Saved to \($0.name)" } ?? "Saved"
        question = ""
        phase = .saved("\(destination)\(tagSuffix)")
        addSummary(to: record)

        if let reminder {
            scheduleReminder(for: record, at: reminder, destination: destination, tagSuffix: tagSuffix)
            // Handed to Apple now rather than on the next summon: this is
            // usually said just before walking away from the Mac, which is the
            // one case where there is no next summon.
            mirrorTasksToAppleReminders()
        }
    }

    /// Copies dated tasks into Apple Reminders, so iCloud can alert the user on
    /// a device this Mac is not.
    ///
    /// Runs on summon, which is also when the task list is read: the mirror is
    /// only ever as fresh as the last time this app looked, and saying so is
    /// better than a background poll in an app whose rule is that it acts when
    /// summoned. Anything already mirrored keeps its alarm regardless, since
    /// Apple owns delivery from that point and needs nothing further from here.
    private func mirrorTasksToAppleReminders() {
        guard AppSettings.mirrorsToAppleReminders, AppleReminders.isAuthorized else { return }

        // Reminders set here stand in for themselves until the to-do app has
        // turned them into tasks. Ahead of it rather than instead of it: the
        // same id arrives from `TodoBridge` later and reconciles.
        let todos = linkedWork.todos + ProjectExport.anticipatedTasks(
            for: ProjectExport.pendingReminders(in: modelContext),
            knownTo: linkedWork.todos
        )
        let quietHours = linkedWork.quietHours

        Task {
            do {
                let armed = try await AppleReminders.sync(openTodos: todos, quietHours: quietHours)
                standDown(forMirrored: armed)
            } catch {
                // Deliberately silent. The panel was summoned to answer a
                // question, and a failure to reach a Reminders database is not
                // an answer to it. Settings is where the state of this is told.
                NSLog("[AppleReminders] mirror failed: \(error)")
            }
        }
    }

    /// Stops announcing a reminder Apple has taken on.
    ///
    /// Only for this app's own reminders, and only once they are *confirmed* in
    /// the mirror. This is not the local hand-over the plan rejected, which
    /// swapped one Mac-only notifier for another and bought nothing: Apple
    /// delivers to the phone and the watch as well, so the notification kept
    /// here would be the strictly weaker duplicate of the two, firing at the
    /// same second with the same words.
    private func standDown(forMirrored taskIDs: [String]) {
        for identifier in ProjectExport.reminderIdentifiers(inTaskIDs: taskIDs) {
            Reminders.cancel(id: identifier)
        }
    }

    /// Scheduling can fail on a permission the user has already refused, and a
    /// reminder that was silently never set is worse than one that was never
    /// offered — the whole point is that it can be relied on.
    private func scheduleReminder(for record: SavedContext,
                                  at date: Date,
                                  destination: String,
                                  tagSuffix: String) {
        let id = record.reminderIdentifier
        let intent = record.intent
        let sourceApp = record.sourceApp

        Task {
            let scheduled = await Reminders.schedule(id: id,
                                                     at: date,
                                                     intent: intent,
                                                     sourceApp: sourceApp)
            guard case .saved = phase else { return }

            if scheduled {
                phase = .saved("\(destination) · reminder \(Self.reminderFormat(date))\(tagSuffix)")
            } else {
                record.remindAt = nil
                try? modelContext.save()
                phase = .saved("Saved, but notifications are off in System Settings.")
            }
        }
    }

    /// "tomorrow at 9:00 AM" reads better than a bare timestamp for something a
    /// few hours or days out, which is what these almost always are.
    static func reminderFormat(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)

        if calendar.isDateInToday(date) { return "today at \(time)" }
        if calendar.isDateInTomorrow(date) { return "tomorrow at \(time)" }

        let days = calendar.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 7 { return "\(date.formatted(.dateTime.weekday(.wide))) at \(time)" }

        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Reminder controls.
    ///
    /// The user's typed sentence is never edited to strip the reminder
    /// phrasing: "remind me tomorrow" is part of why they saved it and stays in
    /// the record verbatim.
    private func refreshReminderSuggestion() {
        guard let raw = savableReason else {
            reminderSuggestion = nil
            reminderDate = nil
            reminderIsArmed = false
            return
        }

        // A time the user picked by hand outranks anything re-parsed from the
        // text they are still typing.
        let wasChosenByHand = reminderDate != nil && reminderDate != reminderSuggestion?.date
        let fresh = ReminderPhrase.suggestion(in: raw)

        reminderSuggestion = fresh
        guard let fresh else {
            if !wasChosenByHand {
                reminderDate = nil
                reminderIsArmed = false
            }
            return
        }

        if !wasChosenByHand {
            reminderDate = fresh.date
            // A bare time is normally inference and stays switched off. It is an
            // instruction when it is the answer to Max having asked for one.
            reminderIsArmed = fresh.wasExplicitlyRequested
                || (pendingReminderRequest != nil && fresh.matchedText != nil)
        }
    }

    func chooseReminder(_ preset: ReminderPreset) {
        guard let date = preset.date() else { return }
        reminderDate = date
        reminderIsArmed = true
    }

    /// Project controls.
    func reloadProjects() {
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.name)])
        projects = (try? modelContext.fetch(descriptor)) ?? []

        // A project deleted elsewhere should not leave a dangling selection.
        let saved = AppSettings.currentProjectID
        currentProject = projects.first { $0.identifier == saved }
        if currentProject == nil, saved != nil {
            AppSettings.currentProjectID = nil
        }
    }

    func chooseProject(_ project: Project?) {
        currentProject = project
        AppSettings.currentProjectID = project?.identifier
    }

    /// - Returns: the project now selected, existing or new.
    ///
    /// Reuses a project of the same name rather than creating a second one, so
    /// a typo-free re-entry does not split a project in two.
    @discardableResult
    func createProject(named rawName: String) -> Project? {
        let name = Project.normalize(rawName)
        guard !name.isEmpty else { return nil }

        if let existing = projects.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            chooseProject(existing)
            return existing
        }

        let project = Project(name: name)
        modelContext.insert(project)
        try? modelContext.save()
        reloadProjects()
        chooseProject(projects.first { $0.identifier == project.identifier } ?? project)
        return currentProject
    }

    /// Fills in the model's own description in the background so saving stays instant.
    private func addSummary(to record: SavedContext) {
        let brain = localBrain()
        let intent = record.intent
        let screenText = record.recognizedText

        Task {
            guard let summary = try? await brain.summarize(intent: intent, screenText: screenText),
                  !summary.isEmpty
            else {
                // Still worth a vector from the user's own words alone.
                await addEmbedding(to: record)
                return
            }
            record.aiSummary = summary
            try? modelContext.save()
            // Deliberately after the summary lands, since the summary is part
            // of what gets embedded. Embedding first would mean vectoring a
            // save without the model's description of what was on screen.
            await addEmbedding(to: record)
        }
    }

    /// Computes the vector for one save, locally.
    ///
    /// Failure is silent by design: the model may not be pulled and Ollama may
    /// not be running, and neither should turn a successful save into a visible
    /// error. The save is already on disk; the vector is an enhancement that
    /// the backfill will pick up on a later summon.
    private func addEmbedding(to record: SavedContext) async {
        guard AppSettings.semanticEnabled else { return }

        let model = AppSettings.embeddingModel
        guard record.needsEmbedding(for: Embedding.identifier(for: model)) else { return }

        let prepared = Embedding.prepared(record.embeddingSource, as: .document, for: model)
        guard let vector = try? await localBrain().embed(prepared, model: model) else {
            return
        }
        record.embeddingData = vector.data
        record.embeddingModel = Embedding.identifier(for: model)
        try? modelContext.save()
    }

    /// Vectors anything saved before the feature was switched on.
    ///
    /// Capped per summon rather than run as one long pass: this is background
    /// work triggered by the user opening a panel, and a library of hundreds
    /// would otherwise hold the local model busy for a noticeable stretch the
    /// first time. A few summons catch up instead.
    private func backfillEmbeddings() {
        guard AppSettings.semanticEnabled else { return }

        let identifier = Embedding.identifier(for: AppSettings.embeddingModel)
        let pending = recentContexts()
            .filter { $0.needsEmbedding(for: identifier) }
            .prefix(8)
        guard !pending.isEmpty else { return }

        Task {
            for record in pending {
                guard !Task.isCancelled else { return }
                await addEmbedding(to: record)
            }
        }
    }

    /// Dismisses the panel's working state but keeps the conversation.
    ///
    /// Dismissing is how the user reaches the thing they are being taught:
    /// clicking into DaVinci to do the step they were just given is, from this
    /// app's side, a click outside it. Wiping the transcript there made
    /// follow-up questions impossible in precisely the situation they exist
    /// for — the panel could only hold a conversation for as long as the user
    /// never touched the app they were asking about.
    func endSession() {
        captureTask?.cancel()
        answerTask?.cancel()
        speech.stop()
        if isListening {
            dictation.stop()
            endListening()
        }

        // A question dismissed before it was answered leaves a turn that would
        // otherwise sit in the transcript showing an ellipsis forever, and go
        // back to the model as something it failed to answer.
        if turns.last?.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            turns.removeLast()
        }
        lastTurnAt = turns.isEmpty ? nil : Date()

        question = ""
        proposedEdit = nil
        pointerTarget = nil
        // The opened file deliberately survives, because dismissing the panel
        // between questions about the same file is the normal way to use this
        // and re-picking it every time through a modal would be absurd.
        observation = nil
        related = []
        phase = .idle
        contextLabel = "Nothing captured yet"
        reminderSuggestion = nil
        reminderDate = nil
        reminderIsArmed = false
        pendingReminderRequest = nil
    }

    /// How long a dismissed conversation stays resumable.
    ///
    /// Long enough to go and do the step you were just told to do, short enough
    /// that a summon after lunch is not answered against this morning's
    /// subject. Time rather than app identity, because the screen legitimately
    /// changes between turns — that is the whole point — so "different app"
    /// would end the conversation exactly when it was working.
    /// `nonisolated` so the pure check below can use it as a default argument;
    /// the class is `@MainActor`, which would otherwise isolate it.
    nonisolated static let conversationResumeWindow: TimeInterval = 5 * 60

    /// When the last answer landed, or nil when there is nothing to resume.
    private var lastTurnAt: Date?

    nonisolated static func conversationSurvives(lastTurnAt: Date?,
                                                 now: Date = Date(),
                                                 window: TimeInterval = conversationResumeWindow) -> Bool {
        guard let lastTurnAt else { return false }
        return now.timeIntervalSince(lastTurnAt) <= window
    }

    /// Decides, on each summon, whether the kept conversation is still live.
    func prepareForSummon(now: Date = Date()) {
        guard !Self.conversationSurvives(lastTurnAt: lastTurnAt, now: now) else { return }

        turns = []
        lastTurnAt = nil
    }

    /// Falls back to the local model when OpenAI is selected without a key, so
    /// a missing secret degrades to a worse answer rather than an error. The
    /// badge says so — see `AnswerDestination.cloudWithoutKey` — because a
    /// silent downgrade is indistinguishable from the switch not working.
    private func makeBrain() -> any Brain {
        if AppSettings.provider == .openAI, let key = AppSettings.openAIKey {
            return OpenAIBrain(apiKey: key, model: AppSettings.openAIModel)
        }
        return localBrain()
    }

    /// Background work is always local. See the note on `Brain`.
    private func localBrain() -> OllamaBrain {
        OllamaBrain(endpoint: AppSettings.endpoint, model: AppSettings.model)
    }

    /// A compact view of what the user still has to do, so questions like
    /// "what should I work on" have something real to answer from.
    private func taskLines() -> [String] {
        // A chosen project narrows this to its own tasks. Answering "what next"
        // with everything on the list would bury the work the user just said
        // they were doing.
        let candidates: [LinkedTodo]
        if let currentProject, !currentProject.linkedTodoIDs.isEmpty {
            let scoped = linkedWork.todos(withIDs: currentProject.linkedTodoIDs).filter { !$0.isDone }
            candidates = scoped.isEmpty ? linkedWork.openTodos : scoped
        } else {
            candidates = linkedWork.openTodos
        }

        let open = candidates.sorted { lhs, rhs in
            switch (lhs.dueAt, rhs.dueAt) {
            case let (left?, right?): return left < right
            case (nil, _?): return false
            case (_?, nil): return true
            default: return false
            }
        }

        return open.prefix(12).map { todo in
            guard let due = todo.dueAt else { return "- \(todo.title)" }
            let when = due.formatted(.relative(presentation: .named))
            return todo.isOverdue ? "- \(todo.title) (overdue, was due \(when))" : "- \(todo.title) (due \(when))"
        }
    }

    /// Scoring runs in memory, so cap the candidate set rather than growing
    /// the work forever as the store fills up.
    private func recentContexts() -> [SavedContext] {
        var descriptor = FetchDescriptor<SavedContext>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 300
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
