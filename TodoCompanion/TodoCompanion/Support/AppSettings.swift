import Foundation

/// UserDefaults-backed configuration. Keys are shared with SettingsView via @AppStorage.
enum AppSettings {
    enum Key {
        static let ollamaEndpoint = "ollamaEndpoint"
        static let model = "model"
        static let sendsImage = "sendsImage"
        static let hotkeyID = "hotkeyID"
        static let provider = "provider"
        static let openAIModel = "openAIModel"
        static let currentProjectID = "currentProjectID"
        static let semanticEnabled = "semanticEnabled"
        static let embeddingModel = "embeddingModel"
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
            Key.provider: Provider.ollama.rawValue,
            Key.openAIModel: OpenAIBrain.defaultModel,
            // Off by default because it needs a second model pulled, and a
            // feature that silently does nothing until an unrelated command is
            // run is worse than one the user turned on deliberately.
            Key.semanticEnabled: false,
            Key.embeddingModel: defaultEmbeddingModel,
        ])
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
