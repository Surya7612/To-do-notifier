import SwiftData
import SwiftUI

struct LibraryView: View {
    @Query(sort: \SavedContext.createdAt, order: .reverse)
    private var contexts: [SavedContext]

    @Environment(\.modelContext) private var modelContext

    @State private var search = ""
    @State private var selection: SavedContext?

    private var filtered: [SavedContext] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return contexts }
        return contexts.filter {
            $0.searchHaystack.localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        NavigationSplitView {
            list
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
    }

    @ViewBuilder
    private var list: some View {
        if contexts.isEmpty {
            ContentUnavailableView(
                "No saved context yet",
                systemImage: "bookmark",
                description: Text("Press \(GlobalHotkey.defaultDisplayName), type why a screen matters, then ⌘S.")
            )
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: search)
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
                Text(context.provenanceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(context.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
                    modelContext.delete(context)
                    try? modelContext.save()
                } label: {
                    Label("Forget", systemImage: "trash")
                }
                .help("Delete this saved context")
            }
        }
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
