import AppKit
import SwiftUI

struct CompanionView: View {
    @Bindable var viewModel: CompanionViewModel
    let onClose: () -> Void
    let onRetry: () -> Void
    let onSelectRegion: () -> Void
    let onClearRegion: () -> Void
    let onLookAgain: () -> Void

    @FocusState private var questionFocused: Bool
    @State private var isNamingProject = false
    @State private var newProjectName = ""

    /// Read here rather than through the view model so flipping either one
    /// redraws the badge immediately. The model re-reads both when a question
    /// is actually sent, so a switch applies to the very next ask.
    @AppStorage(AppSettings.Key.provider) private var provider = AppSettings.Provider.ollama.rawValue
    @AppStorage(AppSettings.Key.sendsImage) private var sendsImage = false

    /// Both drive the follow-along control offered beside "Show me", so
    /// flipping either one redraws the row rather than waiting for the next
    /// answer.
    @AppStorage(AppSettings.Key.speaksAnswers) private var speaksAnswers = false
    @AppStorage(AppSettings.Key.followsAlongWhileSpeaking) private var followsAlongWhileSpeaking = false

    /// Observed but never read, purely so that changing a model in Settings
    /// while the panel is open invalidates this view. The badge keeps taking its
    /// text from `viewModel.destination`, which derives it from the same facts
    /// `makeBrain()` uses; recomputing it here instead would let the badge and
    /// the answering model drift apart, which is the bug `AnswerDestination`
    /// exists to prevent. Without these the label stayed on the old model until
    /// some unrelated change forced a redraw.
    @AppStorage(AppSettings.Key.openAIModel) private var observedCloudModel = ""
    @AppStorage(AppSettings.Key.model) private var observedLocalModel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.normal) {
            header
            if viewModel.phase == .needsPermission {
                permissionNotice
            } else {
                askField
                actionRow
                if viewModel.canSave {
                    saveOptionsRow
                }
                if !viewModel.related.isEmpty {
                    relatedStrip
                }
            }
            Divider().opacity(DS.Alpha.divider)
            answerArea
        }
        .padding(DS.Spacing.roomy)
        .frame(width: DS.Size.panelWidth, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .strokeBorder(.white.opacity(DS.Alpha.hairline), lineWidth: 1)
        )
        .onAppear {
            questionFocused = true
            viewModel.refreshCloudKey()
        }
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.tight) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(viewModel.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: DS.Spacing.tight)
            if viewModel.speech.isSpeaking {
                Button {
                    viewModel.speech.stop()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Status.listening)
                .help("Stop reading aloud")
                .transition(.opacity)
            }
            if !viewModel.turns.isEmpty {
                Button {
                    viewModel.startNewConversation()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear this conversation (⌘K)")
                .keyboardShortcut("k", modifiers: .command)
            }
            fileBadge
            destinationBadge
            Button {
                viewModel.isPinned.toggle()
            } label: {
                Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.isPinned ? DS.Pointer.mark : Color.secondary)
            .help(viewModel.isPinned
                  ? "Unpin — the panel will close again when you click away"
                  : "Pin the panel so it stays put while you work (⌘T)")
            .keyboardShortcut("t", modifiers: .command)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var askField: some View {
        HStack(spacing: DS.Spacing.tight) {
            TextField("Ask, or say why this matters…", text: $viewModel.question, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .focused($questionFocused)
                .onSubmit(viewModel.submit)

            Button(action: viewModel.toggleDictation) {
                Image(systemName: viewModel.isListening ? "mic.fill" : "mic")
                    .font(.title3)
                    .foregroundStyle(viewModel.isListening ? .pink : .primary)
                    .symbolEffect(.variableColor.iterative, isActive: viewModel.isListening)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("d", modifiers: .command)
            .help(viewModel.isListening ? "Stop dictating (⌘D)" : "Dictate instead of typing (⌘D)")

            Button {
                viewModel.saveCurrentContext()
            } label: {
                Image(systemName: "bookmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("s", modifiers: .command)
            .help("Remember this screen with your reason (⌘S)")
            .disabled(!viewModel.canSave)

            Button(action: viewModel.submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Ask about this screen (Return)")
            .disabled(isFieldEmpty || viewModel.isBusy)
        }
        .padding(.horizontal, DS.Spacing.normal)
        .padding(.vertical, DS.Spacing.snug)
        .background(.quaternary.opacity(DS.Alpha.fieldFill), in: Capsule())
    }

    private var isFieldEmpty: Bool {
        viewModel.question.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// What saving will actually do — which project this joins, and whether it
    /// comes back. Shown only once something has been typed, so the common path
    /// of ask-and-read stays uncluttered.
    private var saveOptionsRow: some View {
        HStack(spacing: DS.Spacing.tight) {
            projectPicker
            if viewModel.reminderSuggestion != nil {
                Divider().frame(height: 14)
                reminderControls
            }
            Spacer(minLength: DS.Spacing.hair)
        }
        .font(.caption)
        .padding(.horizontal, DS.Spacing.normal)
        .padding(.vertical, DS.Spacing.snug)
        .background(.quaternary.opacity(DS.Alpha.fieldFill),
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private var projectPicker: some View {
        Menu {
            Button("No project") { viewModel.chooseProject(nil) }
            if !viewModel.projects.isEmpty {
                Divider()
                ForEach(viewModel.projects) { project in
                    Button(project.name) { viewModel.chooseProject(project) }
                }
            }
            Divider()
            Button("New project…") { isNamingProject = true }
        } label: {
            Label(viewModel.currentProject?.name ?? "No project",
                  systemImage: viewModel.currentProject == nil ? "folder" : "folder.fill")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .help("Which project this save belongs to")
        .popover(isPresented: $isNamingProject) {
            newProjectField
        }
    }

    private var newProjectField: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            Text("Name this project")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Engram", text: $newProjectName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit(commitNewProject)
            HStack {
                Spacer()
                Button("Create", action: commitNewProject)
                    .buttonStyle(.borderedProminent)
                    .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DS.Spacing.normal)
    }

    private func commitNewProject() {
        viewModel.createProject(named: newProjectName)
        newProjectName = ""
        isNamingProject = false
    }

    /// The time is always shown rather than applied quietly, and the toggle
    /// starts off unless the user actually used the words "remind me" — reading
    /// a date out of their sentence is inference, and inference here gets to
    /// suggest but not to act.
    @ViewBuilder
    private var reminderControls: some View {
        if let suggestion = viewModel.reminderSuggestion, let date = viewModel.effectiveReminderDate {
            Toggle(isOn: $viewModel.reminderIsArmed) {
                Label(
                    CompanionViewModel.reminderFormat(date),
                    systemImage: viewModel.reminderIsArmed ? "bell.fill" : "bell"
                )
            }
            .toggleStyle(.checkbox)
            .fixedSize()
            .help("Set a reminder for this when you save it")

            if viewModel.reminderIsDeferredByQuietHours {
                Text("after quiet hours")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else if let matched = suggestion.matchedText, !matched.isEmpty {
                // Says which words produced the time, so an odd guess is
                // traceable to what was typed instead of looking arbitrary.
                Text("from “\(matched)”")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Menu("Change") {
                ForEach(ReminderPreset.allCases) { preset in
                    Button(preset.rawValue) { viewModel.chooseReminder(preset) }
                }
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
        }
    }

    /// Region selection and the two questions worth a shortcut, plus a standing
    /// statement of where answers come from.
    private var actionRow: some View {
        HStack(spacing: DS.Spacing.hair) {
            Button {
                onSelectRegion()
            } label: {
                Label(viewModel.hasRegion ? "Region" : "Select region",
                      systemImage: viewModel.hasRegion ? "crop" : "rectangle.dashed")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Drag out part of the screen to ask about (⌘R)")

            if viewModel.hasRegion {
                Button {
                    onClearRegion()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Back to the whole screen")
            }

            // Only once there is a conversation to continue, so the row is not
            // crowded with a control that cannot do anything yet.
            if !viewModel.turns.isEmpty {
                Button {
                    onLookAgain()
                } label: {
                    Label("Look again", systemImage: "arrow.clockwise.circle")
                }
                .disabled(viewModel.isBusy)
                .help("Capture the screen again and keep this conversation (⌘L)")
                .keyboardShortcut("l", modifiers: .command)
            }

            Spacer(minLength: DS.Spacing.hair)

            ForEach(CompanionViewModel.Preset.allCases) { preset in
                Button {
                    viewModel.ask(preset)
                } label: {
                    Label(preset.buttonLabel, systemImage: preset.glyph)
                }
                .disabled(!viewModel.hasCapture || viewModel.isBusy)
                .help(viewModel.presetWouldAskTypedText
                      ? "Asks what you typed — your words are used, not this preset"
                      : (preset == .guidedTeach
                         ? "Teach with boxes and move the pointer to each step as it is spoken"
                         : preset.question))
            }
        }
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
        .font(.caption)
        // Without this the row silently compresses its buttons to illegible
        // slivers instead of asking the panel for the width it needs.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The one file Max may propose changes to, and the control for choosing it.
    ///
    /// Deliberately a visible, standing statement rather than a transient
    /// picker: while a file is open, every answer is given with its contents in
    /// the prompt, and the user should never have to wonder whether that is
    /// still true.
    private var fileBadge: some View {
        Menu {
            if viewModel.editableFile.isOpen {
                Text(viewModel.editableFile.name)
                Divider()
                Button("Choose a different file…") { viewModel.openFileToEdit() }
                if viewModel.editableFile.canRevert {
                    Button("Revert my last applied change") { viewModel.revertAppliedEdit() }
                }
                Button("Stop working on this file") { viewModel.closeEditableFile() }
            } else {
                Button("Open a file to work on…") { viewModel.openFileToEdit() }
                Divider()
                Text("Max can propose a change to one file. You always see a diff first.")
            }
        } label: {
            Label(viewModel.editableFile.isOpen ? viewModel.editableFile.name : "No file",
                  systemImage: viewModel.editableFile.isOpen ? "doc.text.fill" : "doc")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .font(.caption2)
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(viewModel.editableFile.isOpen ? DS.Status.saved : Color.secondary)
    }

    /// Says plainly whether asking will send the screen off this Mac. A
    /// question that leaves the device must never look like one that does not.
    ///
    /// A control rather than a label because the choice is per-question in
    /// practice: the local model reads text back fine, and is worth leaving for
    /// a diagram or an unfamiliar interface. Sending someone to a settings
    /// window mid-question guarantees they never switch — and the click that
    /// opens it dismisses the panel.
    private var destinationBadge: some View {
        Menu {
            Picker("Answer with", selection: $provider) {
                ForEach(AppSettings.Provider.allCases) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }
            .pickerStyle(.inline)

            Divider()

            // The setting that decides whether a visual question can be
            // answered at all: OpenAI sees the screen only if the screenshot
            // goes with it, and otherwise guesses at anything that is not text.
            Toggle("Send the screenshot", isOn: $sendsImage)

            switch viewModel.destination {
            case .cloudWithoutKey:
                Divider()
                Text("No API key saved, so \(viewModel.localModelName) is answering.")
            case .cloud where !sendsImage:
                Divider()
                Text("Sending recognized text only, so OpenAI cannot see images.")
            default:
                EmptyView()
            }

            Divider()
            SettingsLink { Text("Settings…") }
        } label: {
            Label(viewModel.destination.label, systemImage: viewModel.destination.glyph)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .font(.caption2)
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(badgeColor)
        .help(viewModel.destination.explanation(localModel: viewModel.localModelName))
        // Keychain reads are cached in the view model, so a provider change has
        // to prompt a re-read; otherwise adding a key never takes effect until
        // the next summon.
        .onChange(of: provider) { viewModel.refreshCloudKey() }
    }

    /// A choice that is not being honoured is neither reassuring nor a warning
    /// about egress — it is a problem, and reads as one.
    private var badgeColor: Color {
        switch viewModel.destination {
        case .local: return .secondary
        case .cloud: return DS.Status.busy
        case .cloudWithoutKey: return DS.Status.problem
        }
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.snug) {
            Text("macOS won't let me read the screen yet.")
                .font(.callout.weight(.medium))

            Text("If TodoCompanion already looks enabled in the list, remove it with the “−” button and add it back, then relaunch. macOS caches the old answer until the entry is re-added.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DS.Spacing.tight) {
                Button("Open System Settings", action: viewModel.openScreenRecordingSettings)
                Button("Try again") { onRetry() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, DS.Spacing.normal)
        .padding(.vertical, DS.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(DS.Alpha.noticeFill), in: RoundedRectangle(cornerRadius: DS.Radius.card))
    }

    /// Surfaced only on an explicit summon — never from background polling.
    private var relatedStrip: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.hair) {
            Label("You kept this before", systemImage: "clock.arrow.circlepath")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)

            ForEach(viewModel.related) { match in
                VStack(alignment: .leading, spacing: 1) {
                    Text(match.context.intent)
                        .font(.caption)
                        .lineLimit(2)
                    Text("\(match.reason) · \(match.context.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Spacing.snug)
                .padding(.vertical, DS.Spacing.hair)
                .background(.quaternary.opacity(DS.Alpha.chipFill), in: RoundedRectangle(cornerRadius: DS.Radius.chip))
            }
        }
    }

    /// Grows with the answer instead of reserving a fixed block: a two-line
    /// reply under half a panel of empty material reads as a rendering fault.
    /// Long answers scroll rather than pushing the panel off the screen.
    @ViewBuilder
    private var answerArea: some View {
        ScrollViewReader { scroller in
            ScrollView {
                if viewModel.turns.isEmpty {
                    Text(placeholder)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: DS.Spacing.normal) {
                        ForEach(viewModel.turns) { turn in
                            turnView(turn)
                        }
                        if viewModel.lesson != nil {
                            lessonBar
                        } else if let target = viewModel.pointerTarget {
                            // Not both: a lesson is already boxing what its
                            // current step names, so offering to box one more
                            // thing on a button is a second claim about the
                            // same screen.
                            pointerRow(target)
                        }
                        if let edit = viewModel.proposedEdit {
                            diffView(edit)
                        }
                        // Anchored so a streaming answer keeps its own tail in
                        // view instead of scrolling off the bottom.
                        Color.clear.frame(height: 1).id(bottomAnchor)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: DS.Size.maxAnswerHeight)
            .onChange(of: viewModel.turns.last?.answer) {
                withAnimation(.easeOut(duration: 0.15)) {
                    scroller.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    private var bottomAnchor: String { "conversation-bottom" }

    /// One exchange. The user's words and Max's are visually distinct because
    /// the whole app rests on that distinction being obvious.
    private func turnView(_ turn: Turn) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.hair) {
            Text(turn.question)
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)

            if turn.answer.isEmpty {
                Text("…")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                answerBody(turn.answer)
            }
        }
    }

    /// Max's reply, drawn according to what is in it.
    ///
    /// Re-parsed on every streamed chunk rather than incrementally, because the
    /// text is a few hundred characters and the alternative is keeping a parser
    /// and a view in agreement about a half-written document.
    private func answerBody(_ answer: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            ForEach(Array(AnswerContent.blocks(in: answer).enumerated()), id: \.offset) { _, block in
                switch block {
                case let .heading(text):
                    Text(AnswerContent.styled(text))
                        .font(.callout.weight(.semibold))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                case let .paragraph(text):
                    prose(text)

                case let .bulleted(items):
                    listView(items.enumerated().map {
                        AnswerListRow(id: $0.offset, marker: "•", text: $0.element)
                    })

                case let .numbered(items):
                    listView(items.enumerated().map {
                        AnswerListRow(id: $0.offset, marker: "\($0.offset + 1).", text: $0.element)
                    })

                case let .code(code):
                    CodeBlockView(code: code)
                }
            }
        }
    }

    /// Max's words. Colour and weight live on the attributed string so quoted
    /// labels can stay bold label-colour without a view-level `.foregroundStyle`
    /// painting the whole reply — including the quotes — one flat tint.
    private func prose(_ text: String) -> some View {
        Text(AnswerContent.styled(text))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A list, with the marker in its own column so wrapped lines line up under
    /// the text rather than under the bullet.
    private func listView(_ rows: [AnswerListRow]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.hair) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.tight) {
                    Text(row.marker)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 16, alignment: .trailing)
                    prose(row.text)
                }
            }
        }
    }

    /// Offers to point at the control the answer named.
    ///
    /// The matched words are on the button rather than hidden behind it, so the
    /// user knows what is about to be boxed before anything is drawn over their
    /// screen — and can ignore it when the match is not what they meant.
    private func pointerRow(_ target: ScreenTextLocator.Match) -> some View {
        HStack(spacing: DS.Spacing.normal) {
            Button {
                viewModel.showPointerTarget()
            } label: {
                Label {
                    Text("Show me “\(target.text)”")
                        .font(.caption.weight(.semibold))
                } icon: {
                    Image(systemName: "viewfinder.rectangular")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .help(TrustAccessibility.extrasAreActive
                  ? "Box “\(target.text)” and move the pointer onto it (⌘P)"
                  : "Draw a box around “\(target.text)” on screen (⌘P)")
            .keyboardShortcut("p", modifiers: .command)

            // Offered here rather than only in Settings, where it sat under a
            // section that appears after the voice is switched on and was
            // therefore never found. This is the row where someone has just
            // seen the box work once and wonders whether it can keep up on its
            // own, which is the question the switch answers.
            if speaksAnswers { followAlongToggle }

            Spacer(minLength: 0)
        }
        .padding(.top, DS.Spacing.hair)
    }

    private var followAlongToggle: some View {
        Toggle(isOn: $followsAlongWhileSpeaking) {
            Label("Follow along",
                  systemImage: followsAlongWhileSpeaking ? "waveform.circle.fill" : "waveform")
                .font(.caption)
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .foregroundStyle(followsAlongWhileSpeaking ? DS.Pointer.mark : Color.secondary)
        .help("Move the box from control to control as \(Prompt.assistantName) reads the answer. "
              + "Only labels it quotes exactly are boxed, so nothing is drawn on a guess.")
    }

    /// The controls for walking a lesson, shown only while one is playing.
    ///
    /// The steps themselves are not repeated here — they are already drawn as
    /// the numbered list of the answer, a few points above this row. What is
    /// missing without it is a way to go at your own pace, which is the whole
    /// difference between being taught and being read to.
    private var lessonBar: some View {
        HStack(spacing: DS.Spacing.tight) {
            Image(systemName: "graduationcap.fill")
                .foregroundStyle(DS.Pointer.mark)

            Text("Step \(viewModel.lessonStep + 1) of \(viewModel.lessonStepCount)")
                .font(.caption.weight(.medium))

            Spacer(minLength: DS.Spacing.tight)

            Button { viewModel.stepLesson(by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!viewModel.canRewindLesson)
            .help("Previous step")

            Button { viewModel.stepLesson(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!viewModel.canAdvanceLesson)
            .help("Next step — reads the screen again first, in case it moved")

            Button("Done") { viewModel.endLesson() }
                .help("Take the boxes off the screen")
        }
        .font(.caption)
        .buttonStyle(.borderless)
        .padding(.horizontal, DS.Spacing.normal)
        .padding(.vertical, DS.Spacing.tight)
        .background(DS.Pointer.mark.opacity(DS.Alpha.hairline),
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    /// The change Max is proposing, shown before anything is written.
    ///
    /// Only the changed regions with a little context around them: a whole file
    /// is unreadable at this width, and the user is being asked to approve
    /// something, which they cannot do if they cannot find what changed.
    private func diffView(_ edit: CompanionViewModel.ProposedEdit) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            HStack(spacing: DS.Spacing.tight) {
                Label(edit.fileName, systemImage: "doc.text")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(edit.summary.description)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: DS.Spacing.hair)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(TextDiff.hunks(edit.lines).enumerated()), id: \.offset) { hunk in
                        if hunk.offset > 0 {
                            Text("⋯")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 2)
                        }
                        ForEach(hunk.element) { line in
                            diffLine(line)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: DS.Size.maxDiffHeight)
            .padding(DS.Spacing.tight)
            .background(.black.opacity(DS.Alpha.well), in: RoundedRectangle(cornerRadius: DS.Radius.control))

            HStack(spacing: DS.Spacing.tight) {
                Button("Apply") { viewModel.applyProposedEdit() }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                Button("Discard") { viewModel.discardProposedEdit() }
                Spacer(minLength: DS.Spacing.hair)
                Text("Nothing is written until you apply.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .controlSize(.small)
        }
        .padding(.top, DS.Spacing.hair)
    }

    private func diffLine(_ line: TextDiff.Line) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.tight) {
            Text(line.kind == .added ? "+" : line.kind == .removed ? "−" : " ")
                .font(.caption2.monospaced())
                .foregroundStyle(diffColor(line.kind))
            Text(line.text.isEmpty ? " " : line.text)
                .font(.caption2.monospaced())
                .foregroundStyle(line.kind == .unchanged ? .secondary : diffColor(line.kind))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 2)
        .background(diffColor(line.kind).opacity(line.kind == .unchanged ? 0 : DS.Alpha.diffRow))
    }

    private func diffColor(_ kind: TextDiff.Line.Kind) -> Color {
        switch kind {
        case .added: DS.Status.saved
        case .removed: DS.Status.problem
        case .unchanged: .secondary
        }
    }

    private var placeholder: String {
        switch viewModel.phase {
        case .thinking: "…"
        case let .failed(message): message
        case .saved: "Kept, with your reason attached. Find it again in the library."
        default: "Ask \(Prompt.assistantName) anything about this screen. Return asks, and you can keep asking — ⌘L looks again after the screen changes. ⌘D dictates. ⌘S remembers this screen. Esc closes."
        }
    }

    private var statusColor: Color {
        if viewModel.isListening { return DS.Status.listening }
        switch viewModel.phase {
        case .idle: return DS.Status.ready
        case .reading, .thinking, .answering, .startingDictation: return DS.Status.busy
        case .saved: return DS.Status.saved
        case .needsPermission, .failed: return DS.Status.problem
        }
    }
}

/// One line of a bulleted or numbered list.
///
/// A named type rather than a tuple because `ForEach` needs stable identity and
/// the index is the only thing available: the same step can be written twice in
/// one list.
private struct AnswerListRow: Identifiable {
    let id: Int
    let marker: String
    let text: String
}

/// A fenced code block: monospaced, on a recessed background, with the language
/// named and the whole thing copyable in one press.
///
/// Copying matters more here than it looks. The panel is a floating window over
/// whatever the user is working in, so the code in it is nearly always destined
/// for the editor behind it, and selecting monospaced text inside a scroll view
/// with the mouse is the slowest possible way to move it there.
private struct CodeBlockView: View {
    let code: AnswerContent.Code

    /// How long the button stays confirmed. Long enough to be seen after the
    /// eye has gone back to the code, which two seconds was not.
    private static let confirmationSeconds: Double = 3

    @State private var copiedAt: Date?

    private var hasCopied: Bool { copiedAt != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Spacing.tight) {
                Text(code.language?.uppercased() ?? "CODE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: DS.Spacing.hair)

                // Said out loud, because a block that is still arriving looks
                // exactly like a finished one that is missing its last lines.
                if code.isStreaming {
                    Text("writing…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    copyButton
                }
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.top, DS.Spacing.tight)
            .padding(.bottom, DS.Spacing.hair)

            Divider().opacity(DS.Alpha.divider)

            // Scrolled rather than wrapped: a wrapped line of code loses the
            // indentation that says what is nested inside what.
            ScrollView(.horizontal) {
                Text(CodeHighlighter.highlight(code.text, language: code.language))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(DS.Spacing.card)
            }
            .scrollIndicators(.never)
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.control)
                .fill(DS.Code.well)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .strokeBorder(DS.Code.border)
                )
        )
        // Driven by the timestamp rather than by a stored `Task`, so a redraw
        // in the middle of the confirmation cannot strand a cancelled timer
        // with the button left reading "Copied".
        .task(id: copiedAt) {
            guard copiedAt != nil else { return }
            try? await Task.sleep(for: .seconds(Self.confirmationSeconds))
            guard !Task.isCancelled else { return }
            copiedAt = nil
        }
    }

    /// Confirmation is a filled pill rather than a word swap.
    ///
    /// "Copy" becoming "Copied" is two grey words a few pixels apart in the
    /// corner of a panel the user is not looking at — they are looking at the
    /// code, or at the editor they are about to paste into. The shape and the
    /// colour both changing is what makes it register peripherally.
    private var copyButton: some View {
        Button(action: copy) {
            // Both labels are laid out and one is faded out, so confirming
            // cannot change the button's size. That is a hard requirement
            // rather than a neatness one: the panel sizes itself to its
            // content, so a control that grows mid-answer asks the window to
            // resize during a layout pass — see `CompanionPanel.setContentSize`.
            // Opacity and colour are the only things that move here.
            ZStack(alignment: .trailing) {
                copyLabel("Copied", systemImage: "checkmark.circle.fill")
                    .opacity(hasCopied ? 1 : 0)
                copyLabel("Copy", systemImage: "doc.on.doc")
                    .opacity(hasCopied ? 0 : 1)
            }
            .foregroundStyle(hasCopied ? DS.Status.ready : Color.secondary)
            .padding(.horizontal, DS.Spacing.hair)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip)
                    .fill(DS.Status.ready.opacity(hasCopied ? DS.Alpha.hairline : 0))
            )
        }
        .buttonStyle(.plain)
        .help("Copy this block (the panel stays open)")
        .animation(.easeOut(duration: 0.15), value: hasCopied)
    }

    private func copyLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage).font(.caption2)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code.text, forType: .string)
        copiedAt = Date()
    }
}
