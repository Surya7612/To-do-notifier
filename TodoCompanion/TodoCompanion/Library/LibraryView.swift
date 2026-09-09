import SwiftData
import SwiftUI

struct LibraryView: View {
    @Query(sort: \SavedContext.createdAt, order: .reverse)
    private var contexts: [SavedContext]

    @Query(sort: \Project.name)
    private var projects: [Project]

    @Environment(\.modelContext) private var modelContext

    @State private var search = ""
    @State private var selection: SavedContext?
    @State private var scope: Scope = .everything
    @State private var isNamingProject = false
    @State private var isRenamingProject = false
    @State private var projectName = ""

    /// The other app's tasks, re-read whenever the shown project changes. It
    /// owns that file and can change it while this window is open.
    @State private var work = LinkedWork()

    /// Saves that match the query by meaning. Held as identifiers rather than
    /// models so a store change cannot leave this holding stale objects.
    @State private var semanticMatchIDs: [PersistentIdentifier] = []

    /// Whether the detail pane is showing the graph instead of one save.
    @State private var isShowingGraph = false

    /// Which slice of the library the sidebar is showing.
    private enum Scope: Hashable {
        case everything
        case project(String)
        case unfiled
    }

    private var inScope: [SavedContext] {
        switch scope {
        case .everything:
            return contexts
        case .unfiled:
            return contexts.filter { $0.project == nil }
        case let .project(identifier):
            return contexts.filter { $0.project?.identifier == identifier }
        }
    }

