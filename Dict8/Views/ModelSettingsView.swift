import SwiftUI

struct ModelSettingsView: View {
    @ObservedObject var whisperPrompt: WhisperPrompt
    @AppStorage("SelectedLanguage") private var selectedLanguage: String = "auto"
    @AppStorage("IsTextFormattingEnabled") private var isTextFormattingEnabled = true
    @AppStorage("IsVADEnabled") private var isVADEnabled = true
    @AppStorage("AppendTrailingSpace") private var appendTrailingSpace = true
    @AppStorage("PrewarmModelOnWake") private var prewarmModelOnWake = true
    @State private var customPrompt: String = ""
    @State private var isEditing: Bool = false

    var body: some View {
        Section("Output Format") {
            HStack {
                Text("Output Format").font(.headline)
                InfoTip(
                    "Unlike GPT, Voice Models(whisper) follows the style of your prompt rather than instructions. Use examples of your desired output format instead of commands.",
                    learnMoreURL: "https://cookbook.openai.com/examples/whisper_prompting_guide#comparison-with-gpt-prompting"
                )
                Spacer()
                Button(isEditing ? "Save" : "Edit") {
                    if isEditing {
                        whisperPrompt.setCustomPrompt(customPrompt, for: selectedLanguage)
                        isEditing = false
                    } else {
                        customPrompt = whisperPrompt.getLanguagePrompt(for: selectedLanguage)
                        isEditing = true
                    }
                }.buttonStyle(.bordered)
            }

            if isEditing {
                TextEditor(text: $customPrompt)
                    .font(.body).frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            } else {
                Text(whisperPrompt.getLanguagePrompt(for: selectedLanguage))
                    .font(.body).foregroundStyle(.secondary)
            }
        }

        Section("Options") {
            Toggle("Add Space After Paste", isOn: $appendTrailingSpace)
            Toggle("Automatic text formatting", isOn: $isTextFormattingEnabled)
            Toggle("Voice Activity Detection (VAD)", isOn: $isVADEnabled)
            Toggle("Prewarm model (Experimental)", isOn: $prewarmModelOnWake)
            FillerWordsSettingsView()
        }
        .onChange(of: selectedLanguage) { _, _ in
            if isEditing { customPrompt = whisperPrompt.getLanguagePrompt(for: selectedLanguage) }
        }
    }
}
