import AppKit
import AVFAudio
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.Key.ollamaEndpoint) private var endpoint = AppSettings.defaultEndpoint
    @AppStorage(AppSettings.Key.model) private var model = AppSettings.defaultModel
    @AppStorage(AppSettings.Key.sendsImage) private var sendsImage = false
    @AppStorage(AppSettings.Key.hotkeyID) private var hotkeyID = HotkeyChoice.fallback.id
    @AppStorage(AppSettings.Key.talkHotkeyID) private var talkHotkeyID = HotkeyChoice.offIdentifier
    @AppStorage(AppSettings.Key.provider) private var provider = AppSettings.Provider.ollama.rawValue
    @AppStorage(AppSettings.Key.openAIModel) private var openAIModel = OpenAIBrain.defaultModel
    @AppStorage(AppSettings.Key.anthropicModel) private var anthropicModel = AnthropicBrain.defaultModel
    @AppStorage(AppSettings.Key.geminiModel) private var geminiModel = GeminiBrain.defaultModel
    @AppStorage(AppSettings.Key.semanticEnabled) private var semanticEnabled = false
    @AppStorage(AppSettings.Key.embeddingModel) private var embeddingModel = AppSettings.defaultEmbeddingModel
    @AppStorage(AppSettings.Key.speaksAnswers) private var speaksAnswers = false
    @AppStorage(AppSettings.Key.followsAlongWhileSpeaking) private var followsAlongWhileSpeaking = false
    @AppStorage(AppSettings.Key.guideCursorWhileTeaching) private var guideCursorWhileTeaching = false
    @AppStorage(AppSettings.Key.voiceIdentifier) private var voiceIdentifier = ""
    @AppStorage(AppSettings.Key.voiceEngine) private var voiceEngine = AppSettings.VoiceEngine.system.rawValue
    @AppStorage(AppSettings.Key.dictationEngine) private var dictationEngine =
        AppSettings.DictationEngine.apple.rawValue
    @AppStorage(AppSettings.Key.mirrorsToAppleReminders) private var mirrorsToAppleReminders = false
    @AppStorage(AppSettings.Key.accessibilityExtrasEnabled) private var accessibilityExtrasEnabled = false

    /// Mirrors the Keychain rather than being stored by SwiftUI, so the secret
    /// never lands in a preferences plist.
    @State private var openAIKeyDraft = ""
    @State private var openAIKeyStored = false
    @State private var anthropicKeyDraft = ""
    @State private var anthropicKeyStored = false
    @State private var geminiKeyDraft = ""
    @State private var geminiKeyStored = false
    @State private var isLinked = TodoBridge.isLinked
    @State private var linkedSummary = ""
    @State private var canImportKey = false
    @State private var inboxFolder: String?
    @State private var inboxWaiting = 0
    @State private var inboxProblem: String?
    @State private var mirrorDestination: AppleReminders.Destination?
    @State private var mirrorProblem: String?
    @State private var mirrorSuccess: String?
    @State private var accessibilityTrusted = false

    /// Derived from the stored name on appear rather than persisted, since
    /// "custom" is a state of this window and not a preference.
    @State private var openAIModelSelection = OpenAIModelChoice.Selection.custom
    @State private var anthropicModelSelection = AnthropicModelChoice.Selection.custom
    @State private var geminiModelSelection = GeminiModelChoice.Selection.custom

    private var selectedProvider: AppSettings.Provider {
        AppSettings.Provider(rawValue: provider) ?? .ollama
    }

    private var selectedCloudKeyStored: Bool {
        switch selectedProvider {
        case .openAI: openAIKeyStored
        case .anthropic: anthropicKeyStored
        case .gemini: geminiKeyStored
        case .ollama: false
        }
    }

    private var accessibilityStatusText: String {
        if !accessibilityExtrasEnabled {
            return "Off. Carbon shortcuts and OCR pointing work without Accessibility."
        }
        if accessibilityTrusted {
            return "On — Tab+Q is active. Show me also moves the pointer onto the named control."
        }
        return "Waiting for permission. Enable TodoCompanion in System Settings → Privacy & Security → Accessibility."
    }

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

                Picker("Summon and start talking", selection: $talkHotkeyID) {
                    Text("Off").tag(HotkeyChoice.offIdentifier)
                    ForEach(HotkeyChoice.all) { choice in
                        Text("\(choice.displayName) ×2").tag(choice.id)
                    }
                }
                .onChange(of: talkHotkeyID) { _, newValue in
                    GlobalHotkey.shared.activate(HotkeyChoice.optional(newValue), for: .talk)
                }

                Text("Press the combo twice quickly to bring the panel up with the microphone already "
                     + "open, and twice again to stop. A single press does nothing, so an accidental "
                     + "brush does not start listening. Nothing listens until you do — "
                     + "\(Prompt.assistantName) has no wake word and never will.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if talkHotkeyID == hotkeyID {
                    Label("Both shortcuts are the same combo, so only one of them will happen.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(DS.Status.problem)
                }

                Text("These combos avoid the ones macOS reserves for itself, such as ⌘Space and ⌥⌘Space. "
                     + "Tab+Q needs the Accessibility extras below. Until those are on, pressing the "
                     + "talk combo twice is how you open the mic directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if GlobalHotkey.shared.didFailToRegister {
                    Label("Another app already owns this shortcut. Pick a different one.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Accessibility extras") {
                Toggle("Enable advanced shortcuts and pointer actions",
                       isOn: $accessibilityExtrasEnabled)
                    .onChange(of: accessibilityExtrasEnabled) { _, isOn in
                        TrustAccessibility.setExtrasEnabled(isOn)
                        refreshAccessibilityStatus()
                    }

                Text(accessibilityStatusText)
                    .font(.caption)
                    .foregroundStyle(accessibilityTrusted ? DS.Status.ready : .secondary)

                if accessibilityExtrasEnabled, !accessibilityTrusted {
                    Button("Open System Settings…") {
                        TrustAccessibility.openSystemSettings()
                    }
                }

                Text("Off by default. When enabled and granted, Tab+Q opens \(Prompt.assistantName) "
                     + "listening, and Show me also moves the pointer onto the named control. "
                     + "Teach me with Guide cursor warps the pointer from step to step. Carbon "
                     + "shortcuts keep working either way. Nothing listens until you press a key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Who answers") {
                // Menu rather than a segmented control: four providers do not
                // fit on a segment strip, and a strip that only shows Local /
                // OpenAI makes Claude and Gemini look missing.
                Picker("Provider", selection: $provider) {
                    ForEach(AppSettings.Provider.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Text(whoAnswersCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Model and key sit *under* the provider choice, not in
                // separate always-visible sections — otherwise picking "what
                // answers" and picking "which model" feel like two unrelated
                // controls fighting each other.
                switch selectedProvider {
                case .ollama:
                    TextField("Ollama endpoint", text: $endpoint)
                    TextField("Model", text: $model)

                case .openAI:
                    openAIModelControls
                    cloudKeyRow(
                        draft: $openAIKeyDraft,
                        isStored: $openAIKeyStored,
                        account: OpenAIBrain.keychainAccount,
                        placeholder: "sk-…"
                    ) {
                        canImportKey = !openAIKeyStored && TodoBridge.importableOpenAIKey() != nil
                    }
                    if !openAIKeyStored, canImportKey {
                        Button("Import the key from To-Do Notifier") {
                            guard let found = TodoBridge.importableOpenAIKey() else { return }
                            Keychain.set(found, for: OpenAIBrain.keychainAccount)
                            openAIKeyStored = AppSettings.openAIKey != nil
                            canImportKey = false
                        }
                        Text("Your to-do app already has one saved. This copies it into the Keychain; the original stays where it is.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .anthropic:
                    anthropicModelControls
                    cloudKeyRow(
                        draft: $anthropicKeyDraft,
                        isStored: $anthropicKeyStored,
                        account: AnthropicBrain.keychainAccount,
                        placeholder: "sk-ant-…"
                    )

                case .gemini:
                    geminiModelControls
                    cloudKeyRow(
                        draft: $geminiKeyDraft,
                        isStored: $geminiKeyStored,
                        account: GeminiBrain.keychainAccount,
                        placeholder: "AIza…"
                    )
                }

                // Selecting a provider is not the same as being able to use it,
                // and the difference is otherwise only discoverable by noticing
                // that the answers did not improve.
                if selectedProvider.isCloud, !selectedCloudKeyStored {
                    Label("No API key saved for \(selectedProvider.displayName) yet, so questions are still answered on this Mac.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Dictation") {
                Picker("Recognizer", selection: $dictationEngine) {
                    ForEach(AppSettings.DictationEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine.rawValue)
                    }
                }

                Text(AppSettings.DictationEngine(rawValue: dictationEngine)?.detail ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Both run on this Mac. Your voice is never sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reading answers aloud") {
                Toggle("Have \(Prompt.assistantName) read answers out loud", isOn: $speaksAnswers)

                if speaksAnswers {
                    Picker("Voice", selection: $voiceEngine) {
                        ForEach(AppSettings.VoiceEngine.allCases) { engine in
                            Text(engine.displayName).tag(engine.rawValue)
                        }
                    }

                    Text(AppSettings.VoiceEngine(rawValue: voiceEngine)?.detail ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if voiceEngine == AppSettings.VoiceEngine.system.rawValue {
                        Picker("System voice", selection: $voiceIdentifier) {
                            Text("System default").tag("")
                            ForEach(SpeechPlayback.availableVoices, id: \.identifier) { voice in
                                Text(voice.name).tag(voice.identifier)
                            }
                        }
                    } else if !KokoroVoiceSynthesizer.isSupportedBySystem {
                        // Stated here rather than only on failure, since the
                        // alternative is a setting that looks fine and produces
                        // silence at the moment an answer arrives.
                        Text("Needs macOS 26.6 or later. On this Mac the system voice will be used.")
                            .font(.caption)
                            .foregroundStyle(DS.Status.problem)
                    }

                    Toggle("Box each control on screen as \(Prompt.assistantName) names it",
                           isOn: $followsAlongWhileSpeaking)

                    Text("Only labels \(Prompt.assistantName) quotes exactly are boxed, so nothing is drawn on a guess. The box follows the sentence being read and disappears when the voice stops. Leave this off and the panel still offers a button to box the one control an answer named.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Guide cursor during Teach me", isOn: $guideCursorWhileTeaching)

                    Text("Moves the pointer onto each step’s box while teaching. Needs Accessibility extras. Same option lives on the lesson bar so you can flip it mid-lesson.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Both voices run on this Mac, so nothing is sent anywhere. Speaking stops as soon as you dictate, ask something else, or close the panel.")
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
                    Text("Needs a second Ollama model: run `ollama pull \(embeddingModel)`. It runs on this Mac and is never sent anywhere, even when a cloud model is answering your questions.")
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
                        canImportKey = !openAIKeyStored && TodoBridge.importableOpenAIKey() != nil
                    }
                }

                Text("Point this at the To-Do Notifier's app-data.json so the companion can answer using your open tasks and notes. It is only ever read, never written.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reminders on your iPhone") {
                Toggle("Mirror dated tasks to Apple Reminders", isOn: $mirrorsToAppleReminders)
                    .disabled(!isLinked)
                    .onChange(of: mirrorsToAppleReminders) { _, isOn in
                        Task { await applyMirrorSetting(isOn) }
                    }

                if !isLinked {
                    Text("Link your to-do app above first — these are its tasks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let problem = mirrorProblem {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        if AppleReminders.isDenied || problem.contains("System Settings") {
                            Button("Open System Settings…") {
                                ReminderMirrorMessaging.openSystemSettingsForReminders()
                            }
                            .font(.caption)
                        }
                    }
                } else if mirrorsToAppleReminders, let destination = mirrorDestination {
                    // Says which account, because a *local* Reminders account
                    // syncs nowhere and every other part of this would still
                    // look like it was working.
                    Text(ReminderMirrorMessaging.detail(for: destination,
                                                         assistantName: Prompt.assistantName))
                        .font(.caption)
                        .foregroundStyle(destination.reachesOtherDevices ? Color.secondary : Color.orange)
                    if !destination.reachesOtherDevices {
                        Button("Open System Settings…") {
                            ReminderMirrorMessaging.openSystemSettingsForReminders()
                        }
                        .font(.caption)
                    } else if let mirrorSuccess {
                        Label(mirrorSuccess, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(DS.Status.saved)
                    }
                } else {
                    Text(ReminderMirrorMessaging.offStateDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Capture from your phone") {
                HStack {
                    Text(inboxFolder ?? "Not linked")
                        .foregroundStyle(inboxFolder == nil ? .secondary : .primary)
                    Spacer()
                    Button(inboxFolder == nil ? "Choose folder…" : "Unlink") {
                        inboxProblem = nil
                        if inboxFolder == nil {
                            switch InboxImporter.linkResult() {
                            case .linked:
                                refreshInbox()
                            case .cancelled:
                                break
                            case let .failed(message):
                                inboxProblem = message
                            }
                        } else {
                            InboxImporter.unlink()
                            refreshInbox()
                        }
                    }
                }

                if let inboxProblem {
                    Label(inboxProblem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if inboxFolder != nil {
                    Text(inboxWaiting == 0
                         ? "Nothing waiting. Items are brought in when the app launches, each time you summon the panel, and when you open the library."
                         : "\(inboxWaiting) waiting. They will be brought in on the next summon, or when you open the library.")
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
                     ? "Needed for a cloud model to see the screen, and for a local vision model such as qwen3-vl."
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

            openAIModelSelection = OpenAIModelChoice.selection(for: openAIModel)
            anthropicModelSelection = AnthropicModelChoice.selection(for: anthropicModel)
            geminiModelSelection = GeminiModelChoice.selection(for: geminiModel)
            openAIKeyStored = AppSettings.openAIKey != nil
            anthropicKeyStored = AppSettings.anthropicKey != nil
            geminiKeyStored = AppSettings.geminiKey != nil
            refreshLinkedSummary()
            refreshInbox()
            refreshAccessibilityStatus()
            canImportKey = !openAIKeyStored && TodoBridge.importableOpenAIKey() != nil
            if mirrorsToAppleReminders, AppleReminders.isAuthorized {
                mirrorDestination = AppleReminders.destination()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
            if accessibilityExtrasEnabled {
                EventTapHotkey.shared.refresh()
            }
        }
    }

    private var whoAnswersCaption: String {
        switch selectedProvider {
        case .ollama:
            "Nothing leaves this Mac. Local vision models are weaker at reading interfaces, so answers about what is on screen are rougher."
        case .openAI, .anthropic, .gemini:
            "Your question and the captured screen are sent to \(selectedProvider.displayName). Saved summaries and embeddings stay on this Mac and are never sent anywhere."
        }
    }

    @ViewBuilder
    private var openAIModelControls: some View {
        Picker("Model", selection: $openAIModelSelection) {
            ForEach(OpenAIModelChoice.all) { choice in
                Text(choice.displayName)
                    .tag(OpenAIModelChoice.Selection.known(choice.id))
            }
            Divider()
            Text("Custom…").tag(OpenAIModelChoice.Selection.custom)
        }
        .onChange(of: openAIModelSelection) { _, newSelection in
            if case .known(let chosenModel) = newSelection { openAIModel = chosenModel }
        }

        if openAIModelSelection == .custom {
            TextField("Model name", text: $openAIModel, prompt: Text("gpt-5.6-…"))
        }

        if let choice = OpenAIModelChoice.named(openAIModel) {
            Text("\(choice.id) — \(choice.detail)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var anthropicModelControls: some View {
        Picker("Model", selection: $anthropicModelSelection) {
            ForEach(AnthropicModelChoice.all) { choice in
                Text(choice.displayName)
                    .tag(AnthropicModelChoice.Selection.known(choice.id))
            }
            Divider()
            Text("Custom…").tag(AnthropicModelChoice.Selection.custom)
        }
        .onChange(of: anthropicModelSelection) { _, newSelection in
            if case .known(let chosenModel) = newSelection { anthropicModel = chosenModel }
        }

        if anthropicModelSelection == .custom {
            TextField("Model name", text: $anthropicModel, prompt: Text("claude-…"))
        }

        if let choice = AnthropicModelChoice.named(anthropicModel) {
            Text("\(choice.id) — \(choice.detail)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var geminiModelControls: some View {
        Picker("Model", selection: $geminiModelSelection) {
            ForEach(GeminiModelChoice.all) { choice in
                Text(choice.displayName)
                    .tag(GeminiModelChoice.Selection.known(choice.id))
            }
            Divider()
            Text("Custom…").tag(GeminiModelChoice.Selection.custom)
        }
        .onChange(of: geminiModelSelection) { _, newSelection in
            if case .known(let chosenModel) = newSelection { geminiModel = chosenModel }
        }

        if geminiModelSelection == .custom {
            TextField("Model name", text: $geminiModel, prompt: Text("gemini-…"))
        }

        if let choice = GeminiModelChoice.named(geminiModel) {
            Text("\(choice.id) — \(choice.detail)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshAccessibilityStatus() {
        accessibilityTrusted = TrustAccessibility.isTrusted
    }

    @ViewBuilder
    private func cloudKeyRow(
        draft: Binding<String>,
        isStored: Binding<Bool>,
        account: String,
        placeholder: String,
        onChange: (() -> Void)? = nil
    ) -> some View {
        // Plain TextField, not SecureField: SecureField tells macOS this is a
        // login password, so Passwords autofill floats over unrelated rows in
        // Settings (including Who answers) and the key field looks possessed.
        // An API key is a secret, but it is not a password.
        HStack {
            TextField(isStored.wrappedValue && draft.wrappedValue.isEmpty
                      ? "Stored in Keychain — paste a new key to replace"
                      : placeholder,
                      text: draft)
                .autocorrectionDisabled()
                .font(.body.monospaced())
            Button(isStored.wrappedValue && draft.wrappedValue.isEmpty ? "Remove" : "Save") {
                if isStored.wrappedValue, draft.wrappedValue.isEmpty {
                    Keychain.remove(account)
                    isStored.wrappedValue = false
                } else {
                    Keychain.set(draft.wrappedValue, for: account)
                    draft.wrappedValue = ""
                    isStored.wrappedValue = Keychain.get(account) != nil
                }
                onChange?()
            }
            .disabled(draft.wrappedValue.isEmpty && !isStored.wrappedValue)
        }

        Text("Kept in the login Keychain, not in preferences.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func refreshInbox() {
        inboxFolder = InboxImporter.folderName
        inboxWaiting = InboxImporter.pendingCount
    }

    /// Asks for the permission at the moment the switch is flipped, and undoes
    /// the switch if it is refused.
    ///
    /// A toggle left on with no access is the "silently downgraded" failure this
    /// app avoids elsewhere: nothing would reach the phone, and the setting
    /// would say it should.
    private func applyMirrorSetting(_ isOn: Bool) async {
        mirrorProblem = nil
        mirrorSuccess = nil

        guard isOn else {
            // Takes back exactly what it added. Leaving a stale list behind
            // would keep alerting for tasks this app is no longer tracking.
            try? await AppleReminders.withdrawAll()
            mirrorDestination = nil
            return
        }

        let granted: Bool
        do {
            granted = try await AppleReminders.requestAccess()
        } catch {
            // Stated rather than folded into "not granted": a thrown error is
            // usually a misconfiguration on this side, which is not something
            // the user can fix in System Settings.
            mirrorsToAppleReminders = false
            mirrorProblem = "Reminders refused the request: \(error.localizedDescription)"
            return
        }

        guard granted else {
            mirrorsToAppleReminders = false
            mirrorProblem = ReminderMirrorMessaging.deniedDetail(assistantName: Prompt.assistantName)
            return
        }

        mirrorDestination = AppleReminders.destination()
        guard mirrorDestination != nil else {
            mirrorsToAppleReminders = false
            mirrorProblem = "No Reminders account was found on this Mac."
            return
        }

        let work = TodoBridge.load()
        do {
            try await AppleReminders.sync(openTodos: work.todos, quietHours: work.quietHours)
            if let destination = mirrorDestination, destination.reachesOtherDevices {
                mirrorSuccess = "Mirrored — check Reminders on your iPhone"
            }
        } catch {
            mirrorProblem = error.localizedDescription
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