    /// Literal matches first, then anything that only matches by meaning.
    ///
    /// Ordered that way deliberately: a save containing the words the user
    /// typed is not a guess, and should never be pushed below a resemblance.
    /// The meaning-only matches are appended and labelled, so the list never
    /// silently reorders itself around a score nobody can see.
    private var filtered: [SavedContext] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return inScope }

        let literal = inScope.filter {
            $0.searchHaystack.localizedCaseInsensitiveContains(term)
        }

        guard !semanticMatchIDs.isEmpty else { return literal }

        let alreadyFound = Set(literal.map(\.persistentModelID))
        let byMeaning = semanticMatchIDs
            .filter { !alreadyFound.contains($0) }
            .compactMap { id in inScope.first { $0.persistentModelID == id } }

        return literal + byMeaning
    }

    /// True for a row that is only in the list because of what it means.
    private func isMeaningOnlyMatch(_ context: SavedContext) -> Bool {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, semanticMatchIDs.contains(context.persistentModelID) else {
            return false
        }
        return !context.searchHaystack.localizedCaseInsensitiveContains(term)
    }

    /// Embeds the query and ranks saves against it.
    ///
    /// Debounced because this fires per keystroke and each run is a round trip
    /// to a local model. Short queries are skipped: two or three characters
    /// embed to something close to nothing in particular, and matching on that
    /// produces confident-looking nonsense.
    private func refreshSemanticMatches() async {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppSettings.semanticEnabled, term.count >= 4 else {
            semanticMatchIDs = []
            return
        }

        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        let brain = OllamaBrain(endpoint: AppSettings.endpoint, model: AppSettings.model)
        let embeddingModel = AppSettings.embeddingModel
        let prepared = Embedding.prepared(term, as: .query, for: embeddingModel)
        guard let vector = try? await brain.embed(prepared, model: embeddingModel) else {
            semanticMatchIDs = []
            return
        }
        guard !Task.isCancelled else { return }

        semanticMatchIDs = ContextRetriever.matching(vector, among: contexts).map {
            $0.context.persistentModelID
        }
    }

    private var scopeTitle: String {
        switch scope {
        case .everything: return "Everything"
        case .unfiled: return "No project"
        case let .project(identifier):
            return projects.first { $0.identifier == identifier }?.name ?? "Project"
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                scopePicker
                Divider()
                list
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if isShowingGraph {
                GraphView(contexts: inScope) { identifier in
                    // Tapping a save in the graph is a way of navigating to it,
                    // so it leaves the graph rather than selecting invisibly
                    // behind it.
                    if let match = contexts.first(where: { $0.reminderIdentifier == identifier }) {
                        selection = match
                        isShowingGraph = false
                    }
                }
            } else if let selection {
                ContextDetailView(context: selection, quietHours: work.quietHours)
            } else if case let .project(identifier) = scope,
                      let project = projects.first(where: { $0.identifier == identifier }) {
                ProjectOverview(project: project, work: work)
            } else {
                ContentUnavailableView(
                    "Nothing selected",
                    systemImage: "sidebar.left",
                    description: Text("Pick something you kept to see why you kept it.")
                )
            }
        }
        // The library is where someone goes to look at what they kept, so it is
        // the wrong place to be told to summon the panel first. Opening this
        // window is as much a user-initiated moment as a summon is, which is
        // what keeps this from being the background collection the app avoids.
        .task { InboxImporter.importAll(into: modelContext) }
        .task(id: scope) { work = TodoBridge.load() }
        .task(id: search) { await refreshSemanticMatches() }
        .searchable(text: $search, placement: .sidebar, prompt: "Search reasons, screen text, apps")
        .frame(minWidth: 820, minHeight: 520)
        .toolbar {
            ToolbarItem {
                Button {
                    isShowingGraph.toggle()
                } label: {
                    Label("Connections", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .help("See how projects, topics and apps connect what you kept")
            }
            ToolbarItem {
                Menu {
                    Button("New project…") { isNamingProject = true }
                    if case let .project(identifier) = scope,
                       let project = projects.first(where: { $0.identifier == identifier }) {
                        Divider()
                        Button("Rename \(project.name)…") {
                            projectName = project.name
                            isRenamingProject = true
                        }
                        // Saves survive: the relationship nullifies rather than
                        // cascading, so deleting a project unfiles its contents
                        // instead of destroying them.
                        Button("Delete \(project.name)", role: .destructive) {
                            delete(project)
                        }
                    }
                } label: {
                    Label("Projects", systemImage: "folder.badge.gearshape")
                }
            }
        }
        .alert("New project", isPresented: $isNamingProject) {
            TextField("Name", text: $projectName)
            Button("Cancel", role: .cancel) { projectName = "" }
            Button("Create") { createProject() }
        }
        .alert("Rename project", isPresented: $isRenamingProject) {
            TextField("Name", text: $projectName)
            Button("Cancel", role: .cancel) { projectName = "" }
            Button("Rename") { renameCurrentProject() }
        }
    }

    private func createProject() {
        let name = Project.normalize(projectName)
        projectName = ""
        guard !name.isEmpty,
              !projects.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { return }

        let project = Project(name: name)
        modelContext.insert(project)
        try? modelContext.save()
        scope = .project(project.identifier)
    }

    private func renameCurrentProject() {
        let name = Project.normalize(projectName)
        projectName = ""
        guard !name.isEmpty,
              case let .project(identifier) = scope,
              let project = projects.first(where: { $0.identifier == identifier })
        else { return }

        project.name = name
        try? modelContext.save()
    }

    private func delete(_ project: Project) {
        // The panel remembers a project by identifier, so a stale selection
        // would otherwise keep pointing at something gone.
        if AppSettings.currentProjectID == project.identifier {
            AppSettings.currentProjectID = nil
        }
        scope = .everything
        modelContext.delete(project)
        try? modelContext.save()
    }

    /// Projects live above the list rather than as a second sidebar column: with
    /// a handful of projects a whole column is mostly empty space.
    private var scopePicker: some View {
        HStack(spacing: DS.Spacing.tight) {
            Picker("Show", selection: $scope) {
                Text("Everything (\(contexts.count))").tag(Scope.everything)
                ForEach(projects) { project in
                    Text("\(project.name) (\(project.contexts.count))")
                        .tag(Scope.project(project.identifier))
                }
                let unfiled = contexts.count { $0.project == nil }
                if unfiled > 0 {
                    Text("No project (\(unfiled))").tag(Scope.unfiled)
                }
            }
            .labelsHidden()
        }
        .padding(.horizontal, DS.Spacing.normal)
        .padding(.vertical, DS.Spacing.tight)
    }

    @ViewBuilder
    private var list: some View {
        if contexts.isEmpty {
            ContentUnavailableView(
                "No saved context yet",
                systemImage: "bookmark",
                description: Text("Press \(AppSettings.hotkey.displayName), type why a screen matters, then ⌘S.")
            )
        } else if filtered.isEmpty, !search.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: search)
        } else if filtered.isEmpty {
            ContentUnavailableView(
                "Nothing in \(scopeTitle)",
                systemImage: "folder",
                description: Text("Pick this project in the panel before saving, or move something here.")
            )
        } else {
            List(filtered, id: \.persistentModelID, selection: $selection) { context in
                NavigationLink(value: context) {
                    LibraryRow(context: context,
                               matchedByMeaningOnly: isMeaningOnlyMatch(context))
                }
                .tag(context)
            }
            .listStyle(.sidebar)
            .navigationDestination(for: SavedContext.self) {
                ContextDetailView(context: $0, quietHours: work.quietHours)
            }
        }
    }
}

