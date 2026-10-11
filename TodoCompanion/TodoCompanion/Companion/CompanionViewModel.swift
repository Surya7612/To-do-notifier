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
    /// Starts or stops the click-outside monitor behind the pin.
    var onPinnedChanged: ((Bool) -> Void)?
    /// Hides the panel for a capture so ScreenCaptureKit does not punch a black
    /// hole where Max was sitting — that hole is exactly the editor Teach and
    /// Guided need OCR to read.
    var onPanelOcclusion: ((Bool) -> Void)?

    /// Whether clicking into another app leaves the panel where it is.
    ///
    /// Not persisted. A pinned panel that survives a relaunch is a window the
    /// user has to remember they pinned, and the default — dismissing the way
    /// every other floating panel on the system does — is the one that cannot
    /// strand anybody.
    var isPinned = false {
        didSet {
            guard isPinned != oldValue else { return }
            // Manual pin/unpin takes ownership. Otherwise Done would unpin a pin
            // the user re-asserted after auto-pin (or after unpinning mid-lesson).
            pinnedForLesson = false
            onPinnedChanged?(isPinned)
        }
    }

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

    var phase: Phase = .idle {
        didSet {
            guard case .saved = phase, phase != oldValue else { return }
            // A confirmation, not a state: left in place it read as the panel
            // still being busy, and `offersKeepThis` waits for `.idle`.
            let shown = phase
            savedPhaseClear?.cancel()
            savedPhaseClear = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.savedConfirmationSeconds))
                guard !Task.isCancelled, let self, self.phase == shown else { return }
                self.phase = .idle
            }
        }
    }
    private var savedPhaseClear: Task<Void, Never>?
    private static let savedConfirmationSeconds = 3.5
    var contextLabel: String = "Nothing captured yet"

    /// Soft 0…1 fill while the model streams. The panel shows this bar instead
    /// of half-written text; speech and the board wait for 1.
    private(set) var answerLoadProgress: Double = 0
    /// True while the reply is held back for a Teach or board walk; the panel
    /// shows the progress bar instead of the half-written text.
    private(set) var isHoldingAnswer = false
    /// Set once the model has been silent long enough to need explaining.
    private var modelLoadHint: String?

    /// Shown while Teach re-asks for a missing storyboard, or if repair failed.
    private(set) var sketchRepairHint: String?

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

    /// Offer Keep this after a finished answer so ⌘S is not the only path.
    var offersKeepThis: Bool {
        canSave
            && phase == .idle
            && !(turns.last?.answer.isEmpty ?? true)
            && lesson == nil
    }

    /// One-shot tip when a visual question is about to be answered without sight.
    private(set) var visionNudge: String?

    /// Shown under Thinking… when an enabled MCP server fails to answer.
    private var mcpStatusHint: String?

    /// Cold-start readiness: nil until probed, then whether Ollama answered.
    private(set) var ollamaReachable: Bool?
    /// The chat model Ollama reported it does not have, from the summon warm-up.
    private(set) var missingOllamaModel: String?

    /// Auto-pinned for the active lesson so working underneath does not dismiss.
    private var pinnedForLesson = false

    /// User pressed Done (or otherwise ended the lesson) while this answer is
    /// still streaming. Without this, the next chunk calls `beginLesson` again
    /// and brings boxes, pin, and board back.
    private var lessonSuppressedForAnswer = false

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
    /// Accessibility-tree text for the focused app, when extras are trusted.
    private(set) var pageStructure: String?

    /// Clipboard string offered as an ask chip when the field is empty.
    private(set) var clipboardOffer: String?

    /// Diff vs the last keep of this window, shown after a successful save.
    private(set) var lastSaveChangeLine: String?

    /// How the next answer will be grounded — OCR text vs actual screenshot.
    var answerGrounding: AnswerGrounding.Mode {
        AnswerGrounding.mode(hasCapture: hasCapture, sendsImage: AppSettings.sendsImage)
    }

    var answerGroundingLabel: String? {
        AnswerGrounding.badgeLabel(for: answerGrounding)
    }

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
    private(set) var hasCloudKey = AppSettings.hasKeyForSelectedProvider

    func refreshCloudKey() {
        hasCloudKey = AppSettings.hasKeyForSelectedProvider
    }

    /// Who will answer, as the panel states it. Derived from the same two facts
    /// `makeBrain()` uses, so the badge cannot claim one thing while a different
    /// model answers.
    var destination: AppSettings.AnswerDestination {
        AppSettings.AnswerDestination.resolve(provider: AppSettings.provider,
                                              hasCloudKey: hasCloudKey,
                                              cloudModel: AppSettings.cloudModel)
    }

    var localModelName: String { AppSettings.model }

    private let modelContext: ModelContext
    private var observation: ScreenObservation?
    private var captureTask: Task<Void, Never>?
    private var regionTask: Task<Void, Never>?
    private var answerTask: Task<Void, Never>?
    private var warpTask: Task<Void, Never>?
    private var warpGeneration = UUID()
    /// Identifies the in-flight grab so a cancelled predecessor cannot clear
    /// `.reading` or re-show the panel while a newer capture still owns them.
    private var captureGeneration = UUID()
    private var panelOcclusionOwner: UUID?
    private var dictationStartInFlight = false
    /// The answer currently allowed to write panel state; see `submit`.
    private var answerGeneration = UUID()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        reloadProjects()
        speech.onSpeakingClause = { [weak self] clause in self?.followAlong(with: clause) }
    }

    var isBusy: Bool {
        // `.reading` counts: Show me / Look again / Teach re-grabs must not
        // overlap a Return that starts a new answer on a half-written observation.
        phase == .thinking || phase == .answering || phase == .reading
    }
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

        if let visionNudge, phase == .idle { return visionNudge }

        switch phase {
        case .idle:
            if let blocker = readinessBlocker { return blocker }
            // Name the summon shortcut when nothing is captured yet — USABILITY §4
            // asks for Screen Recording, Ollama, *or* the hotkey, and the first two
            // only appear as blockers. Without this the idle panel looks inert.
            if observation == nil {
                return "Press \(AppSettings.hotkey.displayName) to capture, then ask"
            }
            return contextLabel
        case .reading: return "Reading your screen…"
        case .startingDictation:
            // Loading Parakeet onto the Neural Engine takes tens of seconds the
            // first time in a session, and an unexplained wait on a key press
            // reads as the key having been ignored.
            return isLoadingDictationModel
                ? "Loading the Parakeet model — first time only…"
                : "Turning the microphone on…"
        case .thinking:
            if let sketchRepairHint { return sketchRepairHint }
            if let modelLoadHint { return modelLoadHint }
            if let mcpStatusHint { return "Planning… · \(mcpStatusHint)" }
            if speech.speaksRegardlessOfSetting || AppSettings.sessionMode.prefersTeaching {
                return "Planning the lesson…"
            }
            return "Thinking…"
        case .answering:
            if let sketchRepairHint { return sketchRepairHint }
            if lesson != nil { return "Teaching — step \(lessonStep + 1)" }
            if speech.speaksRegardlessOfSetting || AppSettings.sessionMode.prefersTeaching {
                return "Writing the walkthrough…"
            }
            return "Answering…"
        case let .saved(message): return message
        case .needsPermission: return "Screen Recording permission needed"
        case let .failed(message): return message
        }
    }

    /// Names the one thing stopping a first ask, when there is one.
    private var readinessBlocker: String? {
        if !ScreenCapture.hasPermission {
            return "Screen Recording permission needed — open Settings from the panel"
        }
        if AppSettings.provider == .ollama, ollamaReachable == false {
            return "Ollama isn’t running — start it, then ask again"
        }
        if AppSettings.provider == .ollama, let missingOllamaModel {
            return "Ollama has no \(missingOllamaModel) — run ollama pull \(missingOllamaModel)"
        }
        return nil
    }

    /// Probes Ollama so the status line can name a blocker before the first ask
    /// (docs/USABILITY.md §4). Does not set `phase` — a false preflight flicker
    /// must not yank the panel into the permission sheet while capture would
    /// still succeed; `performCapture` owns that transition on a real denial.
    func refreshReadiness() {
        guard AppSettings.provider == .ollama else {
            ollamaReachable = nil
            missingOllamaModel = nil
            return
        }
        let endpoint = AppSettings.endpoint
        let model = AppSettings.model
        Task { [weak self] in
            let ok = await OllamaBrain.isReachable(endpoint: endpoint)
            guard let self else { return }
            self.ollamaReachable = ok
            guard ok else { return }
            // Loading starts at the summon rather than at the question, so the
            // seconds spent reading the screen and typing pay for it.
            let warm = await OllamaBrain.warm(endpoint: endpoint, model: model)
            self.missingOllamaModel = warm == .modelMissing ? model : nil
        }
    }

    /// Who to attribute a capture to, and whose app Guided / Show me activate.
    ///
    /// Set by the panel controller. Max is usually frontmost when a button is
    /// pressed, so `NSWorkspace.frontmostApplication` alone would teach Max's
    /// own windows and warp into the wrong process.
    var resolveContextApp: (() -> NSRunningApplication?)?

    /// When the last grab finished — used to skip a redundant re-capture when
    /// Explain is pressed a moment after summon.
    private var lastCaptureAt: Date?
    /// Quality of the OCR currently on `observation` — Teach upgrades fast
    /// summon OCR without a second ScreenCaptureKit grab when the pixels are fresh.
    private var lastOCRQuality: TextRecognizer.Quality = .fast

    /// Snapshots the screen behind the companion. Called as the panel appears so
    /// an answer can start the moment the user hits return.
    func captureScreen(frontmostApp: NSRunningApplication?) {
        // Never clobber an in-flight answer — swapping `observation` and forcing
        // `.idle` while `answerTask` still streams leaves submits unlocked and
        // pointer/lesson marks on the wrong screen.
        guard phase != .thinking, phase != .answering else { return }
        refreshReadiness()
        captureTask?.cancel()
        captureTask = Task {
            _ = await performCapture(frontmostApp: frontmostApp,
                                     preserveCropFrame: nil,
                                     ocrQuality: .fast)
        }
    }

    /// Re-reads every display, OCR and related strip.
    ///
    /// - Parameter preserveCropFrame: when the user had narrowed to a region,
    ///   re-apply that rectangle after the fresh grab so Teach / Guided stay on
    ///   the selection rather than silently widening to the whole display.
    /// - Parameter ocrQuality: `.fast` on summon; `.accurate` when Teach needs
    ///   boxes that match quoted labels.
    @discardableResult
    private func performCapture(frontmostApp: NSRunningApplication?,
                                preserveCropFrame: CGRect?,
                                preserveTeaching: Bool = false,
                                ocrQuality: TextRecognizer.Quality = .accurate) async -> Bool {
        // Snapshot before flipping to `.reading` — Look again mid-answer must
        // still suppress lesson restart on later stream chunks.
        let answerWasInFlight = phase == .thinking || phase == .answering
        let myGeneration = UUID()
        captureGeneration = myGeneration
        phase = .reading
        pointerTarget = nil
        if let frontmostApp,
           frontmostApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            contextApp = frontmostApp
        }
        if !preserveTeaching {
            if answerWasInFlight {
                lessonSuppressedForAnswer = true
            }
            endLesson()
        }
        onCaptureBegan?()
        refreshCloudKey()

        defer { onCaptureEnded?() }

        // Started alongside the grab rather than after OCR, so the tree walk
        // costs nothing beyond the capture it runs in parallel with.
        let pageStructureRead: Task<String?, Never>? = TrustAccessibility.extrasAreActive
            ? Task.detached(priority: .userInitiated) { AXPageReader.snapshot() }
            : nil
        defer { pageStructureRead?.cancel() }

        do {
            var fresh = try await ScreenCapture.captureAllDisplays(frontmostApp: frontmostApp)
            guard stillCurrentCapture(myGeneration) else { return false }

            let vocab = ocrQuality == .accurate ? ocrVocabulary() : []

            // With a preserved region, OCR only that crop — full-display Vision
            // on every monitor then a second pass on the crop was the main
            // Teach / Look again delay on multi-monitor setups.
            if let crop = preserveCropFrame {
                let screen = NSScreen.screens.first(where: { NSMouseInRect(crop.origin, $0.frame, false) })
                    ?? NSScreen.screens.first(where: { $0.frame.intersects(crop) })
                    ?? NSScreen.main
                if let screen, let narrowed = fresh.cropped(to: crop, on: screen) {
                    var cropped = narrowed
                    let cropRead = await Self.readText(in: cropped.primary.image,
                                                       customWords: vocab,
                                                       quality: ocrQuality)
                    guard stillCurrentCapture(myGeneration) else { return false }
                    cropped.primary.recognizedText = cropRead.text
                    cropped.primary.textRegions = cropRead.regions
                    fresh = cropped
                } else {
                    await applyOCR(to: &fresh, customWords: vocab, quality: ocrQuality)
                    guard stillCurrentCapture(myGeneration) else { return false }
                }
            } else {
                await applyOCR(to: &fresh, customWords: vocab, quality: ocrQuality)
                guard stillCurrentCapture(myGeneration) else { return false }
            }

            observation = fresh
            contextLabel = fresh.contextLabel
            lastCaptureAt = Date()
            lastOCRQuality = ocrQuality
            // Structure text is free once Accessibility is on — browsers and
            // docs especially — and is labelled separately from OCR in the prompt.
            pageStructure = await pageStructureRead?.value
            guard stillCurrentCapture(myGeneration) else { return false }
            reloadProjects()
            related = ContextRetriever.related(to: fresh,
                                               among: recentContexts(),
                                               inProject: currentProject)
            linkedWork = TodoBridge.load()
            refreshClipboardOffer()
            if stillCurrentCapture(myGeneration), phase == .reading { phase = .idle }

            // Inbox, Reminders, embeddings, and meaning matches must not hold
            // the "Reading your screen…" state — that was the bulk of the
            // summon delay after OCR had already finished.
            let captured = fresh
            Task { @MainActor [weak self] in
                guard let self else { return }
                InboxImporter.importAll(into: self.modelContext)
                self.mirrorTasksToAppleReminders()
                self.backfillEmbeddings()
                await self.addMeaningMatches(for: captured)
            }
            return true
        } catch ScreenCaptureError.permissionDenied {
            guard stillCurrentCapture(myGeneration) else { return false }
            phase = .needsPermission
            return false
        } catch {
            guard stillCurrentCapture(myGeneration) else { return false }
            phase = .failed(error.localizedDescription)
            return false
        }
    }

    /// Whether this grab still owns the panel's capture state.
    private func stillCurrentCapture(_ generation: UUID) -> Bool {
        if Task.isCancelled || captureGeneration != generation {
            // Only the owner clears `.reading` — a superseded task used to flip
            // the replacement back to idle mid-OCR and unlock Return too early.
            return false
        }
        return true
    }

    /// OCR every display in parallel. Serial Vision was ~N× summon latency.
    private func applyOCR(to observation: inout ScreenObservation,
                          customWords: [String],
                          quality: TextRecognizer.Quality) async {
        let primaryImage = observation.primary.image
        let otherImages = observation.others.map(\.image)

        async let primaryRead = Self.readText(in: primaryImage,
                                              customWords: customWords,
                                              quality: quality)
        // Accurate secondary-monitor OCR on every summon was a major delay and
        // rarely needed for the first ask — fast there, accurate when Teach
        // re-reads for pointing.
        let secondaryQuality: TextRecognizer.Quality = quality == .accurate ? .fast : .fast
        let otherReads: [RecognizedScreen] = await withTaskGroup(of: (Int, RecognizedScreen).self) { group in
            for (index, image) in otherImages.enumerated() {
                group.addTask {
                    (index, await Self.readText(in: image,
                                                customWords: [],
                                                quality: secondaryQuality))
                }
            }
            var byIndex: [Int: RecognizedScreen] = [:]
            for await (index, read) in group { byIndex[index] = read }
            return otherImages.indices.map { byIndex[$0] ?? RecognizedScreen() }
        }

        let primary = await primaryRead
        observation.primary.recognizedText = primary.text
        observation.primary.textRegions = primary.regions
        for index in observation.others.indices {
            observation.others[index].recognizedText = otherReads[index].text
            observation.others[index].textRegions = otherReads[index].regions
        }
    }

    /// Hides the panel for a grab; only the owning generation may show it again.
    private func beginPanelOcclusion(for generation: UUID) {
        panelOcclusionOwner = generation
        onPanelOcclusion?(true)
    }

    private func endPanelOcclusion(for generation: UUID) {
        guard panelOcclusionOwner == generation else { return }
        panelOcclusionOwner = nil
        onPanelOcclusion?(false)
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
    private static func readText(in image: CGImage,
                                 customWords: [String] = [],
                                 quality: TextRecognizer.Quality = .accurate) async -> RecognizedScreen {
        await Task.detached {
            TextRecognizer.recognize(in: image, customWords: customWords, quality: quality)
        }.value
    }

    /// Project names and distinctive words from the *previous* primary display,
    /// fed to Vision as `customWords`. Secondary-display OCR is deliberately
    /// omitted — dumping every monitor into Vision's bias list slowed summon
    /// without helping Teach on the focused screen.
    private func ocrVocabulary() -> [String] {
        let names = projects.map(\.name)
        let prior = observation?.primary.recognizedText ?? ""
        return DictationHints.from(screenText: prior, projectNames: names)
    }

    /// Retries after the user grants permission, so they don't have to guess
    /// whether it took effect.
    func retryCapture(frontmostApp: NSRunningApplication?) {
        captureScreen(frontmostApp: frontmostApp)
    }

    /// Presets shown on the action row. Guided is a Teach option (Guide cursor),
    /// not a third button. "Next step" was dropped from the row — it earned the
    /// least and crowded Explain / Teach into truncated labels.
    static var primaryPresets: [Preset] { [.explain, .teach] }

    /// Ready-made questions for the two things worth asking about a region.
    /// Typing "explain this" every time is friction on the most common action.
    ///
    /// `nonisolated` because it is pure data read from `presetAsk`, which is
    /// itself nonisolated so the choice can be tested without a container.
    nonisolated enum Preset: String, CaseIterable, Identifiable {
        case explain
        case nextStep
        case teach
        case guidedTeach

        var id: String { rawValue }

        /// Whether the answer should be a walk through the screen rather than
        /// a reply. Only the teach presets change the prompt, and only pressing
        /// them turns the lesson machinery on — asking the same thing in words
        /// does not, because a lesson draws on the screen and that stays behind
        /// a press.
        var isTeaching: Bool { self == .teach || self == .guidedTeach }

        /// Guided Teach also warps the cursor to each step's box as Max speaks.
        /// Plain Teach me only draws boxes. The user pressed Guided, so moving
        /// the pointer is asked for — same footing as follow-along for drawing.
        var isGuidedTeaching: Bool { self == .guidedTeach }

        /// Kept short deliberately. These sit in a row with the region controls
        /// inside a narrow panel, and the full question does not fit.
        var buttonLabel: String {
            switch self {
            case .explain: "Explain"
            case .nextStep: "Next step"
            case .teach: "Teach me"
            case .guidedTeach: "Guided"
            }
        }

        var glyph: String {
            switch self {
            case .explain: "text.book.closed"
            case .nextStep: "arrow.turn.down.right"
            case .teach: "graduationcap"
            case .guidedTeach: "cursorarrow.click.2"
            }
        }

        var question: String {
            switch self {
            case .explain:
                "Explain what this is, in plain language. Define any jargon."
            case .nextStep:
                "Based on this, what is the single next thing I should do? Be specific."
            case .teach, .guidedTeach:
                "Walk me through what is on screen, step by step, so I understand it."
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
        // Finish the mic first so a dictated sentence is actually in `question`
        // when we read it — otherwise Teach raced the last transcript update
        // and fell back to "walk the whole screen".
        settleDictation()
        let asked = Self.presetAsk(typed: question, preset: preset)
        question = asked.question
        guard !isBusy, hasCapture else { return }

        let contextApp = resolveContextApp?() ?? contextApp
        // Region applies to every preset, not only a full-screen Teach grab.
        let crop = observation?.isCropped == true ? observation?.primaryScreenFrame : nil
        let teaching = preset.isTeaching
        if teaching {
            // Teach me is the full teacher: boxes, spoken steps, and cursor
            // follow. Without Accessibility trust the cursor silently never
            // moves — ask for the grant at the press, open Settings after the
            // grab so the list is not buried under the occlusion.
            prepareTeachingPointerAccess(openSettingsIfNeeded: false)
        }

        // Board only when it helps: Explain may diagram; Teach only when the
        // ask is about a concept that needs a sketch. Always-on boards stole
        // the model's attention from quoting the screen, so boxes and cursor
        // follow died the moment a diagram appeared.
        let wantsBoard = preset == .explain
            || (teaching && Self.asksForDiagram(asked.question))

        // Reuse a fresh grab. Teach upgrades summon's fast OCR in place when
        // the pixels are still current — a second ScreenCaptureKit pass was
        // most of the "Teach feels slow" tax after a hotkey summon.
        let captureIsFresh = lastCaptureAt.map { Date().timeIntervalSince($0) < 2.5 } ?? false
        let canReuseAccurate = captureIsFresh && lastOCRQuality == .accurate
        let canUpgradeOCROnly = teaching && captureIsFresh && lastOCRQuality == .fast
            && observation != nil

        if canReuseAccurate || (!teaching && captureIsFresh) {
            if teaching { offerAccessibilityGrantOnce() }
            submit(prompt: asked.question,
                   isFromPreset: asked.isFromPreset,
                   isTeaching: teaching,
                   isGuidedTeaching: teaching,
                   wantsBoard: wantsBoard)
            return
        }

        let occlusionID = UUID()
        captureTask?.cancel()
        captureTask = Task {
            if canUpgradeOCROnly {
                let ok = await upgradeOCRInPlace(quality: .accurate)
                guard ok, !Task.isCancelled else { return }
            } else {
                // Panel must not be on screen during this grab. Excluding our
                // windows from ScreenCaptureKit leaves an opaque void where they
                // were, so OCR of the editor under Max comes back empty.
                beginPanelOcclusion(for: occlusionID)
                defer { endPanelOcclusion(for: occlusionID) }
                let ok = await performCapture(frontmostApp: contextApp,
                                              preserveCropFrame: crop,
                                              ocrQuality: .accurate)
                guard ok, !Task.isCancelled else { return }
            }
            if teaching { offerAccessibilityGrantOnce() }
            submit(prompt: asked.question,
                   isFromPreset: asked.isFromPreset,
                   isTeaching: teaching,
                   isGuidedTeaching: teaching,
                   wantsBoard: wantsBoard)
        }
    }

    /// Re-runs Vision on the pixels already held — no new ScreenCaptureKit grab.
    @discardableResult
    private func upgradeOCRInPlace(quality: TextRecognizer.Quality) async -> Bool {
        guard var fresh = observation else { return false }
        let myGeneration = UUID()
        captureGeneration = myGeneration
        phase = .reading
        let vocab = quality == .accurate ? ocrVocabulary() : []
        await applyOCR(to: &fresh, customWords: vocab, quality: quality)
        guard stillCurrentCapture(myGeneration) else { return false }
        observation = fresh
        lastOCRQuality = quality
        lastCaptureAt = Date()
        if phase == .reading { phase = .idle }
        return true
    }

    /// Whether the user's words are asking for a concept sketch, not only a
    /// walk of what's printed.
    nonisolated static func asksForDiagram(_ text: String) -> Bool {
        let lower = text.lowercased()
        let cues = ["diagram", "draw", "sketch", "illustrate", "visuali", "picture of",
                    "data flow", "call graph", "tree of", "flowchart", "flow chart",
                    "whiteboard", "storyboard"]
        if cues.contains(where: { lower.contains($0) }) { return true }
        return lower.contains("show me how")
            && (lower.contains("works") || lower.contains("flow"))
    }

    /// Free-typed asks that must take the Teach + board path, not Ask.
    ///
    /// "draw and explain… give me the code" was landing as a solution dump with
    /// no pen — hard-board and sketch playback only arm when `isTeaching`.
    nonisolated static func asksForSketchLesson(_ text: String) -> Bool {
        if asksForDiagram(text) { return true }
        let lower = text.lowercased()
        let cues = [
            "teach me", "teach this", "walk me through", "walk through",
            "explain how to", "explain me how", "how to solve",
            "step by step", "step-by-step", "tutor me",
        ]
        return cues.contains(where: { lower.contains($0) })
    }

    /// Stops the mic and keeps whatever transcript has already landed in the field.
    private func settleDictation() {
        guard isListening || dictationStartInFlight else { return }
        dictationStartInFlight = false
        dictation.stop()
        endListening()
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
        guard !isBusy else { return }
        guard let current = observation else {
            phase = .failed("Nothing captured yet.")
            return
        }

        // Prefer the captured display's screen so the overlay and the crop share
        // a coordinate space. Falling back to the mouse screen still works when
        // the selection is on a secondary that `cropped(to:on:)` can promote.
        let preferredFrame = current.primaryScreenFrame
        let screen = preferredFrame.flatMap { frame in
            NSScreen.screens.first { $0.frame.intersects(frame) }
        }
            ?? NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        guard let screen else { return }

        let sessionGeneration = captureGeneration
        regionTask?.cancel()
        regionTask = Task {
            hidingPanel(true)
            let selection = await regionSelector.selectRegion(on: screen)
            hidingPanel(false)

            guard !Task.isCancelled, captureGeneration == sessionGeneration else { return }
            guard let selection else { return }
            guard let narrowed = current.cropped(to: selection, on: screen) else {
                phase = .failed("That selection was too small to read.")
                return
            }

            var updated = narrowed
            let read = await Self.readText(in: narrowed.primary.image)
            guard !Task.isCancelled, captureGeneration == sessionGeneration else { return }
            updated.primary.recognizedText = read.text
            updated.primary.textRegions = read.regions
            observation = updated
            lastCaptureAt = Date()
            lastOCRQuality = .accurate
            pointerTarget = nil
            contextLabel = "Selected region of \(updated.contextLabel)"
            if phase == .idle || phase == .failed("") { phase = .idle }
        }
    }

    /// Returns to the whole screen after a region was selected.
    func clearRegion(frontmostApp: NSRunningApplication?) {
        guard !isBusy else { return }
        captureScreen(frontmostApp: frontmostApp)
    }

    /// Dictates into the same field used for typing, so speech and text are the
    /// same input rather than two separate flows.
    func toggleDictation() {
        if isListening || dictationStartInFlight {
            dictationStartInFlight = false
            dictation.stop()
            endListening()
            return
        }

        // Half duplex. The synthesizer plays through the speakers and the mic
        // would transcribe it, so Max would end up dictating to itself.
        speech.stop()

        // Stated before anything can go wrong, so a failure that arrives later
        // replaces a visible "starting" rather than appearing out of nowhere.
        // `dictationStartInFlight` blocks a second talk-hotkey press from
        // starting another engine while `prepare()` is still awaiting.
        dictationStartInFlight = true
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
                        // Apple may fall back from on-device mid-session when
                        // the model is missing; keep the status line honest.
                        if let self {
                            self.dictationIsOnDevice = self.dictation.isOnDevice
                        }
                    },
                    onSilence: { [weak self] device in
                        self?.dictationHint =
                            "No sound from “\(device)”. Pick a different mic in System Settings → Sound → Input."
                    }
                )
                dictationStartInFlight = false
                isLoadingDictationModel = false
                isListening = dictation.isListening
                dictationIsOnDevice = dictation.isOnDevice
                inputDeviceName = dictation.inputDeviceName
                if phase == .startingDictation { phase = .idle }
                if !isListening { endListening() }
            } catch {
                dictationStartInFlight = false
                isLoadingDictationModel = false
                endListening()
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func endListening() {
        dictationStartInFlight = false
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

    func submit() {
        settleDictation()
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty Return in Prep / Teach is a stance shortcut, not a no-op —
        // Prep drafts a standup from keeps and tasks; Teach starts a walk.
        // Non-empty Teach also goes through `ask(.teach)` so typed Return gets
        // the same accurate OCR re-capture as the Teach me button — session
        // mode used to stream against summon's fast OCR and point wrongly.
        if trimmed.isEmpty {
            switch AppSettings.sessionMode {
            case .prep:
                askStandupPrep()
            case .teach:
                ask(.teach)
            case .ask, .debug:
                break
            }
            return
        }
        // "draw and explain…" is Teach, even in Ask mode — otherwise the user
        // gets a code dump and never arms the pen / storyboard path.
        if AppSettings.sessionMode == .teach || Self.asksForSketchLesson(trimmed) {
            ask(.teach)
            return
        }
        submit(prompt: nil,
               isFromPreset: false,
               isTeaching: false,
               isGuidedTeaching: false,
               wantsBoard: false)
    }

    private func submit(prompt promptOverride: String? = nil,
                        isFromPreset: Bool,
                        isTeaching: Bool,
                        isGuidedTeaching: Bool = false,
                        wantsBoard: Bool = false) {
        if promptOverride == nil { settleDictation() }
        let prompt = (promptOverride ?? question)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

        // A follow-up typed while a lesson is open continues the teach
        // conversation — ending the lesson here tore the boxes down the moment
        // someone asked "why that line?", which is exactly when they need them.
        let mode = AppSettings.sessionMode
        let continueTeaching = lesson != nil && !isTeaching && !isFromPreset
        // Session mode Teach makes Return start a lesson walk without needing
        // the Teach me button — same machinery, one less press.
        let teach = isTeaching
            || continueTeaching
            || (mode.prefersTeaching && !isFromPreset)
        let guide = isGuidedTeaching
            || (continueTeaching && AppSettings.guideCursorWhileTeaching)
            || (teach && AppSettings.guideCursorWhileTeaching)

        answerTask?.cancel()
        speech.stop()
        teachingPlayback?.cancel()
        teachingPlayback = nil
        proposedEdit = nil
        pointerTarget = nil
        visionNudge = nil
        lessonSuppressedForAnswer = false
        if continueTeaching {
            // Drop the prior step index so the follow-up lesson starts at 1,
            // but leave the overlay up until the new walk draws — tearing it
            // down mid-question made follow-ups feel like the teach mode died.
            lesson = nil
            lessonStep = 0
            lessonMarks = []
            lastGuidedWarpStep = nil
            onHighlightEnded?()
        } else {
            endLesson()
        }
        phase = .thinking
        answerLoadProgress = 0.02
        sketchRepairHint = nil

        // The question moves into the transcript immediately so a follow-up
        // reads as a conversation rather than as the field having been cleared.
        let turnID = UUID()
        turns.append(Turn(id: turnID, question: prompt, isFromPreset: isFromPreset))
        question = ""
        refreshReminderSuggestion()

        let brain = makeBrain()
        let includeImage = AppSettings.sendsImage
        // Bare Teach preset → whole-screen walk. Anything the user typed or
        // dictated (including a follow-up) is the focus the lesson must serve.
        let focus: String? = (teach && !isFromPreset) ? prompt : nil
        let screenText = observation?.recognizedText ?? ""
        let problem = ProblemTutor.inferred(from: screenText)
        let boardWanted = wantsBoard || teach
            || (mode.prefersBoard && Self.asksForDiagram(prompt))
            || (problem == .codingProblem && teach)

        // Teach forces speech for this answer so steps advance with the voice
        // and the cursor can follow — a silent lesson is boxes with no teacher.
        // Arrows on the lesson bar still work if speech fails. Explain boards
        // also speak so multi-frame diagrams can step with the voice.
        speech.speaksRegardlessOfSetting = teach || boardWanted
        followAlongThisAnswer = teach
        guidedTeachThisAnswer = guide
        // Clear any prior board *before* arming this answer's flag — `endBoard`
        // zeroes `wantsBoardThisAnswer`, so setting the flag first left every
        // Explain/Teach stream unable to open a board.
        endBoard()
        wantsBoardThisAnswer = boardWanted

        if Self.looksLikeVisualQuestion(prompt),
           !includeImage || !brain.leavesTheMachine {
            visionNudge = "Diagrams need a cloud model with “Send the screenshot” on — switch from the badge"
        }

        let historySnapshot = Array(turns.dropLast())
        let memoriesSnapshot = ContextRetriever.promptLines(for: related)
        let tasksSnapshot = taskLines()
        let pageSnapshot = pageStructure
        let observationSnapshot = observation
        let fileSnapshot = editableFile.context
        let mcpOn = AppSettings.mcpEnabled
        let mcpLaunch = AppSettings.mcpLaunchTokens
        mcpStatusHint = nil

        let generation = UUID()
        answerGeneration = generation
        answerTask = Task {
            // Every await below is a point where the panel may have been
            // dismissed or a newer question asked. A superseded answer must not
            // write phase, open the board, or start speaking afterwards.
            @MainActor func superseded() -> Bool {
                Task.isCancelled || self.answerGeneration != generation
            }
            @MainActor func abandon() {
                guard self.answerGeneration == generation else { return }
                self.clearTeachingSpeechOverride()
                self.answerLoadProgress = 0
                self.sketchRepairHint = nil
                if self.phase == .thinking || self.phase == .answering { self.phase = .idle }
            }

            var toolNotes: [String] = []
            if mcpOn {
                let enrichment = await MCPClient.enrich(question: prompt,
                                                        launch: mcpLaunch,
                                                        enabled: true)
                guard !superseded() else { abandon(); return }
                toolNotes = MCPClient.promptLines(for: enrichment.notes)
                if let problem = enrichment.problem {
                    mcpStatusHint = problem
                }
            }

            let context = AskContext(
                observation: observationSnapshot,
                memories: memoriesSnapshot,
                tasks: tasksSnapshot,
                includeImage: includeImage,
                history: historySnapshot,
                editableFile: fileSnapshot,
                isTeaching: teach,
                isGuidedTeaching: guide,
                wantsBoard: boardWanted,
                teachingFocus: focus,
                sessionMode: mode,
                pageStructure: pageSnapshot,
                problemTutor: problem,
                toolNotes: toolNotes
            )

            // Accumulated locally rather than in a property: the turn is the
            // one place an answer lives, and a second copy of it that has to be
            // kept in step is the sort of thing that silently drifts.
            var streamed = ""
            // Hold the panel only for Teach / board walks — ordinary Ask streams
            // again so every question does not feel like a blocked progress bar.
            let holdUntilComplete = teach || boardWanted
            isHoldingAnswer = holdUntilComplete
            answerLoadProgress = 0.05
            // A local model that has been unloaded takes many seconds to say
            // anything, and an unexplained bar at its floor reads as a hang.
            let firstTokenWatch = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self,
                      self.answerGeneration == generation, self.phase == .thinking else { return }
                self.modelLoadHint = brain.leavesTheMachine
                    ? "Waiting for the first words…"
                    : "Loading \(AppSettings.model) on this Mac — the first answer takes longest…"
            }
            defer {
                firstTokenWatch.cancel()
                if self.answerGeneration == generation {
                    self.modelLoadHint = nil
                    self.isHoldingAnswer = false
                }
            }
            do {
                let stream = brain.answerStream(question: prompt, context: context)
                for try await chunk in stream {
                    if superseded() { abandon(); return }
                    if streamed.isEmpty {
                        firstTokenWatch.cancel()
                        modelLoadHint = nil
                    }
                    streamed += chunk
                    if phase != .answering { phase = .answering }
                    // The panel shows this bar for every answer, so it has to
                    // move for every answer; one that only moved while held read
                    // as frozen on a plain question.
                    answerLoadProgress = min(0.92, 0.08 + Double(streamed.count) / 1_800)
                    if !holdUntilComplete {
                        recordAnswer(streamed, for: turnID)
                        speech.speakArriving(streamed)
                    }
                }
                guard !superseded() else { abandon(); return }

                answerLoadProgress = 1
                var finalAnswer = streamed
                if teach { beginLesson(from: finalAnswer) }

                // Repair only when there is *no* board at all. A one-frame fence
                // used to fail `storyboard` and cost a full second model call.
                if teach, BoardScene.from(answer: finalAnswer) == nil {
                    sketchRepairHint = "Sketch missing — drawing the storyboard…"
                    answerLoadProgress = 0.55
                    if let repaired = await self.repairTeachStoryboard(
                        brain: brain,
                        baseContext: context,
                        answer: finalAnswer
                    ) {
                        guard !superseded() else { abandon(); return }
                        finalAnswer = finalAnswer + "\n\n" + repaired
                        beginLesson(from: finalAnswer)
                    }
                    guard !superseded() else { abandon(); return }
                    sketchRepairHint = BoardScene.from(answer: finalAnswer) == nil
                        ? "No sketch board — teaching from the steps only"
                        : nil
                }

                recordAnswer(finalAnswer, for: turnID)
                if wantsBoardThisAnswer || teach {
                    explainSpeakable = SpeechPlayback.speakable(from: finalAnswer)
                    explainHeardCharacters = 0
                    refreshBoard(from: finalAnswer)
                    // The answer is final, so a board that has not appeared is
                    // not coming. Still reserving the beat for one hid the step
                    // tips and left an empty screen under "Step 1 of 5".
                    if boardScene == nil {
                        wantsBoardThisAnswer = false
                        if lesson != nil { showLessonStep() }
                    }
                }
                if teach, lesson != nil {
                    startTeachingPlayback()
                } else {
                    speech.finish(finalAnswer)
                }
                captureProposedEdit(from: finalAnswer)
                findPointerTarget(in: finalAnswer)
                lastTurnAt = Date()
                phase = .idle
                answerLoadProgress = 0
                // Keep the override while a lesson is still on screen so a late
                // clause can still advance it. Cleared when the lesson ends, or
                // immediately when teaching produced only an ordinary answer.
                if lesson == nil { clearTeachingSpeechOverride() }
            } catch {
                guard !superseded() else { abandon(); return }
                clearTeachingSpeechOverride()
                sketchRepairHint = nil
                answerLoadProgress = 0
                phase = .failed(Self.failureMessage(for: error))
            }
        }
    }

    /// What a failed answer says, in words someone can act on.
    ///
    /// `URLError`'s own descriptions name the transport ("The network
    /// connection was lost.") and cloud providers reach here without the
    /// mapping `OllamaBrain` does, so the common cases are restated once.
    static func failureMessage(for error: Error) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }
        switch urlError.code {
        case .timedOut:
            return BrainError.timedOut.localizedDescription
        case .networkConnectionLost:
            return BrainError.connectionLost.localizedDescription
        case .notConnectedToInternet, .cannotFindHost, .dnsLookupFailed:
            return "No internet connection — switch to the local model, or try again once online."
        default:
            return error.localizedDescription
        }
    }

    /// One board-only follow-up so Teach is not a code dump without a sketch.
    private func repairTeachStoryboard(brain: Brain,
                                       baseContext: AskContext,
                                       answer: String) async -> String? {
        let stepLines: [String] = {
            if let lesson = Lesson.from(answer: answer) {
                return lesson.steps.map(\.text)
            }
            for block in AnswerContent.blocks(in: answer) {
                if case let .numbered(items) = block { return items }
            }
            return []
        }()
        guard stepLines.count >= 2 else { return nil }

        var repairContext = baseContext
        repairContext.isTeaching = true
        repairContext.wantsBoard = true
        repairContext.history = []
        // Image already informed the first answer; the repair is steps → board.
        repairContext.includeImage = false

        let question = Prompt.boardRepairQuestion(steps: stepLines)
        var collected = ""
        do {
            for try await chunk in brain.answerStream(question: question, context: repairContext) {
                if Task.isCancelled { return nil }
                collected += chunk
                answerLoadProgress = min(0.9, 0.55 + Double(collected.count) / 2_400)
            }
        } catch {
            return nil
        }
        guard BoardScene.storyboard(from: collected) != nil else { return nil }
        // Keep only the fence so we do not paste a second prose lesson.
        if let json = BoardScene.extractBoardJSON(from: collected) {
            return "```board\n\(json)\n```"
        }
        return collected
    }

    /// Session-only speech / follow-along forced by Teach me.
    private var followAlongThisAnswer = false

    /// Teach / Guided is in flight for this answer (before or during the lesson).
    var isPreparingLesson: Bool { followAlongThisAnswer }

    /// Session-only: Guided Teach warps the cursor to each step's box.
    private var guidedTeachThisAnswer = false

    /// Session-only: parse and show a teaching-grid board for this answer.
    private var wantsBoardThisAnswer = false

    private func clearTeachingSpeechOverride() {
        speech.speaksRegardlessOfSetting = false
        followAlongThisAnswer = false
        // Leave guidedTeachThisAnswer alone while a lesson is still on screen —
        // ending speech mid-lesson must not kill cursor follow for later steps.
        if lesson == nil {
            guidedTeachThisAnswer = false
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

    /// App whose screen was captured, so Show me / Guided Teach can activate it
    /// before warping the pointer — Max holds key focus when those run.
    private weak var contextApp: NSRunningApplication?

    private func findPointerTarget(in answer: String) {
        guard let observation else {
            pointerTarget = nil
            return
        }
        pointerTarget = observation.locatePointable(named: answer)?.match
    }

    /// Draws a box around what the answer named, and warps the pointer onto it
    /// when Accessibility extras are on.
    ///
    /// Always re-reads the screen. Locating on the summon capture first looked
    /// faster, but after the editor reflows the same label still "matches" at
    /// the old box — a confident mark on the wrong line (docs/USABILITY.md §7).
    ///
    /// Runs on `captureTask` like every other grab so summon / Look again / Teach
    /// can cancel it — an orphan Task left the panel ordered out and could
    /// re-front it after the user had dismissed.
    func showPointerTarget() {
        let answer = turns.last?.answer ?? ""
        guard !answer.isEmpty else { return }

        let occlusionID = UUID()
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self else { return }

            let context = resolveContextApp?() ?? contextApp
            let crop = observation?.isCropped == true ? observation?.primaryScreenFrame : nil
            beginPanelOcclusion(for: occlusionID)
            defer { endPanelOcclusion(for: occlusionID) }

            let ok = await performCapture(frontmostApp: context,
                                          preserveCropFrame: crop,
                                          preserveTeaching: true)
            guard ok, !Task.isCancelled else { return }

            guard let hit = observation?.locatePointable(named: answer)
            else {
                phase = .failed("That label isn’t on screen anymore — try Look again")
                return
            }

            pointerTarget = hit.match
            highlightPointer(hit.match, in: hit.frame)
        }
    }

    private func highlightPointer(_ match: ScreenTextLocator.Match, in frame: CGRect) {
        let rect = ScreenTextLocator.screenRect(for: match.boundingBox, in: frame)
        onHighlight?(rect, false)

        guard TrustAccessibility.extrasAreActive else { return }
        warpPointer(to: CGPoint(x: rect.midX, y: rect.midY))
    }

    /// Activates the captured app, waits for it to take front, then warps.
    ///
    /// Activating and warping in the same turn left the cursor on Max or on a
    /// half-switched app — one jump to a useless point. The short settle is
    /// what makes Show me and Guided Teach land on the control that was boxed.
    private func warpPointer(to point: CGPoint) {
        let app = contextApp
        let generation = UUID()
        warpGeneration = generation
        warpTask?.cancel()
        warpTask = Task { [weak self] in
            app?.activate(options: [.activateIgnoringOtherApps])
            // Longer than a single frame: Guided warps while Max still holds
            // key focus and a speaking synthesizer is starting, and 80ms was
            // often not enough for the context app to finish coming forward.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self, self.warpGeneration == generation else { return }
            AXControlLocator.movePointer(to: point)
        }
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
        // A lesson is already boxing what the current step names, and the two
        // would otherwise fight over the same screen: the single box would jump
        // to whichever label the clause happened to quote first while the
        // lesson's own marks stayed where they were.
        if lesson != nil {
            advanceLesson(spokenIn: clause)
            return
        }

        advanceExplainBoard(spokenIn: clause)

        guard AppSettings.followsAlongWhileSpeaking || followAlongThisAnswer else { return }

        guard let clause else {
            onHighlightEnded?()
            return
        }

        guard let observation,
              let hit = observation.locatePointable(named: clause, requiringQuoted: true)
        else { return }

        onHighlight?(ScreenTextLocator.screenRect(for: hit.match.boundingBox, in: hit.frame), true)
    }

    // MARK: - Teaching

    /// Draws the marks for one step of a lesson, in global screen coordinates.
    var onLessonMarks: ((LessonMarks) -> Void)?
    var onLessonEnded: (() -> Void)?

    private(set) var lesson: Lesson?
    private(set) var lessonStep = 0

    /// Where each step's labels are, resolved once and re-resolved on demand.
    ///
    /// Held here rather than looked up from `observation` on each step, because
    /// a lesson outlives the capture: `endSession` drops the observation, and
    /// dismissing the panel is exactly what the user does to get back to the
    /// code being taught. Keeping the geometry is what lets the boxes stay up
    /// while they work underneath them.
    private var lessonMarks: [[CGRect]] = []
    private var lessonFrame: CGRect = .zero
    /// Last step Guided already warped to. beginLesson runs on every streamed
    /// chunk; without this the cursor thrashes to the same box dozens of times
    /// and keeps yanking focus into the context app mid-answer.
    private var lastGuidedWarpStep: Int?

    /// Steps that already got one OCR re-read after a miss. Without this a
    /// tip-only beat would re-capture forever when the label simply is not
    /// on screen (conceptual step, or empty editor).
    private var anchorRetrySteps: Set<Int> = []

    /// One-beat-at-a-time voice walk for Teach. Cancelled on Done, arrows, or quit.
    private var teachingPlayback: Task<Void, Never>?

    /// Brief hold after a spoken beat so the eye can land on the mark before
    /// the next step — the classroom "point and pause" cue.
    private static let teachingBeatPause: Duration = .milliseconds(180)

    // MARK: - Teaching board

    /// Drawn on Max's grid panel — invented diagrams, not OCR marks.
    /// Scene, frame, and what Max says over that frame (paces the pen).
    var onBoardScene: ((BoardScene, Int, String?) -> Void)?
    var onBoardEnded: (() -> Void)?

    private(set) var boardScene: BoardScene?
    private(set) var boardFrameIndex = 0

    /// Frame and beat last sent to the board. Republishing restarts the pen,
    /// so it happens when the beat changes and never on an incidental
    /// `showLessonStep` — an anchor retry mid-sentence used to wipe the
    /// drawing and start it again while Max was still talking about it.
    private var publishedBoardBeat: (frame: Int, step: Int)?

    /// Explain boards follow how far through the spoken answer the voice is.
    private var explainSpeakable = ""
    private var explainHeardCharacters = 0

    /// User closed the board from its own chrome.
    func closeBoard() {
        endBoard()
    }

    /// Parses a closed `board` fence out of the answer and publishes the frame
    /// that matches the current lesson step (or frame 0 for Explain).
    private func refreshBoard(from answer: String) {
        guard wantsBoardThisAnswer,
              let scene = BoardScene.from(answer: answer)
        else { return }

        let isNewScene = boardScene != scene
        boardScene = scene
        if lesson != nil {
            boardFrameIndex = scene.frameIndex(forLessonStep: lessonStep)
        } else {
            boardFrameIndex = scene.clampedFrameIndex(boardFrameIndex)
        }
        if isNewScene { publishedBoardBeat = nil }
        publishBoardIfBeatChanged()
    }

    /// Sends the current frame unless that exact beat is already being drawn.
    private func publishBoardIfBeatChanged(force: Bool = false) {
        guard let boardScene else { return }
        let beat = (frame: boardFrameIndex, step: lesson == nil ? -1 : lessonStep)
        if !force, let published = publishedBoardBeat,
           published.frame == beat.frame, published.step == beat.step {
            return
        }
        publishedBoardBeat = beat
        onBoardScene?(boardScene, boardFrameIndex, boardNarration())
    }

    /// What Max says over the current frame: the lesson beat, or for Explain
    /// the share of the spoken answer that falls on this frame.
    private func boardNarration() -> String? {
        if let lesson, lesson.steps.indices.contains(lessonStep) {
            return lesson.steps[lessonStep].text
        }
        guard let boardScene, boardScene.frames.count > 0, !explainSpeakable.isEmpty else { return nil }
        let count = boardScene.frames.count
        let length = explainSpeakable.count
        let start = length * boardFrameIndex / count
        let end = length * (boardFrameIndex + 1) / count
        let text = explainSpeakable
        let lower = text.index(text.startIndex, offsetBy: start)
        let upper = text.index(text.startIndex, offsetBy: max(start, end))
        return String(text[lower..<upper])
    }

    private func syncBoardToLessonStep() {
        guard let boardScene else { return }
        boardFrameIndex = boardScene.frameIndex(forLessonStep: lessonStep)
        publishBoardIfBeatChanged()
    }

    /// A short head-start so the pen is already moving when the voice begins.
    /// The pen is paced to the narration, so waiting for it to finish would
    /// put the whole beat's silence in front of the sentence.
    private func waitForSketchReveal() async {
        guard boardScene != nil else { return }
        try? await Task.sleep(for: .milliseconds(Int(SketchRevealTiming.voiceLeadSeconds * 1_000)))
    }

    /// Explain (no lesson): the frame follows how far through the spoken
    /// answer the voice has got. Advancing one frame per clause skipped the
    /// first frame the moment speech began and ran out of frames long before
    /// a long answer ended.
    private func advanceExplainBoard(spokenIn clause: String?) {
        guard wantsBoardThisAnswer,
              lesson == nil,
              let scene = boardScene,
              scene.frames.count > 1,
              let clause,
              !explainSpeakable.isEmpty
        else { return }

        let heardBefore = explainHeardCharacters
        explainHeardCharacters += clause.count
        let fraction = Double(heardBefore) / Double(max(explainSpeakable.count, 1))
        let target = min(scene.frames.count - 1, Int(fraction * Double(scene.frames.count)))
        guard target > boardFrameIndex else { return }
        boardFrameIndex = target
        publishBoardIfBeatChanged()
    }

    private func endBoard() {
        let hadBoard = boardScene != nil
        boardScene = nil
        boardFrameIndex = 0
        publishedBoardBeat = nil
        explainSpeakable = ""
        explainHeardCharacters = 0
        wantsBoardThisAnswer = false
        if hadBoard { onBoardEnded?() }
    }

    /// Takes the marks down if the panel is dismissed and never comes back.
    ///
    /// The lesson surviving dismissal is the point of it, but "until the next
    /// summon" is not a bound when the next summon may never happen — and an
    /// overlay with no window to switch it off is the app having drawn
    /// something the user cannot undraw.
    private static let lessonLingerAfterDismissal: TimeInterval = 300
    private var lessonExpiry: Task<Void, Never>?

    var lessonStepCount: Int { lesson?.steps.count ?? 0 }
    var canAdvanceLesson: Bool { lesson.map { lessonStep + 1 < $0.steps.count } ?? false }
    var canRewindLesson: Bool { lesson != nil && lessonStep > 0 }

    /// Turns a finished answer into a lesson, if it turned out to be one.
    ///
    /// Silent when it did not. A model that wrote prose where steps were asked
    /// for has still answered the question, and putting an empty lesson bar
    /// over that answer would report a failure the user cannot act on.
    private func beginLesson(from answer: String) {
        guard !lessonSuppressedForAnswer else { return }
        guard let parsed = Lesson.from(answer: answer),
              let observation,
              !observation.pointingSurfaces.isEmpty
        else { return }

        // Called again as the stream grows: keep the current step when more
        // items appear rather than snapping back to the first every chunk.
        let starting = lesson == nil
        lesson = parsed
        if starting {
            lessonStep = 0
            anchorRetrySteps = []
            // Lesson means working underneath the panel — auto-pin so a click
            // into the editor does not tear the boxes down (USABILITY §3).
            // Set the flag *after* toggling pin: `isPinned.didSet` clears it so
            // a manual pin later is not stolen by Done.
            if !isPinned {
                isPinned = true
                pinnedForLesson = true
            }
        } else {
            lessonStep = min(lessonStep, parsed.steps.count - 1)
        }
        resolveLessonMarks(across: observation.pointingSurfaces)
        showLessonStep()
    }

    func endLesson() {
        lessonExpiry?.cancel()
        lessonExpiry = nil
        teachingPlayback?.cancel()
        teachingPlayback = nil
        speech.stop()
        // Guided leaves a Standalone highlight up `untilHidden`; without this
        // the amber box outlived Done / Quit and looked like the lesson stuck.
        onHighlightEnded?()
        // While this answer is still arriving, refuse to start the lesson again
        // from later chunks — otherwise Done is undone mid-stream. Look again
        // mid-stream sets the flag in `performCapture` before phase becomes
        // `.reading`, because by the time we get here phase alone is too late.
        if phase == .thinking || phase == .answering {
            lessonSuppressedForAnswer = true
        }
        guard lesson != nil else {
            clearTeachingSpeechOverride()
            return
        }

        let shouldUnpin = pinnedForLesson
        lesson = nil
        lessonStep = 0
        lessonMarks = []
        lastGuidedWarpStep = nil
        anchorRetrySteps = []
        pinnedForLesson = false
        clearTeachingSpeechOverride()
        if shouldUnpin {
            isPinned = false
        }
        onLessonEnded?()
        endBoard()
    }

    /// Walks the lesson the way a tutor does: show the mark, say that beat,
    /// pause, then advance. The panel's current step stays in lockstep.
    private func startTeachingPlayback() {
        teachingPlayback?.cancel()
        speech.stop()
        teachingPlayback = Task { [weak self] in
            guard let self else { return }
            guard let steps = self.lesson?.steps, !steps.isEmpty else { return }

            for index in steps.indices {
                guard !Task.isCancelled, self.lesson != nil else { return }
                self.lessonStep = index
                self.lastGuidedWarpStep = nil
                // Later steps often miss on the first grab (editor empty, pane
                // scrolled). One re-read before the tip-only fallback is what
                // made step 1 box and step 3 only show a floating chip.
                if self.lessonMarks.indices.contains(index),
                   self.lessonMarks[index].isEmpty,
                   !steps[index].anchors.isEmpty {
                    await self.refreshLessonAnchors()
                }
                self.showLessonStep()
                // Pen finishes the cut before the voice — otherwise Max narrates
                // over a blank board and the "video" feel collapses.
                await self.waitForSketchReveal()
                guard !Task.isCancelled, self.lesson != nil else { return }
                await self.speech.speakAndAwait(steps[index].text)
                guard !Task.isCancelled, self.lesson != nil else { return }
                try? await Task.sleep(for: Self.teachingBeatPause)
            }
        }
    }

    /// Guide cursor for the rest of this lesson (and remember for the next Teach).
    func setGuideCursorWhileTeaching(_ on: Bool) {
        AppSettings.guideCursorWhileTeaching = on
        guidedTeachThisAnswer = on
        if on {
            prepareTeachingPointerAccess()
            // Clearing lets the current step warp again after Guide was toggled
            // off — otherwise `lastGuidedWarpStep == lessonStep` blocked it.
            lastGuidedWarpStep = nil
            showLessonStep()
        }
    }

    var guideCursorWhileTeaching: Bool { guidedTeachThisAnswer }

    /// Why the cursor did not move — for the lesson bar, not a silent no-op.
    var teachingPointerBlocker: String? {
        guard guidedTeachThisAnswer, lesson != nil else { return nil }
        if !AppSettings.accessibilityExtrasEnabled {
            return "Pointer teaching is off — tap Enable below."
        }
        if !TrustAccessibility.isTrusted {
            return "Allow Max under System Settings → Privacy & Security → Accessibility."
        }
        return nil
    }

    /// Turns on extras, asks macOS for the Accessibility prompt, and opens
    /// Settings when trust is still missing. Called from Teach and the banner.
    func enableTeachingPointerAccess() {
        AppSettings.guideCursorWhileTeaching = true
        guidedTeachThisAnswer = true
        prepareTeachingPointerAccess()
        lastGuidedWarpStep = nil
        if lesson != nil { showLessonStep() }
    }

    /// Enables the Accessibility-extras flag and requests the TCC prompt.
    ///
    /// Broad reason the cursor "never moves": warping needs
    /// `accessibilityExtrasEnabled` *and* `AXIsProcessTrusted()`. Both were
    /// off by default, so Teach drew boxes and looked finished while the
    /// pointer stayed put. Asking here — when the user pressed Teach — is the
    /// self-heal.
    ///
    /// - Parameter openSettingsIfNeeded: when false, only registers the TCC
    ///   request (so Max appears in the Accessibility list). Teach defers the
    ///   System Settings hand-off until the capture panel is visible again.
    private func prepareTeachingPointerAccess(openSettingsIfNeeded: Bool = true) {
        AppSettings.guideCursorWhileTeaching = true
        if !AppSettings.accessibilityExtrasEnabled {
            TrustAccessibility.setExtrasEnabled(true)
        } else if !TrustAccessibility.isTrusted {
            _ = TrustAccessibility.request()
        }
        // Prompt alone does not wait for the toggle in System Settings — open
        // the pane whenever trust is still missing so Enable is not a dead end.
        if openSettingsIfNeeded, !TrustAccessibility.isTrusted {
            TrustAccessibility.openSystemSettings()
        }
    }

    private var hasOfferedAccessibilityGrant = false

    /// Opens the Accessibility list from Teach once per launch, not per press.
    ///
    /// Every press used to bring System Settings forward while the grant was
    /// missing, so a lesson started over someone's work by covering it. Once
    /// is the offer; after that the lesson teaches with boxes alone and the
    /// switch stays in Settings.
    private func offerAccessibilityGrantOnce() {
        guard !TrustAccessibility.isTrusted, !hasOfferedAccessibilityGrant else { return }
        hasOfferedAccessibilityGrant = true
        TrustAccessibility.openSystemSettings()
    }

    /// Moves to a step because the user pressed a button.
    ///
    /// Re-reads the screen first, which the spoken advance deliberately does
    /// not. The anchors were resolved against the screen as it was when the
    /// question was asked, and the whole point of this feature is that the user
    /// keeps working underneath it — a few keystrokes reflow an editor and
    /// every box below the caret is a line out. Failing to find a label is
    /// recoverable; a confident box around the wrong line is not, so the pause
    /// is worth it on a press. While speaking there is no press, the screen is
    /// very unlikely to have moved, and a capture between every sentence would
    /// be the continuous capture this app refuses.
    func stepLesson(by offset: Int) {
        guard let lesson else { return }
        let target = max(0, min(lesson.steps.count - 1, lessonStep + offset))
        guard target != lessonStep else { return }

        // Manual advance takes over from the automatic walk — otherwise the
        // playback task would yank the step back a moment later.
        teachingPlayback?.cancel()
        teachingPlayback = nil
        speech.stop()

        lessonStep = target
        lastGuidedWarpStep = nil
        showLessonStep()

        let beat = lesson.steps[target].text
        // One at a time: rapid arrow presses used to stack re-captures and
        // speak several beats over one another.
        teachingPlayback = Task { [weak self] in
            guard let self else { return }
            await self.refreshLessonAnchors()
            guard !Task.isCancelled, self.lesson != nil else { return }
            self.showLessonStep()
            // Speak only this beat so arrows stay in sync with the voice.
            if self.lessonAdvancesByVoice {
                await self.speech.speakAndAwait(beat)
            }
        }
    }

    /// Explain board without a lesson: step frames by hand when speech is off.
    func stepBoardFrame(by offset: Int) {
        guard lesson == nil, let scene = boardScene, scene.frames.count > 1 else { return }
        let target = max(0, min(scene.frames.count - 1, boardFrameIndex + offset))
        guard target != boardFrameIndex else { return }
        boardFrameIndex = target
        publishBoardIfBeatChanged()
    }

    var canAdvanceBoardFrame: Bool {
        lesson == nil && (boardScene.map { boardFrameIndex + 1 < $0.frames.count } ?? false)
    }

    var canRewindBoardFrame: Bool {
        lesson == nil && boardScene != nil && boardFrameIndex > 0
    }

    var boardFrameCount: Int { boardScene?.frames.count ?? 0 }

    /// Keep this after an answer — same save path as ⌘S, reason from the ask.
    func keepThis() {
        saveCurrentContext()
    }

    func dismissVisionNudge() {
        visionNudge = nil
    }

    /// Questions that are about pixels more than about OCR text.
    ///
    /// Whole-word cues only — `"graph"` must not match inside `"paragraph"`.
    nonisolated static func looksLikeVisualQuestion(_ text: String) -> Bool {
        let lower = text.lowercased()
        let phrases = ["what do you see", "what's on screen", "look like", "ui look"]
        if phrases.contains(where: { lower.contains($0) }) { return true }

        let words = ["diagram", "chart", "graph", "image", "screenshot", "picture",
                     "icon", "drawing", "sketch", "visual"]
        return words.contains { containsWholeWord($0, in: lower) }
    }

    nonisolated private static func containsWholeWord(_ word: String, in text: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    /// Whether Speak answers (or a session override) will actually read this lesson.
    var lessonAdvancesByVoice: Bool {
        AppSettings.speaksAnswers || speech.speaksRegardlessOfSetting
    }

    /// Moves to whichever step the clause now being read aloud belongs to.
    ///
    /// Only used when Teach is *not* driving `teachingPlayback` (e.g. Speak
    /// answers on a leftover monologue). Beat-gated playback already sets the
    /// step before each utterance, so matching here would race it.
    private func advanceLesson(spokenIn clause: String?) {
        guard teachingPlayback == nil else { return }
        guard let lesson, let clause else { return }
        guard let target = lesson.step(spokenIn: clause, notBefore: lessonStep),
              target != lessonStep
        else { return }

        lessonStep = target
        showLessonStep()
    }

    private func startLessonExpiry() {
        guard lesson != nil else { return }
        lessonExpiry?.cancel()
        lessonExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.lessonLingerAfterDismissal))
            guard !Task.isCancelled else { return }
            self?.endLesson()
        }
    }

    /// Resolves every step's quoted labels across every capture surface.
    ///
    /// Anchors are resolved in the order Max named them, not display-major
    /// order — otherwise an arrow `"A" → "B"` with A on monitor 2 and B on
    /// monitor 1 drew backwards and Guided warped to the wrong box.
    ///
    /// OCR first; Accessibility tree as a second pass for the same quote when
    /// Vision misses (browsers / thin editors). AX was already used for Guided
    /// warps but never fed the overlay — so the tip chip appeared with no box.
    private func resolveLessonMarks(across surfaces: [(regions: [TextRegion], frame: CGRect)]) {
        guard let lesson, let first = surfaces.first else { return }

        lessonMarks = lesson.steps.map { step in
            let fromOCR: [CGRect] = step.anchors.compactMap { anchor in
                for surface in surfaces {
                    if let hit = ScreenTextLocator.locate(label: anchor, in: surface.regions) {
                        return ScreenTextLocator.screenRect(for: hit.boundingBox, in: surface.frame)
                    }
                }
                return nil
            }
            if !fromOCR.isEmpty { return fromOCR }
            guard TrustAccessibility.extrasAreActive else { return [] }
            return step.anchors.compactMap { AXControlLocator.locate(label: $0)?.frame }
        }

        let allMarks = lessonMarks.flatMap { $0 }
        if allMarks.isEmpty {
            lessonFrame = first.frame
        } else {
            // Only the displays that actually contributed a box — unioning every
            // capture surface made the overlay span empty monitors.
            lessonFrame = allMarks.reduce(CGRect.null) { $0.union($1) }
        }
    }

    /// One step's worth of drawing, in global screen coordinates.
    ///
    /// A value type rather than five arguments, because the overlay is reached
    /// through a closure and the fourth `CGRect` in a row is exactly where a
    /// caller silently passes the covered boxes as the current ones.
    struct LessonMarks {
        let current: [CGRect]
        let covered: [CGRect]
        let number: Int
        let caption: String
        let isConnected: Bool
        let screen: CGRect
    }

    private func showLessonStep() {
        guard let lesson, lessonMarks.indices.contains(lessonStep) else { return }

        let step = lesson.steps[lessonStep]
        let current = lessonMarks[lessonStep]
        // Clicky points at OCR; Golpo keeps concept tips on the whiteboard.
        // Suppress floating chips whenever a board owns (or will own) the beat —
        // waiting for the fence to parse used to drop a black pill on Max.
        let boardOwnsBeat = current.isEmpty && (boardScene != nil || wantsBoardThisAnswer)
        let caption = (current.isEmpty && !boardOwnsBeat) ? step.cue : ""
        onLessonMarks?(LessonMarks(
            current: current,
            covered: [],
            number: lessonStep + 1,
            caption: caption,
            // An arrow needs somewhere to go: a step whose second label Vision
            // could not find would otherwise draw one from a box to itself.
            isConnected: step.isConnected && current.count > 1,
            screen: lessonFrame
        ))

        syncBoardToLessonStep()

        // One silent re-read when a quoted step drew nothing — arrows already
        // do this; voice advance used to skip it and strand later beats on tips.
        if current.isEmpty,
           !step.anchors.isEmpty,
           !anchorRetrySteps.contains(lessonStep),
           observation?.isCropped != true {
            anchorRetrySteps.insert(lessonStep)
            Task { [weak self] in
                guard let self else { return }
                await self.refreshLessonAnchors()
                guard self.lesson != nil else { return }
                self.showLessonStep()
            }
        }

        // Guided Teach: warp to the first box of this step. Never clicks —
        // the user does that. Only when the step *changes* — beginLesson is
        // called per streamed chunk for the same step, and warping every time
        // fights the user for the pointer. Also wait until the beat walk (or a
        // manual arrow) owns the step — warping while the answer is still
        // streaming yanked the cursor before the voice had anything to say.
        guard guidedTeachThisAnswer else { return }
        guard lastGuidedWarpStep != lessonStep else { return }
        guard TrustAccessibility.extrasAreActive else { return }
        guard teachingPlayback != nil
                || phase == .idle
                || phase == .reading
        else { return }

        if let rect = current.first {
            lastGuidedWarpStep = lessonStep
            // Also draw the amber Show-me box so the pointer and the mark agree.
            onHighlight?(rect, true)
            warpPointer(to: CGPoint(x: rect.midX, y: rect.midY))
        }
    }

    /// Whether the current step named something printable (vs a pure concept beat).
    var currentLessonStepQuotesScreen: Bool {
        guard let lesson, lesson.steps.indices.contains(lessonStep) else { return false }
        return !lesson.steps[lessonStep].anchors.isEmpty
    }

    /// Whether Guided is active but cannot move the pointer yet.
    var guidedNeedsAccessibility: Bool {
        guidedTeachThisAnswer && lesson != nil && !TrustAccessibility.extrasAreActive
    }

    /// Guided is on and trusted, but this step's quotes are not on the capture.
    /// Without a box there is nowhere to warp — the failure looks like the
    /// cursor never tried.
    var guidedMissingOnScreenMatch: Bool {
        guard guidedTeachThisAnswer,
              lesson != nil,
              TrustAccessibility.extrasAreActive,
              lessonMarks.indices.contains(lessonStep)
        else { return false }
        return lessonMarks[lessonStep].isEmpty
    }

    /// Reads the screen again and works out where the labels have moved to.
    ///
    /// Deliberately does not touch `observation`. The conversation is about the
    /// screen the question was asked against, and quietly swapping it here
    /// would answer a follow-up against a screen the user never asked about —
    /// `lookAgain` is the control that does that, on purpose and visibly.
    private func refreshLessonAnchors() async {
        // A cropped capture is measured against the region the user dragged
        // out, so a fresh full-screen grab would re-anchor every label to the
        // whole display without saying so.
        guard observation?.isCropped != true else { return }

        let context = resolveContextApp?() ?? contextApp
        guard var fresh = try? await ScreenCapture.captureAllDisplays(frontmostApp: context)
        else { return }

        let vocab = ocrVocabulary()
        let primaryRead = await Self.readText(in: fresh.primary.image, customWords: vocab)
        fresh.primary.recognizedText = primaryRead.text
        fresh.primary.textRegions = primaryRead.regions
        for index in fresh.others.indices {
            let other = await Self.readText(in: fresh.others[index].image, customWords: vocab)
            fresh.others[index].recognizedText = other.text
            fresh.others[index].textRegions = other.regions
        }
        guard lesson != nil, !fresh.pointingSurfaces.isEmpty else { return }
        resolveLessonMarks(across: fresh.pointingSurfaces)
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
        endLesson()
        endBoard()
        phase = .idle
    }

    /// Grabs the screen again while keeping the conversation.
    ///
    /// The point of the whole feature: the user does what they were told, the
    /// screen changes, and they ask "now what?" without losing the thread.
    func lookAgain(frontmostApp: NSRunningApplication?) {
        guard phase != .thinking, phase != .answering else { return }
        speech.stop()
        let context = frontmostApp ?? resolveContextApp?() ?? contextApp
        let crop = observation?.isCropped == true ? observation?.primaryScreenFrame : nil
        captureTask?.cancel()
        captureTask = Task {
            _ = await performCapture(frontmostApp: context, preserveCropFrame: crop)
        }
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
        let prior = ScreenChange.priorKeep(for: observation, among: recentContexts())
        let change = prior.flatMap {
            ScreenChange.summary(previous: $0.recognizedText, current: observation.recognizedText)
        }
        lastSaveChangeLine = change?.line

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
        let changeSuffix = change.map { " · \($0.line)" } ?? ""
        let destination = currentProject.map { "Saved to \($0.name)" } ?? "Saved"
        question = ""
        phase = .saved("\(destination)\(tagSuffix)\(changeSuffix)")
        addSummary(to: record, changePreface: change?.line)

        if let reminder {
            // In this order, not side by side. Handing a reminder to Apple
            // cancels Max's own notification for it, and a cancel that lands
            // before the notification has been added cancels nothing — so both
            // alerted, on the Mac, for the one thing asked about once.
            Task {
                await scheduleReminder(for: record, at: reminder,
                                       destination: destination, tagSuffix: tagSuffix)
                // Handed to Apple now rather than on the next summon: this is
                // usually said just before walking away from the Mac, which is
                // the one case where there is no next summon.
                mirrorTasksToAppleReminders(announceSuccess: true)
            }
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
    ///
    /// - Parameter announceSuccess: when true (a reminder was just set), append
    ///   a phone hint to the saved status if the list syncs off this Mac.
    private func mirrorTasksToAppleReminders(announceSuccess: Bool = false) {
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
                if announceSuccess,
                   let destination = AppleReminders.destination(),
                   destination.reachesOtherDevices,
                   case .saved(let message) = phase,
                   !message.contains("Mirrored") {
                    phase = .saved("\(message) · Mirrored — check Reminders on your iPhone")
                }
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
            Reminders.standDown(id: identifier)
        }
    }

    /// Scheduling can fail on a permission the user has already refused, and a
    /// reminder that was silently never set is worse than one that was never
    /// offered — the whole point is that it can be relied on.
    private func scheduleReminder(for record: SavedContext,
                                  at date: Date,
                                  destination: String,
                                  tagSuffix: String) async {
        let id = record.reminderIdentifier
        let intent = record.intent
        let sourceApp = record.sourceApp

        let scheduled = await Reminders.schedule(id: id,
                                                 at: date,
                                                 intent: intent,
                                                 sourceApp: sourceApp)
        if !scheduled {
            // Independent of what the panel shows: the permission prompt
            // can outlast the saved confirmation, and a reminder kept on a
            // refused grant is one that silently never fires.
            record.remindAt = nil
            try? modelContext.save()
        }

        switch phase {
        case .saved:
            break
        case .idle where !scheduled:
            break
        default:
            return
        }
        phase = scheduled
            ? .saved("\(destination) · reminder \(Self.reminderFormat(date))\(tagSuffix)")
            : .saved("Saved, but notifications are off in System Settings.")
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
    private func addSummary(to record: SavedContext, changePreface: String? = nil) {
        let brain = localBrain()
        let intent = record.intent
        let screenText = record.recognizedText

        Task {
            let gloss = (try? await brain.summarize(intent: intent, screenText: screenText))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let pieces = [changePreface, gloss].compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            if !pieces.isEmpty {
                // Change line is facts from OCR; gloss is labelled in the UI as
                // inference. Keeping both in aiSummary is fine — the library
                // already frames that field as the model's reading.
                record.aiSummary = pieces.joined(separator: " · ")
                try? modelContext.save()
            }
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
        regionTask?.cancel()
        regionSelector.cancel()
        warpTask?.cancel()
        answerTask?.cancel()
        answerGeneration = UUID()
        answerLoadProgress = 0
        sketchRepairHint = nil
        speech.stop()
        if isListening || dictationStartInFlight {
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
        // A lesson deliberately survives, and its marks stay on screen. This is
        // the same argument the conversation makes for surviving: reaching the
        // code being taught means clicking outside this app, so tearing the
        // boxes down here would leave them visible only while the user was
        // looking at the panel instead of at their work. It is bounded, since
        // nothing guarantees a next summon to end it.
        startLessonExpiry()
        // The opened file deliberately survives, because dismissing the panel
        // between questions about the same file is the normal way to use this
        // and re-picking it every time through a modal would be absurd.
        observation = nil
        pageStructure = nil
        related = []
        mcpStatusHint = nil
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

    /// Falls back to the local model when a cloud provider is selected without a
    /// key, so a missing secret degrades to a worse answer rather than an error.
    /// The badge says so — see `AnswerDestination.cloudWithoutKey` — because a
    /// silent downgrade is indistinguishable from the switch not working.
    private func makeBrain() -> any Brain {
        switch AppSettings.provider {
        case .openAI:
            if let key = AppSettings.openAIKey {
                return OpenAIBrain(apiKey: key, model: AppSettings.openAIModel)
            }
        case .anthropic:
            if let key = AppSettings.anthropicKey {
                return AnthropicBrain(apiKey: key, model: AppSettings.anthropicModel)
            }
        case .gemini:
            if let key = AppSettings.geminiKey {
                return GeminiBrain(apiKey: key, model: AppSettings.geminiModel)
            }
        case .ollama:
            break
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

    // MARK: - Continuity actions (project brief, standup, clipboard, lesson)

    /// Reads the pasteboard when the field is empty so a chip can offer it.
    func refreshClipboardOffer() {
        guard question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clipboardOffer = nil
            return
        }
        let pasted = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pasted, pasted.count >= 4, pasted.count <= 2_000 else {
            clipboardOffer = nil
            return
        }
        clipboardOffer = pasted
    }

    /// Puts a prior keep's intent into the field so the user can ask about it.
    func askAboutRelated(_ match: RetrievalMatch) {
        question = "About what I kept — \"\(match.context.intent)\": "
        refreshClipboardOffer()
    }

    /// Uses clipboard contents as the question (or appends if the field is empty).
    func askAboutClipboard() {
        guard let offer = clipboardOffer else { return }
        question = offer
        clipboardOffer = nil
        submit(isFromPreset: false, isTeaching: false, isGuidedTeaching: false, wantsBoard: false)
    }

    /// Drafts a project brief from the user's own intents and open tasks.
    func askProjectBrief() {
        guard let project = currentProject else {
            phase = .failed("Pick a project first — the brief is built from what you kept in it.")
            return
        }
        let contexts = project.contexts.sorted { $0.createdAt > $1.createdAt }
        let intents = contexts.map(\.intent)
        let tasks = linkedWork.todos(withIDs: project.linkedTodoIDs).filter { !$0.isDone }.map(\.title)
        let due = contexts.filter {
            $0.hasReminderDue(within: 48 * 60 * 60) || $0.hasOverdueReminder
        }.map(\.intent)

        guard let prompt = ProjectBrief.askPrompt(projectName: project.name,
                                                  intents: intents,
                                                  openTaskTitles: tasks,
                                                  dueSoonIntents: due) else {
            phase = .failed("Nothing in \(project.name) yet to brief on.")
            return
        }
        question = prompt
        submit(isFromPreset: false, isTeaching: false, isGuidedTeaching: false, wantsBoard: false)
    }

    /// Standup / meeting prep from tasks, due reminders, and recent keeps.
    func askStandupPrep() {
        let contexts = recentContexts()
        let due = contexts.filter {
            $0.hasReminderDue(within: 48 * 60 * 60) || $0.hasOverdueReminder
        }.map(\.intent)
        let recent = contexts.prefix(8).map(\.intent)
        let tasks = linkedWork.openTodos.prefix(10).map(\.title)

        question = StandupPrep.askPrompt(projectName: currentProject?.name,
                                         openTaskTitles: Array(tasks),
                                         dueSoonIntents: due,
                                         recentKeepIntents: Array(recent))
        submit(isFromPreset: false, isTeaching: false, isGuidedTeaching: false, wantsBoard: false)
    }

    /// Copies the active lesson to the pasteboard as Markdown.
    @discardableResult
    func exportLessonMarkdown() -> Bool {
        guard let lesson else { return false }
        let title: String = {
            if let window = observation?.windowTitle, !window.isEmpty { return window }
            if let app = observation?.appName, !app.isEmpty { return app }
            return "Lesson"
        }()
        let markdown = lesson.markdown(title: title)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        phase = .saved("Lesson copied as Markdown")
        return true
    }
}
