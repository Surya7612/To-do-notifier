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
    }

    static let defaultEndpoint = "http://127.0.0.1:11434"
    static let defaultModel = "llama3.2"

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

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.ollamaEndpoint: defaultEndpoint,
            Key.model: defaultModel,
            Key.sendsImage: false,
            Key.hotkeyID: HotkeyChoice.fallback.id,
            Key.provider: Provider.ollama.rawValue,
            Key.openAIModel: OpenAIBrain.defaultModel,
        ])
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
}
