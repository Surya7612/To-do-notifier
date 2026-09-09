import Foundation

/// UserDefaults-backed configuration. Keys are shared with SettingsView via @AppStorage.
enum AppSettings {
    enum Key {
        static let ollamaEndpoint = "ollamaEndpoint"
        static let model = "model"
        static let sendsImage = "sendsImage"
        static let hotkeyID = "hotkeyID"
        static let talkHotkeyID = "talkHotkeyID"
        static let provider = "provider"
        static let openAIModel = "openAIModel"
        static let currentProjectID = "currentProjectID"
        static let semanticEnabled = "semanticEnabled"
        static let embeddingModel = "embeddingModel"
        static let speaksAnswers = "speaksAnswers"
        static let followsAlongWhileSpeaking = "followsAlongWhileSpeaking"
        static let voiceIdentifier = "voiceIdentifier"
        static let dictationEngine = "dictationEngine"
        static let voiceEngine = "voiceEngine"
        static let mirrorsToAppleReminders = "mirrorsToAppleReminders"
        static let accessibilityExtrasEnabled = "accessibilityExtrasEnabled"
    }

    static let defaultEndpoint = "http://127.0.0.1:11434"
    static let defaultModel = "llama3.2"
    static let defaultEmbeddingModel = "nomic-embed-text"

