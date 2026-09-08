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

    private var filtered: [SavedContext] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return inScope }
        return inScope.filter {
            $0.searchHaystack.localizedCaseInsensitiveContains(term)
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
            if let selection {
                ContextDetailView(context: selection)
            } else {
                ContentUnavailableView(
                    "Nothing selected",
                    systemImage: "sidebar.left",
                    description: Text("Pick something you kept to see why you kept it.")
                )
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search reasons, screen text, apps")
        .frame(minWidth: 820, minHeight: 520)
        .toolbar {
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
                    LibraryRow(context: context)
                }
                .tag(context)
            }
            .listStyle(.sidebar)
            .navigationDestination(for: SavedContext.self) { ContextDetailView(context: $0) }
        }
    }
}

private struct LibraryRow: View {
    let context: SavedContext

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(context.intent)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
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

    @Query(sort: \Project.name) private var projects: [Project]
    @Environment(\.modelContext) private var modelContext
    @State private var showingFullText = false

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

                if let remindAt = context.remindAt {
                    section("Reminder") {
                        HStack(spacing: 10) {
                            Label(CompanionViewModel.reminderFormat(remindAt),
                                  systemImage: context.hasPendingReminder ? "bell.fill" : "bell.slash")
                                .font(.callout)
                                .foregroundStyle(context.hasPendingReminder ? DS.Status.saved : Color.secondary)

                            if context.hasPendingReminder {
                                Button("Cancel") {
                                    Reminders.cancel(id: context.reminderIdentifier)
                                    context.remindAt = nil
                                    try? modelContext.save()
                                }
                                .font(.caption)
                            } else {
                                Text("already passed")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
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
