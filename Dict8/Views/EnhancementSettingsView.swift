import SwiftUI
import KeyboardShortcuts

// MARK: - Enhancement Model Presets

struct EnhancementModel: Identifiable {
    let id: String          // model ID for API calls
    let displayName: String
    let description: String
    let size: String        // disk size for local, or pricing hint for cloud
    let isLocal: Bool
    let provider: String    // "ollama", "openai", "anthropic", "gemini", "groq", "mistral", "deepseek", "xai"
    var isDefault: Bool = false
}

private let predefinedEnhancementModels: [EnhancementModel] = [
    // Local (Ollama) models
    EnhancementModel(id: "gemma3:1b", displayName: "Gemma 3 1B", description: "Ultra-fast, basic cleanup", size: "815 MB", isLocal: true, provider: "ollama"),
    EnhancementModel(id: "qwen3:1.7b", displayName: "Qwen 3 1.7B", description: "Fast with good quality, multilingual", size: "1.1 GB", isLocal: true, provider: "ollama", isDefault: true),
    EnhancementModel(id: "phi4-mini", displayName: "Phi-4 Mini 3.8B", description: "Best for technical and code language", size: "2.5 GB", isLocal: true, provider: "ollama"),
    EnhancementModel(id: "gemma3:4b", displayName: "Gemma 3 4B", description: "Strong general-purpose cleanup", size: "3.3 GB", isLocal: true, provider: "ollama"),
    EnhancementModel(id: "qwen3:8b", displayName: "Qwen 3 8B", description: "Highest quality, best accuracy", size: "4.9 GB", isLocal: true, provider: "ollama"),
    EnhancementModel(id: "llama4:scout", displayName: "Llama 4 Scout", description: "Meta's latest MoE model", size: "5.2 GB", isLocal: true, provider: "ollama"),
    // Cloud models (require API keys)
    EnhancementModel(id: "gpt-4.1-mini", displayName: "GPT-4.1 Mini", description: "OpenAI's fast, cheap model", size: "Cloud", isLocal: false, provider: "openai"),
    EnhancementModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash", description: "Google's fast model", size: "Cloud", isLocal: false, provider: "gemini"),
    EnhancementModel(id: "claude-haiku-4-5-20250414", displayName: "Claude Haiku 4.5", description: "Anthropic's fast model", size: "Cloud", isLocal: false, provider: "anthropic"),
    EnhancementModel(id: "mistral-small-latest", displayName: "Mistral Small", description: "Mistral's fast model", size: "Cloud", isLocal: false, provider: "mistral"),
    EnhancementModel(id: "deepseek-chat", displayName: "DeepSeek V3", description: "Ultra-cheap, high quality", size: "Cloud", isLocal: false, provider: "deepseek"),
    EnhancementModel(id: "grok-3-mini-fast", displayName: "Grok 3 Mini", description: "xAI's fast model", size: "Cloud", isLocal: false, provider: "xai"),
]

// MARK: - View