/// A project seen whole: what the user kept, and what they still have to do.
///
/// The tasks come from the To-Do Notifier and are only ever read. Which tasks
/// belong to a project is this app's own idea, so it is stored here rather than
/// written back into a file another app owns.
private struct ProjectOverview: View {
    let project: Project
    let work: LinkedWork

    @Environment(\.modelContext) private var modelContext
    @State private var isPickingTasks = false

    private var linked: [LinkedTodo] { work.todos(withIDs: project.linkedTodoIDs) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(project.name)
                    .font(.largeTitle.weight(.semibold))

                tasksSection
                keptSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Still to do")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Spacer()
                Button("Choose tasks…") { isPickingTasks = true }
                    .font(.caption)
                    .disabled(work.todos.isEmpty)
            }

            if !TodoBridge.isLinked {
                Text("Link your To-Do Notifier data in Settings to see tasks here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if linked.isEmpty {
                Text("No tasks assigned to this project yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(linked) { todo in
                    HStack(spacing: 8) {
                        Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(todo.isDone ? Color.secondary : DS.Status.ready)
                        Text(todo.title)
                            .strikethrough(todo.isDone)
                            .foregroundStyle(todo.isDone ? .secondary : .primary)
                        if let due = todo.dueAt {
                            Text(due.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(todo.isOverdue ? DS.Status.problem : Color.secondary)
                        }
                    }
                    .font(.callout)
                }

                // Completing a task belongs in the app that owns tasks.
                Text("Tick these off in the To-Do Notifier — this view only reads them.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .popover(isPresented: $isPickingTasks, arrowEdge: .bottom) {
            taskPicker
        }
    }

    private var taskPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tasks in \(project.name)")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(work.todos) { todo in
                        Toggle(isOn: binding(for: todo)) {
                            Text(todo.title).lineLimit(1)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(width: 320, height: 260)
        }
        .padding(DS.Spacing.normal)
    }

    private func binding(for todo: LinkedTodo) -> Binding<Bool> {
        Binding(
            get: { project.linkedTodoIDs.contains(todo.id) },
            set: { isOn in
                if isOn {
                    guard !project.linkedTodoIDs.contains(todo.id) else { return }
                    project.linkedTodoIDs.append(todo.id)
                } else {
                    project.linkedTodoIDs.removeAll { $0 == todo.id }
                }
                try? modelContext.save()
            }
        )
    }

    @ViewBuilder
    private var keptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kept for this project")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            if project.contexts.isEmpty {
                Text("Choose this project in the panel before saving a screen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(project.contexts.sorted { $0.createdAt > $1.createdAt },
                        id: \.persistentModelID) { context in
                    LibraryRow(context: context)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LibraryRow: View {
    let context: SavedContext

    /// Set when the row is in the list only because of what it means, not
    /// because it contains the words typed. Said out loud so a result that
    /// looks unrelated is explained rather than merely puzzling.
    var matchedByMeaningOnly = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(context.intent)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                if matchedByMeaningOnly {
                    Label("close in meaning", systemImage: "wand.and.sparkles")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: DS.Spacing.hair) {
                    if let project = context.project {
                        Label(project.name, systemImage: "folder.fill")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                    }
                    Text(context.provenanceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(context.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if context.hasPendingReminder, let remindAt = context.remindAt {
                    Label(CompanionViewModel.reminderFormat(remindAt), systemImage: "bell.fill")
                        .font(.caption2)
                        .foregroundStyle(DS.Status.saved)
                }
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = context.imageData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 52, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: 52, height: 34)
        }
    }
}

private struct ContextDetailView: View {
    let context: SavedContext

    /// The other app owns the do-not-disturb window, so a reminder set here is
    /// moved out of it exactly as one set from the panel is.
    var quietHours = QuietHours()

    @Query(sort: \Project.name) private var projects: [Project]
    @Environment(\.modelContext) private var modelContext
    @State private var showingFullText = false
    @State private var reminderProblem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let data = context.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.separator, lineWidth: 1)
                        )
                }

