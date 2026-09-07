import Foundation

/// UserDefaults-backed configuration. Keys are shared with SettingsView via @AppStorage.
enum AppSettings {
    enum Key {
        static let ollamaEndpoint = "ollamaEndpoint"
        static let model = "model"
        static let sendsImage = "sendsImage"
        static let hotkeyID = "hotkeyID"
    }

    static let defaultEndpoint = "http://127.0.0.1:11434"
    static let defaultModel = "llama3.2"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.ollamaEndpoint: defaultEndpoint,
            Key.model: defaultModel,
            Key.sendsImage: false,
            Key.hotkeyID: HotkeyChoice.fallback.id,
        ])
    }

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