struct EnhancementSettingsView: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @EnvironmentObject private var aiService: AIService
    @ObservedObject private var shortcutSettings = EnhancementShortcutSettings.shared
    @State private var isShortcutsExpanded = false
    @State private var sheetMode: PromptEditorView.Mode?
    @State private var pulledOllamaModelNames: [String] = []
    @State private var downloadingModels: Set<String> = []
    @State private var downloadError: String?

    var body: some View {
        Form {
            Section("Enhancement") {
                Toggle(isOn: $enhancementService.isEnhancementEnabled) {
                    HStack(spacing: 4) {
                        Text("Enable Enhancement")
                        InfoTip("AI enhancement passes transcriptions through LLMs for cleanup and formatting.")
                    }
                }
            }

            // Same pattern as STT "Available Models" — unified list + Add Model at bottom
            Section("Available Models") {
                ForEach(predefinedEnhancementModels) { model in
                    modelRow(model)
                }
                // Exact same Add Model component as Speech to Text tab
                AddCustomModelCardView(customModelManager: .shared, whisperState: nil, modelContext: .enhancement) {
                    // refresh if needed
                }
            }

            Section("Prompts") {
                ForEach(enhancementService.customPrompts) { prompt in
                    promptRow(prompt)
                }
                Button { sheetMode = .add } label: {
                    Label("Add Prompt", systemImage: "plus.circle.fill")
                }
            }

            Section("Options") {
                Toggle(isOn: $enhancementService.useScreenCaptureContext) {
                    HStack(spacing: 4) { Text("Screen Context"); InfoTip("Capture on-screen text for better enhancement context.") }
                }
                Toggle(isOn: $enhancementService.useClipboardContext) {
                    HStack(spacing: 4) { Text("Clipboard Context"); InfoTip("Use clipboard text for better enhancement context.") }
                }
            }

            Section {
                DisclosureGroup(isExpanded: $isShortcutsExpanded) {
                    LabeledContent {
                        Toggle("", isOn: $shortcutSettings.isToggleEnhancementShortcutEnabled).toggleStyle(.switch).labelsHidden()
                    } label: { Text("Toggle Enhancement (\u{2318}E)") }
                    LabeledContent {
                        Text("\u{2318}1–\u{2318}0").font(.caption).foregroundColor(.secondary)
                    } label: { Text("Switch Prompt") }
                } label: { Text("Shortcuts").font(.headline) }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshOllamaModels() }
        .sheet(isPresented: Binding(get: { sheetMode != nil }, set: { if !$0 { sheetMode = nil } })) {
            if let mode = sheetMode {
                PromptEditorView(mode: mode) { sheetMode = nil }.frame(minWidth: 450, minHeight: 500)
            }
        }
        .alert("Download Error", isPresented: Binding(get: { downloadError != nil }, set: { if !$0 { downloadError = nil } })) {
            Button("OK") { downloadError = nil }
        } message: {
            Text(downloadError ?? "")
        }
    }

    private func refreshOllamaModels() {
        Task {
            let models = await aiService.fetchOllamaModels()
            pulledOllamaModelNames = models.map { $0.name }
        }
    }

    private func selectModel(_ model: EnhancementModel) {
        if model.isLocal {
            aiService.selectedProvider = .ollama
        } else {
            switch model.provider {
            case "openai": aiService.selectedProvider = .openAI
            case "anthropic": aiService.selectedProvider = .anthropic
            case "gemini": aiService.selectedProvider = .gemini
            case "mistral": aiService.selectedProvider = .mistral
            case "groq": aiService.selectedProvider = .groq
            case "deepseek": aiService.selectedProvider = .deepseek
            case "xai": aiService.selectedProvider = .xai
            default: break
            }
        }
        aiService.selectModel(model.id)
    }

    private func downloadModel(_ model: EnhancementModel) {
        downloadingModels.insert(model.id)
        Task {
            do {
                try await OllamaService.shared.pullModel(name: model.id)
                refreshOllamaModels()
            } catch {
                downloadError = "Failed to download \(model.displayName): \(error.localizedDescription)"
            }
            downloadingModels.remove(model.id)
        }
    }

    private func providerForModel(_ model: EnhancementModel) -> AIProvider? {
        switch model.provider {
        case "ollama": return .ollama
        case "openai": return .openAI
        case "anthropic": return .anthropic
        case "gemini": return .gemini
        case "mistral": return .mistral
        case "groq": return .groq
        case "deepseek": return .deepseek
        case "xai": return .xai
        default: return nil
        }
    }

    // MARK: - Model Row (same layout as ModelCardView)

    private func modelRow(_ model: EnhancementModel) -> some View {
        let isActive: Bool = {
            guard let provider = providerForModel(model) else { return false }
            return aiService.selectedProvider == provider && aiService.currentModel == model.id
        }()
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.displayName).font(.body)
                    if model.isLocal {
                        Text("Local").font(.caption).foregroundStyle(.green)
                    } else {
                        Text("Cloud").font(.caption).foregroundStyle(.secondary)
                    }
                    if isActive { Text("Default").font(.caption).fontWeight(.semibold).foregroundColor(.accentColor) }
                }
                HStack(spacing: 6) {
                    Text(model.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text("\u{00B7}").font(.caption).foregroundStyle(.secondary)
                    Text(model.size).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.isLocal {
                let isInstalled = pulledOllamaModelNames.contains(where: { $0.hasPrefix(model.id) })
                let isDownloading = downloadingModels.contains(model.id)

                if isActive {
                    // Selected — just show highlight
                } else if isDownloading {
                    ProgressView().controlSize(.small)
                    Text("Downloading...").font(.caption)
                } else if isInstalled {
                    Button("Set Default") { selectModel(model) }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Button("Download") { downloadModel(model) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            } else {
                let hasKey = APIKeyManager.shared.hasAPIKey(forProvider: providerForModel(model)?.rawValue ?? "")
                if isActive {
                    // Selected — just show highlight
                } else if hasKey {
                    Button("Set Default") { selectModel(model) }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Text("Setup Required").font(.caption2).foregroundStyle(.orange)
                    Button("Configure") {
                        if let p = providerForModel(model) { aiService.selectedProvider = p }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .listRowBackground(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selectModel(model) }
    }

    // MARK: - Prompt Row (same layout as model rows)

    private func promptRow(_ prompt: CustomPrompt) -> some View {
        let isActive = enhancementService.selectedPromptId == prompt.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(prompt.title).font(.body)
                        if isActive { Text("Active").font(.caption).fontWeight(.semibold).foregroundColor(.accentColor) }
                        if prompt.isPredefined { Text("Default").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let desc = prompt.description, !desc.isEmpty {
                        Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if !prompt.isPredefined {
                    Button { sheetMode = .edit(prompt) } label: { Image(systemName: "pencil") }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            Text(prompt.promptText).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
        .listRowBackground(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { enhancementService.setActivePrompt(prompt) }
        .contextMenu {
            if !prompt.isPredefined {
                Button { sheetMode = .edit(prompt) } label: { Label("Edit", systemImage: "pencil") }
                Button(role: .destructive) { enhancementService.deletePrompt(prompt) } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }
}
