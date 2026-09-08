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

    var phase: Phase = .idle
    var answer: String = ""
    var contextLabel: String = "Nothing captured yet"

    /// Re-reads the reminder suggestion on every keystroke, so the offer
    /// appears and disappears as the sentence changes.
    var question: String = "" {
        didSet { refreshReminderSuggestion() }
    }

    /// What the app thinks the typed reason is asking for, if anything.
    private(set) var reminderSuggestion: ReminderSuggestion?

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
        switch phase {
        case .idle: return contextLabel
        case .reading: return "Reading your screen…"
        case .startingDictation: return "Turning the microphone on…"
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
        onCaptureBegan?()
        // A key may have been added in Settings since the last summon.
        refreshCloudKey()

        captureTask = Task {
            defer { onCaptureEnded?() }
            do {
                var fresh = try await ScreenCapture.captureAllDisplays(frontmostApp: frontmostApp)
                fresh.primary.recognizedText = await Self.readText(in: fresh.primary.image)
                for index in fresh.others.indices {
                    fresh.others[index].recognizedText = await Self.readText(in: fresh.others[index].image)
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
            } catch ScreenCaptureError.permissionDenied {
                guard !Task.isCancelled else { return }
                phase = .needsPermission
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Vision is CPU-heavy enough to stall the panel's appearance if it runs
    /// inline, so each display is recognized off the main actor.
    private static func readText(in image: CGImage) async -> String {
        await Task.detached { TextRecognizer.recognize(in: image) }.value
    }

    /// Retries after the user grants permission, so they don't have to guess
    /// whether it took effect.
    func retryCapture(frontmostApp: NSRunningApplication?) {
        captureScreen(frontmostApp: frontmostApp)
    }

    /// Ready-made questions for the two things worth asking about a region.
    /// Typing "explain this" every time is friction on the most common action.
    enum Preset: String, CaseIterable, Identifiable {
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

    func ask(_ preset: Preset) {
        question = preset.question
        submit()
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
            updated.primary.recognizedText = await Self.readText(in: narrowed.primary.image)
            observation = updated
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

        // Stated before anything can go wrong, so a failure that arrives later
        // replaces a visible "starting" rather than appearing out of nowhere.
        phase = .startingDictation

        Task {
            onListeningBegan?()
            do {
                try await dictation.start(
                    onTranscript: { [weak self] text in
                        self?.question = text
                        self?.dictationHint = ""
                    },
                    onEnd: { [weak self] in self?.endListening() },
                    onSilence: { [weak self] device in
                        self?.dictationHint =
                            "No sound from “\(device)”. Pick a different mic in System Settings → Sound → Input."
                    }
                )
                isListening = dictation.isListening
                dictationIsOnDevice = dictation.isOnDevice
                inputDeviceName = dictation.inputDeviceName
                if phase == .startingDictation { phase = .idle }
                if !isListening { endListening() }
            } catch {
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

    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        if let url { NSWorkspace.shared.open(url) }
    }

    func submit() {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isBusy else { return }

        answerTask?.cancel()
        answer = ""
        phase = .thinking

        let brain = makeBrain()
        let context = AskContext(
            observation: observation,
            memories: ContextRetriever.promptLines(for: related),
            tasks: taskLines(),
            includeImage: AppSettings.sendsImage
        )

        answerTask = Task {
            do {
                let stream = brain.answerStream(question: prompt, context: context)
                for try await chunk in stream {
                    if Task.isCancelled { return }
                    answer += chunk
                    if phase != .answering { phase = .answering }
                }
                if !Task.isCancelled { phase = .idle }
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Persists the current screen with whatever the user typed as the reason.
    /// The typed text is the record's intent; `#tags` inside it become topics.
    func saveCurrentContext() {
        guard let observation else {
            phase = .failed("Nothing captured yet.")
            return
        }

        let raw = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
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
        let raw = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
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
            reminderIsArmed = fresh.wasExplicitlyRequested
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
            else { return }
            record.aiSummary = summary
            try? modelContext.save()
        }
    }

    func reset() {
        captureTask?.cancel()
        answerTask?.cancel()
        if isListening {
            dictation.stop()
            endListening()
        }
        question = ""
        answer = ""
        observation = nil
        related = []
        phase = .idle
        contextLabel = "Nothing captured yet"
        reminderSuggestion = nil
        reminderDate = nil
        reminderIsArmed = false
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
