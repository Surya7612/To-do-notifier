import SwiftUI

struct CompanionView: View {
    @Bindable var viewModel: CompanionViewModel
    let onClose: () -> Void
    let onRetry: () -> Void
    let onSelectRegion: () -> Void
    let onClearRegion: () -> Void

    @FocusState private var questionFocused: Bool
    @State private var isNamingProject = false
    @State private var newProjectName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.normal) {
            header
            if viewModel.phase == .needsPermission {
                permissionNotice
            } else {
                askField
                actionRow
                if !isFieldEmpty {
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
        .onAppear { questionFocused = true }
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
            destinationBadge
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

            Button(action: viewModel.saveCurrentContext) {
                Image(systemName: "bookmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("s", modifiers: .command)
            .help("Remember this screen with your reason (⌘S)")
            .disabled(isFieldEmpty || !viewModel.hasCapture)

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

            Spacer(minLength: DS.Spacing.hair)

            ForEach(CompanionViewModel.Preset.allCases) { preset in
                Button {
                    viewModel.ask(preset)
                } label: {
                    Label(preset.buttonLabel, systemImage: preset.glyph)
                }
                .disabled(!viewModel.hasCapture || viewModel.isBusy)
            }
        }
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
        .font(.caption)
        // Without this the row silently compresses its buttons to illegible
        // slivers instead of asking the panel for the width it needs.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Says plainly whether asking will send the screen off this Mac. A
    /// question that leaves the device must never look like one that does not.
    private var destinationBadge: some View {
        Label(
            viewModel.answersLeaveTheMachine ? viewModel.brainLabel : "Local",
            systemImage: viewModel.answersLeaveTheMachine ? "cloud" : "lock.laptopcomputer"
        )
        .font(.caption2)
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(viewModel.answersLeaveTheMachine ? DS.Status.busy : Color.secondary)
        .help(viewModel.answersLeaveTheMachine
              ? "Your question and the captured screen go to \(viewModel.brainLabel). Saved summaries stay local."
              : "Nothing leaves this Mac.")
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
        ScrollView {
            if viewModel.answer.isEmpty {
                Text(placeholder)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(viewModel.answer)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: DS.Size.maxAnswerHeight)
    }

    private var placeholder: String {
        switch viewModel.phase {
        case .thinking: "…"
        case let .failed(message): message
        case .saved: "Kept, with your reason attached. Find it again in the library."
        default: "Return asks. ⌘D dictates. ⌘S remembers this screen. #tags become topics. Esc closes."
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
