import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.Key.ollamaEndpoint) private var endpoint = AppSettings.defaultEndpoint
    @AppStorage(AppSettings.Key.model) private var model = AppSettings.defaultModel
    @AppStorage(AppSettings.Key.sendsImage) private var sendsImage = false
    @AppStorage(AppSettings.Key.hotkeyID) private var hotkeyID = HotkeyChoice.fallback.id
    @AppStorage(AppSettings.Key.provider) private var provider = AppSettings.Provider.ollama.rawValue
    @AppStorage(AppSettings.Key.openAIModel) private var openAIModel = OpenAIBrain.defaultModel

    /// Mirrors the Keychain rather than being stored by SwiftUI, so the secret
    /// never lands in a preferences plist.
    @State private var apiKey = ""
    @State private var keyIsStored = false
    @State private var isLinked = TodoBridge.isLinked
    @State private var linkedSummary = ""
    @State private var canImportKey = false

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
            }

            Section("On this Mac") {
                TextField("Ollama endpoint", text: $endpoint)
                TextField("Model", text: $model)
            }

            Section("OpenAI") {
                TextField("Model", text: $openAIModel)

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

            Section("Screen context") {
                Toggle("Send the screenshot instead of on-device text", isOn: $sendsImage)
                Text(sendsImage
                     ? "Needed for OpenAI to see the screen, and for local vision models such as llava or qwen2.5vl."
                     : "Screenshots stay on this Mac; only recognized text reaches the model.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear {
            keyIsStored = AppSettings.openAIKey != nil
            refreshLinkedSummary()
            canImportKey = !keyIsStored && TodoBridge.importableOpenAIKey() != nil
        }
    }

    private func refreshLinkedSummary() {
        guard TodoBridge.isLinked else { return }
        let work = TodoBridge.load()
        linkedSummary = work.isEmpty
            ? "Linked, but nothing readable in that file"
            : "\(work.openTodos.count) open tasks · \(work.notes.count) notes"
    }
}
