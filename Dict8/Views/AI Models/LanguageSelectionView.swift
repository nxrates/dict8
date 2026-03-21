import SwiftUI

enum LanguageDisplayMode {
    case full
    case menuItem
}

struct LanguageSelectionView: View {
    @ObservedObject var whisperState: WhisperState
    @AppStorage("SelectedLanguage") private var selectedLanguage: String = "auto"
    var displayMode: LanguageDisplayMode = .full
    @ObservedObject var whisperPrompt: WhisperPrompt

    private var currentModel: (any TranscriptionModel)? { whisperState.currentTranscriptionModel }
    private var isAutoDetect: Bool { currentModel.map { $0.provider == .parakeet || $0.provider == .gemini } ?? false }
    private var isMultilingual: Bool { currentModel?.isMultilingualModel ?? false }
    private var sortedLanguages: [(key: String, value: String)] {
        (currentModel?.supportedLanguages ?? ["en": "English"])
            .sorted { ($0.key == "auto" ? "" : $0.value) < ($1.key == "auto" ? "" : $1.value) }
    }

    private func updateLanguage(_ language: String) {
        selectedLanguage = language
        whisperPrompt.updateTranscriptionPrompt()
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    var body: some View {
        switch displayMode {
        case .full: fullView
        case .menuItem: menuItemView
        }
    }

    private var fullView: some View {
        Section("Transcription Language") {
            if let model = currentModel {
                if isAutoDetect {
                    LabeledContent("Language") { Text("Autodetected") }
                    Text("Current model: \(model.displayName)").font(.caption).foregroundStyle(.secondary)
                    Text("The transcription language is automatically detected by the model.").font(.caption).foregroundStyle(.secondary)
                } else if isMultilingual {
                    Picker("Select Language", selection: $selectedLanguage) {
                        ForEach(sortedLanguages, id: \.key) { Text($0.value).tag($0.key) }
                    }
                    .onChange(of: selectedLanguage) { _, new in updateLanguage(new) }
                    Text("Current model: \(model.displayName)").font(.caption).foregroundStyle(.secondary)
                } else {
                    LabeledContent("Language") { Text("English") }
                    Text("This is an English-optimized model and only supports English transcription.")
                        .font(.caption).foregroundStyle(.secondary)
                        .onAppear { updateLanguage("en") }
                }
            } else {
                Text("No model selected").font(.body).foregroundStyle(.secondary)
            }
        }
    }

    private var menuItemView: some View {
        Group {
            if isAutoDetect {
                Button {} label: { Text("Language: Autodetected").foregroundStyle(.secondary) }.disabled(true)
            } else if isMultilingual {
                Menu {
                    ForEach(sortedLanguages, id: \.key) { key, value in
                        Button {
                            updateLanguage(key)
                        } label: {
                            HStack { Text(value); if selectedLanguage == key { Image(systemName: "checkmark") } }
                        }
                    }
                } label: {
                    HStack {
                        Text("Language: \(sortedLanguages.first { $0.key == selectedLanguage }?.value ?? "Unknown")")
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }
                }
            } else {
                Button {} label: { Text("Language: English (only)").foregroundStyle(.secondary) }
                    .disabled(true)
                    .onAppear { updateLanguage("en") }
            }
        }
    }
}