    /// Which brain answers a question the user asked.
    ///
    /// Local is the default because it works with no key and no account, and
    /// because "local-first by default" is a stated principle. The choice
    /// persists once changed, so nobody has to re-pick it every summon.
    enum Provider: String, CaseIterable, Identifiable {
        case ollama
        case openAI

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .ollama: "On this Mac"
            case .openAI: "OpenAI"
            }
        }
    }

    /// Which voice reads an answer aloud.
    ///
    /// Both run on this Mac. The system voice is the default because it needs
    /// nothing downloaded and works everywhere; Kokoro sounds markedly less
    /// synthetic but fetches a model on first use and needs macOS 26.6, which
    /// `KokoroVoiceSynthesizer` checks rather than risking Apple's BNNS crash.
    enum VoiceEngine: String, CaseIterable, Identifiable {
        case system
        case kokoro

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .system: "System"
            case .kokoro: "Kokoro"
            }
        }

        var detail: String {
            switch self {
            case .system:
                "The voices built into macOS. Nothing to download, and noticeably synthetic."
            case .kokoro:
                "Kokoro-82M on the Neural Engine. Much more natural. Downloads a model the first time."
            }
        }

        @MainActor
        func makeSynthesizer() -> any VoiceSynthesizer {
            switch self {
            case .system: SystemVoiceSynthesizer()
            case .kokoro: KokoroVoiceSynthesizer()
            }
        }
    }

    static var voiceEngine: VoiceEngine {
        let raw = UserDefaults.standard.string(forKey: Key.voiceEngine) ?? ""
        return VoiceEngine(rawValue: raw) ?? .system
    }

    /// Which recognizer turns speech into text.
    ///
    /// Both run on this Mac, so this is a quality and disk-space choice rather
    /// than a privacy one. Apple's is the default because it needs nothing
    /// downloaded; Parakeet is better at continuous speech but fetches a model
    /// on first use, and asking for a hundred megabytes before anyone has tried
    /// the feature is the wrong trade for a default.
    enum DictationEngine: String, CaseIterable, Identifiable {
        case apple
        case parakeet

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .apple: "Apple"
            case .parakeet: "Parakeet"
            }
        }

        var detail: String {
            switch self {
            case .apple:
                "Built in, nothing to download. Fastest to the first word."
            case .parakeet:
                "Neural Engine, keeps the sentence across pauses. First use downloads a model; live typing is usually a beat behind Apple."
            }
        }

        @MainActor
        func makeRecognizer() -> any DictationRecognizer {
            switch self {
            case .apple: AppleDictationRecognizer()
            case .parakeet: ParakeetDictationRecognizer()
            }
        }
    }

    static var dictationEngine: DictationEngine {
        let raw = UserDefaults.standard.string(forKey: Key.dictationEngine) ?? ""
        return DictationEngine(rawValue: raw) ?? .apple
    }

    /// Who the panel says will answer, and whether the user's choice is
    /// actually in force.
    ///
    /// Exists because a selection that cannot be honoured has to be *stated*.
    /// Selecting OpenAI with no key in the Keychain falls back to the local
    /// model, and labelling that "Local" makes the switch look broken rather
    /// than makes the missing key visible — the user flipped something and
    /// nothing moved.
    enum AnswerDestination: Equatable, Sendable {
        case local
        case cloud(String)
        case cloudWithoutKey

        /// Pure so it can be tested without a Keychain or a defaults domain.
        static func resolve(provider: Provider, hasCloudKey: Bool, cloudModel: String) -> AnswerDestination {
            switch provider {
            case .ollama: return .local
            case .openAI: return hasCloudKey ? .cloud(cloudModel) : .cloudWithoutKey
            }
        }

        var label: String {
            switch self {
            case .local: return "Local"
            case let .cloud(model): return model
            case .cloudWithoutKey: return "OpenAI — no key"
            }
        }

        var glyph: String {
            switch self {
            case .local: return "lock.laptopcomputer"
            case .cloud: return "cloud"
            case .cloudWithoutKey: return "exclamationmark.triangle"
            }
        }

        /// Only a usable cloud provider actually sends anything.
        var leavesTheMachine: Bool {
            switch self {
            case .cloud: return true
            case .local, .cloudWithoutKey: return false
            }
        }

        func explanation(localModel: String) -> String {
            switch self {
            case .local:
                return "Answered by \(localModel) on this Mac. Nothing leaves the device. Click to change."
            case let .cloud(model):
                return "Your question and the captured screen go to \(model). Saved summaries stay local. Click to change."
            case .cloudWithoutKey:
                return "OpenAI is selected but no API key is saved, so \(localModel) is answering on this Mac. Add a key in Settings."
            }
        }
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.ollamaEndpoint: defaultEndpoint,
            Key.model: defaultModel,
            Key.sendsImage: false,
            Key.hotkeyID: HotkeyChoice.fallback.id,
            Key.talkHotkeyID: HotkeyChoice.talkFallback.id,
            Key.provider: Provider.ollama.rawValue,
            Key.openAIModel: OpenAIBrain.defaultModel,
            // Off by default because it needs a second model pulled, and a
            // feature that silently does nothing until an unrelated command is
            // run is worse than one the user turned on deliberately.
            Key.semanticEnabled: false,
            Key.embeddingModel: defaultEmbeddingModel,
            // Off by default: an assistant that starts talking the moment it is
            // summoned is intrusive in a way a panel of text is not, and the
            // panel is often summoned in a meeting.
            Key.speaksAnswers: false,
            // Off by default: Accessibility is a high-trust grant, and the app
            // works fully without it. Tab+Q and pointer move/click unlock only
            // when the user flips this and macOS trusts the process.
            Key.accessibilityExtrasEnabled: false,
        ])
    }

    /// Whether the user asked for Accessibility extras (Tab+Q, Show me warping
    /// the pointer, Guided Teach cursor follow). The grant is still required
    /// separately in System Settings; this flag alone is not enough.
    static var accessibilityExtrasEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.accessibilityExtrasEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Key.accessibilityExtrasEnabled) }
    }

    /// Whether dated tasks are copied into Apple Reminders so iCloud can alert
    /// the user away from this Mac.
    ///
    /// Off by default, and not only out of caution about a new permission: this
    /// is the one feature here that puts the user's task titles into another
    /// company's sync, which is a decision to make deliberately rather than to
    /// find already made.
    static var mirrorsToAppleReminders: Bool {
        UserDefaults.standard.bool(forKey: Key.mirrorsToAppleReminders)
    }

    /// Whether answers are read aloud, always by the system voice on this Mac.
    static var speaksAnswers: Bool {
        UserDefaults.standard.bool(forKey: Key.speaksAnswers)
    }

    /// Whether the box on screen moves to whichever control Max is naming as it
    /// reads an answer aloud.
    ///
    /// Off by default, and this one is not merely caution. The standing rule is
    /// that nothing is drawn over the user's screen unasked — the existing box
    /// is a button press that names its match first. Follow-along cannot name
    /// each match beforehand, because the point is that it keeps up with the
    /// speech, so what stands in for that consent is this switch plus the
    /// narrower matching it turns on: only a label Max put in double quotes is
    /// ever boxed, never a phrase inferred from prose.
    static var followsAlongWhileSpeaking: Bool {
        UserDefaults.standard.bool(forKey: Key.followsAlongWhileSpeaking)
    }

    /// nil means the system default voice.
    static var voiceIdentifier: String? {
        UserDefaults.standard.string(forKey: Key.voiceIdentifier).flatMap {
            $0.isEmpty ? nil : $0
        }
    }

    /// Whether saved context is matched by meaning as well as by words.
    static var semanticEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.semanticEnabled)
    }

    static var embeddingModel: String {
        let raw = UserDefaults.standard.string(forKey: Key.embeddingModel) ?? defaultEmbeddingModel
        return raw.isEmpty ? defaultEmbeddingModel : raw
    }

    static var provider: Provider {
        Provider(rawValue: UserDefaults.standard.string(forKey: Key.provider) ?? "") ?? .ollama
    }

    static var openAIModel: String {
        let raw = UserDefaults.standard.string(forKey: Key.openAIModel) ?? OpenAIBrain.defaultModel
        return raw.isEmpty ? OpenAIBrain.defaultModel : raw
    }

    static var openAIKey: String? { Keychain.get(OpenAIBrain.keychainAccount) }

    static var hotkey: HotkeyChoice {
        HotkeyChoice.named(UserDefaults.standard.string(forKey: Key.hotkeyID))
    }

    /// Summons the panel and opens the microphone in one press, or nil when the
    /// user has switched it off.
    ///
    /// This is not a wake word and must never become one. The distinction is
    /// not about how convenient it is to start talking, it is about whether the
    /// microphone is ever open when the user did not open it — a shortcut is
    /// still the user opening it. Nothing listens until this is pressed.
    static var talkHotkey: HotkeyChoice? {
        HotkeyChoice.optional(UserDefaults.standard.string(forKey: Key.talkHotkeyID))
    }

    static var endpoint: URL {
        let raw = UserDefaults.standard.string(forKey: Key.ollamaEndpoint) ?? defaultEndpoint
        return URL(string: raw) ?? URL(string: defaultEndpoint)!
    }

    static var model: String {
        let raw = UserDefaults.standard.string(forKey: Key.model) ?? defaultModel
        return raw.isEmpty ? defaultModel : raw
    }

    /// Send the screenshot itself instead of OCR text. Requires a vision-capable Ollama model.
    static var sendsImage: Bool {
        UserDefaults.standard.bool(forKey: Key.sendsImage)
    }

    /// What the user says they are working on.
    ///
    /// Chosen explicitly and left alone until they change it. Deriving it from
    /// the frontmost app was the obvious alternative and was rejected: a wrong
    /// guess here silently misfiles everything saved afterwards, and the user
    /// would have no way to see that it had happened.
    static var currentProjectID: String? {
        get {
            let raw = UserDefaults.standard.string(forKey: Key.currentProjectID) ?? ""
            return raw.isEmpty ? nil : raw
        }
        set {
            guard let newValue, !newValue.isEmpty else {
                UserDefaults.standard.removeObject(forKey: Key.currentProjectID)
                return
            }
            UserDefaults.standard.set(newValue, forKey: Key.currentProjectID)
        }
    }
}
