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
    @AppStorage(AppSettings.Key.semanticEnabled) private var semanticEnabled = false
    @AppStorage(AppSettings.Key.embeddingModel) private var embeddingModel = AppSettings.defaultEmbeddingModel
    @AppStorage(AppSettings.Key.speaksAnswers) private var speaksAnswers = false
    @AppStorage(AppSettings.Key.followsAlongWhileSpeaking) private var followsAlongWhileSpeaking = false
    @AppStorage(AppSettings.Key.voiceIdentifier) private var voiceIdentifier = ""
    @AppStorage(AppSettings.Key.voiceEngine) private var voiceEngine = AppSettings.VoiceEngine.system.rawValue
    @AppStorage(AppSettings.Key.dictationEngine) private var dictationEngine =
        AppSettings.DictationEngine.apple.rawValue
    @AppStorage(AppSettings.Key.mirrorsToAppleReminders) private var mirrorsToAppleReminders = false
    @AppStorage(AppSettings.Key.accessibilityExtrasEnabled) private var accessibilityExtrasEnabled = false

    /// Mirrors the Keychain rather than being stored by SwiftUI, so the secret
    /// never lands in a preferences plist.
    @State private var apiKey = ""
    @State private var keyIsStored = false
    @State private var isLinked = TodoBridge.isLinked
    @State private var linkedSummary = ""
    @State private var canImportKey = false
    @State private var inboxFolder: String?
    @State private var inboxWaiting = 0
    @State private var mirrorDestination: AppleReminders.Destination?
    @State private var mirrorProblem: String?
    @State private var accessibilityTrusted = false

    /// Derived from the stored name on appear rather than persisted, since
    /// "custom" is a state of this window and not a preference.
    @State private var modelSelection = OpenAIModelChoice.Selection.custom

    private var accessibilityStatusText: String {
        if !accessibilityExtrasEnabled {
            return "Off. Carbon shortcuts and OCR pointing work without Accessibility."
        }
        if accessibilityTrusted {
            return "On — Tab+Q is active. Move pointer and Click appear when AX finds the control."
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
                     + "listening, and Move pointer / Click appear beside Show me when the "
                     + "accessibility tree knows the control. Carbon shortcuts keep working either "
                     + "way. Nothing listens until you press a key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Section("Reminders away from this Mac") {
                Toggle("Copy dated tasks into Apple Reminders", isOn: $mirrorsToAppleReminders)
                    .disabled(!isLinked)
                    .onChange(of: mirrorsToAppleReminders) { _, isOn in
                        Task { await applyMirrorSetting(isOn) }
                    }

                if !isLinked {
                    Text("Link your to-do app above first — these are its tasks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let problem = mirrorProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if mirrorsToAppleReminders, let destination = mirrorDestination {
                    // Says which account, because a *local* Reminders account
                    // syncs nowhere and every other part of this would still
                    // look like it was working.
                    Text(destination.reachesOtherDevices
                         ? "Tasks due in the future are copied into a \u{201C}\(ReminderMirror.listTitle)\u{201D} list in \(destination.account), so your iPhone and Watch alert you even when this Mac is asleep. \(Prompt.assistantName) stops announcing anything Reminders has taken on, so one thing pings once."
                         : "Reminders is using the \u{201C}\(destination.account)\u{201D} account on this Mac, which does not sync, so the list will not reach your phone. Turn on iCloud for Reminders in System Settings.")
                    .font(.caption)
                    .foregroundStyle(destination.reachesOtherDevices ? Color.secondary : Color.orange)
                } else {
                    Text("Local notifications need this Mac awake at the due time. Copying a task into an iCloud Reminders list lets Apple deliver it to your other devices instead. Only tasks still ahead of them are copied, and completing one there leaves the task open in the to-do app.")
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
            refreshAccessibilityStatus()
            canImportKey = !keyIsStored && TodoBridge.importableOpenAIKey() != nil
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

    private func refreshAccessibilityStatus() {
        accessibilityTrusted = TrustAccessibility.isTrusted
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
            mirrorProblem = AppleReminders.isDenied
                ? "Reminders access is off for \(Prompt.assistantName) in System Settings → Privacy & Security → Reminders."
                : "Reminders access was not granted, so nothing will be copied."
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