                section("Why I kept this") {
                    Text(context.intent)
                        .font(.body)
                        .textSelection(.enabled)
                }

                section("Project") {
                    Picker("Project", selection: projectBinding) {
                        Text("No project").tag(nil as String?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.identifier as String?)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                if !context.topics.isEmpty {
                    section("Topics") {
                        HStack(spacing: 6) {
                            ForEach(context.topics, id: \.self) { topic in
                                Text("#\(topic)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                }

                if !context.aiSummary.isEmpty {
                    section("What the model thinks it shows") {
                        Text(context.aiSummary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if !context.conversation.isEmpty {
                    section("What you asked about it") {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(context.orderedConversation) { turn in
                                VStack(alignment: .leading, spacing: 3) {
                                    // Attributed on both sides, because a
                                    // transcript is the one place the user's
                                    // words and the model's sit together.
                                    Text(turn.question)
                                        .font(.callout.weight(.medium))
                                    Text(turn.answer)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                section("Reminder") {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 10) {
                            if let remindAt = context.remindAt {
                                Label(CompanionViewModel.reminderFormat(remindAt),
                                      systemImage: context.hasPendingReminder ? "bell.fill" : "bell.slash")
                                    .font(.callout)
                                    .foregroundStyle(context.hasPendingReminder ? DS.Status.saved : Color.secondary)

                                if !context.hasPendingReminder {
                                    Text("already passed")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            } else {
                                Text("None set")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            Menu(context.remindAt == nil ? "Set" : "Change") {
                                ForEach(ReminderPreset.allCases) { preset in
                                    Button(preset.rawValue) { setReminder(preset) }
                                }
                            }
                            .menuStyle(.button)
                            .buttonStyle(.borderless)
                            .fixedSize()

                            if context.hasPendingReminder {
                                Button("Cancel") {
                                    Reminders.cancel(id: context.reminderIdentifier)
                                    context.remindAt = nil
                                    reminderProblem = nil
                                    try? modelContext.save()
                                }
                                .font(.caption)
                            }
                        }

                        if let reminderProblem {
                            Text(reminderProblem)
                                .font(.caption)
                                .foregroundStyle(Color.orange)
                        }
                    }
                }

                section("Where it came from") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.provenanceLabel)
                        Text(context.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }

                if !context.recognizedText.isEmpty {
                    section("Text read from the screen") {
                        DisclosureGroup(isExpanded: $showingFullText) {
                            Text(context.recognizedText)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Text("\(context.recognizedText.count) characters")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    // Otherwise the notification still fires for something the
                    // user has deleted, and nothing can cancel it afterwards.
                    Reminders.cancel(id: context.reminderIdentifier)
                    modelContext.delete(context)
                    try? modelContext.save()
                } label: {
                    Label("Forget", systemImage: "trash")
                }
                .help("Delete this saved context")
            }
        }
    }

    /// Arms a reminder on something already kept.
    ///
    /// Scheduled before it is stored, not after: a reminder that was silently
    /// never set is worse than one that was never offered, so a refused
    /// notification permission has to leave the record alone and say so.
    private func setReminder(_ preset: ReminderPreset) {
        guard let chosen = preset.date() else { return }
        let date = quietHours.firstMomentAfter(chosen)

        Task {
            // No cancel first: adding a request under an identifier that
            // already has one replaces it. Cancelling would only open a window
            // in which a failed reschedule leaves the record claiming a
            // reminder that no longer exists.
            let scheduled = await Reminders.schedule(id: context.reminderIdentifier,
                                                     at: date,
                                                     intent: context.intent,
                                                     sourceApp: context.sourceApp)
            guard scheduled else {
                reminderProblem = "Notifications are off for \(Prompt.assistantName) in System Settings."
                return
            }

            context.remindAt = date
            reminderProblem = nil
            try? modelContext.save()
        }
    }

    /// Bound by identifier rather than by `Project` so the picker does not need
    /// the model objects to be `Hashable` in a way SwiftData does not promise.
    private var projectBinding: Binding<String?> {
        Binding(
            get: { context.project?.identifier },
            set: { identifier in
                context.project = projects.first { $0.identifier == identifier }
                try? modelContext.save()
            }
        )
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
