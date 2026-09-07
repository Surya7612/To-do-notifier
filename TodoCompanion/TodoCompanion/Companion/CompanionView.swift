import SwiftUI

struct CompanionView: View {
    @Bindable var viewModel: CompanionViewModel
    let onClose: () -> Void

    @FocusState private var questionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            askField
            if !viewModel.related.isEmpty {
                relatedStrip
            }
            Divider().opacity(0.35)
            answerArea
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear { questionFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(viewModel.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var askField: some View {
        HStack(spacing: 8) {
            TextField("Ask, or say why this matters…", text: $viewModel.question, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .focused($questionFocused)
                .onSubmit(viewModel.submit)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private var isFieldEmpty: Bool {
        viewModel.question.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Surfaced only on an explicit summon — never from background polling.
    private var relatedStrip: some View {
        VStack(alignment: .leading, spacing: 5) {
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
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

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
        .frame(maxHeight: .infinity)
    }

    private var placeholder: String {
        switch viewModel.phase {
        case .thinking: "…"
        case let .failed(message): message
        case .saved: "Kept, with your reason attached. Find it again in the library."
        default: "Return asks. ⌘S remembers this screen. #tags become topics. Esc closes."
        }
    }

    private var statusColor: Color {
        switch viewModel.phase {
        case .idle: .green
        case .reading, .thinking, .answering: .orange
        case .saved: .blue
        case .failed: .red
        }
    }
}
