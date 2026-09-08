import AppKit
import AVFAudio
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.Key.ollamaEndpoint) private var endpoint = AppSettings.defaultEndpoint
    @AppStorage(AppSettings.Key.model) private var model = AppSettings.defaultModel
    @AppStorage(AppSettings.Key.sendsImage) private var sendsImage = false
    @AppStorage(AppSettings.Key.hotkeyID) private var hotkeyID = HotkeyChoice.fallback.id
    @AppStorage(AppSettings.Key.provider) private var provider = AppSettings.Provider.ollama.rawValue
    @AppStorage(AppSettings.Key.openAIModel) private var openAIModel = OpenAIBrain.defaultModel
    @AppStorage(AppSettings.Key.semanticEnabled) private var semanticEnabled = false
    @AppStorage(AppSettings.Key.embeddingModel) private var embeddingModel = AppSettings.defaultEmbeddingModel
    @AppStorage(AppSettings.Key.speaksAnswers) private var speaksAnswers = false
    @AppStorage(AppSettings.Key.voiceIdentifier) private var voiceIdentifier = ""

    /// Mirrors the Keychain rather than being stored by SwiftUI, so the secret
    /// never lands in a preferences plist.
    @State private var apiKey = ""
    @State private var keyIsStored = false
    @State private var isLinked = TodoBridge.isLinked
    @State private var linkedSummary = ""
    @State private var canImportKey = false
    @State private var inboxFolder: String?
    @State private var inboxWaiting = 0

    /// Derived from the stored name on appear rather than persisted, since
    /// "custom" is a state of this window and not a preference.
    @State private var modelSelection = OpenAIModelChoice.Selection.custom

    var body: some View {
        Form {
            Section("Shortcut") {
                Picker("Summon companion", selection: $hotkeyID) {
                    ForEach(HotkeyChoice.all) { choice in
                        Text(choice.displayName).tag(choice.id)
                    }
                }
                .onChange(of: hotkeyID) { _, newValue in
                    GlobalHotkey.shared.activate(HotkeyChoice.named(newValue))
                }

                Text("These combos avoid the ones macOS reserves for itself, such as ⌘Space and ⌥⌘Space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if GlobalHotkey.shared.didFailToRegister {
                    Label("Another app already owns this shortcut. Pick a different one.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Who answers") {
                Picker("Answer questions with", selection: $provider) {
                    ForEach(AppSettings.Provider.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text(provider == AppSettings.Provider.openAI.rawValue
                     ? "Your question and the captured screen are sent to OpenAI. Saved summaries are always generated on this Mac and never sent anywhere."
                     : "Nothing leaves this Mac. Local vision models are weaker at reading interfaces, so answers about what is on screen are rougher.")
                .font(.caption)
                .foregroundStyle(.secondary)

                // Selecting a provider is not the same as being able to use it,
                // and the difference is otherwise only discoverable by noticing
                // that the answers did not improve.
                if provider == AppSettings.Provider.openAI.rawValue, !keyIsStored {
                    Label("No API key saved yet, so questions are still answered on this Mac.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("On this Mac") {
                TextField("Ollama endpoint", text: $endpoint)
                TextField("Model", text: $model)
            }

            Section("Reading answers aloud") {
                Toggle("Have \(Prompt.assistantName) read answers out loud", isOn: $speaksAnswers)

                if speaksAnswers {
                    Picker("Voice", selection: $voiceIdentifier) {
                        Text("System default").tag("")
                        ForEach(SpeechPlayback.availableVoices, id: \.identifier) { voice in
                            Text(voice.name).tag(voice.identifier)
                        }
                    }
                }

                Text("Uses the speech voices built into macOS, so nothing is sent anywhere. Speaking stops as soon as you dictate, ask something else, or close the panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Finding things by meaning") {
                Toggle("Match saved context by meaning, not just words", isOn: $semanticEnabled)

                Text(semanticEnabled
                     ? "Search and resurfacing also compare meaning, so \u{201C}screen capture\u{201D} can find a note that says \u{201C}display grabbing\u{201D}. Matches still say why they surfaced."
                     : "Search and resurfacing compare words only, so \u{201C}screen capture\u{201D} will not find a note that says \u{201C}display grabbing\u{201D}.")
                .font(.caption)
                .foregroundStyle(.secondary)

                if semanticEnabled {
                    TextField("Embedding model", text: $embeddingModel)

                    // Runs across everything kept, unprompted, which is exactly
                    // the work that must never reach a hosted provider — so it
                    // is worth stating rather than leaving to be assumed.
                    Text("Needs a second Ollama model: run `ollama pull \(embeddingModel)`. It runs on this Mac and is never sent anywhere, even when OpenAI is answering your questions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("OpenAI") {
                Picker("Model", selection: $modelSelection) {
                    ForEach(OpenAIModelChoice.all) { choice in
                        Text(choice.displayName)
                            .tag(OpenAIModelChoice.Selection.known(choice.id))
                    }
                    Divider()
                    Text("Custom…").tag(OpenAIModelChoice.Selection.custom)
                }
                .onChange(of: modelSelection) { _, newSelection in
                    // Custom deliberately leaves the stored name alone, so
                    // switching to it and back does not discard a typed one.
                    if case .known(let chosenModel) = newSelection { openAIModel = chosenModel }
                }

                if modelSelection == .custom {
                    TextField("Model name", text: $openAIModel, prompt: Text("gpt-5.6-…"))
                }

                if let choice = OpenAIModelChoice.named(openAIModel) {
                    Text("\(choice.id) — \(choice.detail)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    SecureField(keyIsStored ? "Stored in Keychain" : "sk-…", text: $apiKey)
                    Button(keyIsStored && apiKey.isEmpty ? "Remove" : "Save") {
                        if keyIsStored, apiKey.isEmpty {
                            Keychain.remove(OpenAIBrain.keychainAccount)
                            keyIsStored = false
                        } else {
                            Keychain.set(apiKey, for: OpenAIBrain.keychainAccount)
                            apiKey = ""
                            keyIsStored = AppSettings.openAIKey != nil
                        }
                    }
                    .disabled(apiKey.isEmpty && !keyIsStored)
                }

                Text("Kept in the login Keychain, not in preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Offered rather than taken. The key was given to the other app
                // for transcription, and it sits in plaintext there; importing
                // copies it somewhere safer and makes the reuse deliberate.
                if !keyIsStored, canImportKey {
                    Button("Import the key from To-Do Notifier") {
                        guard let found = TodoBridge.importableOpenAIKey() else { return }
                        Keychain.set(found, for: OpenAIBrain.keychainAccount)
                        keyIsStored = AppSettings.openAIKey != nil
                        canImportKey = false
                    }
                    Text("Your to-do app already has one saved. This copies it into the Keychain; the original stays where it is.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Your to-do app") {
                HStack {
                    Text(isLinked ? linkedSummary : "Not linked")
                        .foregroundStyle(isLinked ? .primary : .secondary)
                    Spacer()
                    Button(isLinked ? "Unlink" : "Link…") {
                        if isLinked {
                            TodoBridge.unlink()
                            isLinked = false
                            linkedSummary = ""
                        } else if TodoBridge.link() {
                            isLinked = true
                            refreshLinkedSummary()
                        }
                        canImportKey = !keyIsStored && TodoBridge.importableOpenAIKey() != nil
                    }
                }

                Text("Point this at the To-Do Notifier's app-data.json so the companion can answer using your open tasks and notes. It is only ever read, never written.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Capture from your phone") {
                HStack {
                    Text(inboxFolder ?? "Not linked")
                        .foregroundStyle(inboxFolder == nil ? .secondary : .primary)
                    Spacer()
                    Button(inboxFolder == nil ? "Choose folder…" : "Unlink") {
                        if inboxFolder == nil {
                            if InboxImporter.link() { refreshInbox() }
                        } else {
                            InboxImporter.unlink()
                            refreshInbox()
                        }
                    }
                }

                if inboxFolder != nil {
                    Text(inboxWaiting == 0
                         ? "Nothing waiting. Items are brought in when the app launches and each time you summon the panel."
                         : "\(inboxWaiting) waiting. They will be brought in on the next summon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                // Says plainly that this is not iCloud sync, because a folder in
                // iCloud Drive looks like it and behaves differently on failure.
                Text("Put the folder in iCloud Drive and an iPhone Shortcut can save into it. The folder is a transport, not storage — anything brought in is removed from it. See the README for the Shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Screen context") {
                Toggle("Send the screenshot instead of on-device text", isOn: $sendsImage)
                Text(sendsImage
                     ? "Needed for OpenAI to see the screen, and for a local vision model such as qwen3-vl."
                     : "Screenshots stay on this Mac; only recognized text reaches the model.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear {
            // An accessory app is never a normal foreground application, so
            // macOS hands this window no key focus: it draws, and it takes
            // mouse clicks on toggles and buttons, but every text field silently
            // swallows typing. The library window activates for the same reason.
            NSApp.activate(ignoringOtherApps: true)

            modelSelection = OpenAIModelChoice.selection(for: openAIModel)
            keyIsStored = AppSettings.openAIKey != nil
            refreshLinkedSummary()
            refreshInbox()
            canImportKey = !keyIsStored && TodoBridge.importableOpenAIKey() != nil
        }
    }

    private func refreshInbox() {
        inboxFolder = InboxImporter.folderName
        inboxWaiting = InboxImporter.pendingCount
    }

    private func refreshLinkedSummary() {
        guard TodoBridge.isLinked else { return }
        let work = TodoBridge.load()
        linkedSummary = work.isEmpty
            ? "Linked, but nothing readable in that file"
            : "\(work.openTodos.count) open tasks · \(work.notes.count) notes"
    }
}
