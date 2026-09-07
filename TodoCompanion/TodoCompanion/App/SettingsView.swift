import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.Key.ollamaEndpoint) private var endpoint = AppSettings.defaultEndpoint
    @AppStorage(AppSettings.Key.model) private var model = AppSettings.defaultModel
    @AppStorage(AppSettings.Key.sendsImage) private var sendsImage = false

    var body: some View {
        Form {
            Section("Local model") {
                TextField("Ollama endpoint", text: $endpoint)
                TextField("Model", text: $model)
            }

            Section("Screen context") {
                Toggle("Send the screenshot instead of on-device text", isOn: $sendsImage)
                Text(sendsImage
                     ? "Requires a vision-capable model such as llava or qwen2.5vl."
                     : "Screenshots stay on this Mac; only recognized text reaches the model.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Shortcut") {
                LabeledContent("Summon companion", value: GlobalHotkey.defaultDisplayName)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
