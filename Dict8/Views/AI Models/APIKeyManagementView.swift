import SwiftUI
import LLMkit

struct APIKeyManagementView: View {
    @EnvironmentObject private var aiService: AIService
    @State private var apiKey = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isVerifying = false
    @State private var ollamaBaseURL = UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
    @State private var ollamaModels: [OllamaModel] = []
    @State private var selectedOllamaModel = UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? "qwen3:1.7b"
    @State private var isCheckingOllama = false
    @State private var isEditingURL = false

    var body: some View {
        Group {
            Divider()
            HStack {
                Picker("Cloud Provider", selection: $aiService.selectedProvider) {
                    ForEach(AIProvider.allCases.filter { $0 != .elevenLabs && $0 != .deepgram && $0 != .soniox }, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Spacer(); connectionStatus
            }
            .onChange(of: aiService.selectedProvider) { _, _ in if aiService.selectedProvider == .ollama { checkOllamaConnection() } }
            modelPicker
            providerConfig
        }
        .alert("Error", isPresented: $showAlert) { Button("OK", role: .cancel) {} } message: { Text(alertMessage) }
        .onAppear { if aiService.selectedProvider == .ollama { checkOllamaConnection() } }
    }

    @ViewBuilder private var connectionStatus: some View {
        if aiService.selectedProvider == .ollama {
            if isCheckingOllama { ProgressView().controlSize(.small) }
            else {
                Label(!ollamaModels.isEmpty ? "Connected" : "Disconnected", systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(!ollamaModels.isEmpty ? .green : .red)
            }
        } else if aiService.isAPIKeyValid {
            Label("Connected", systemImage: "circle.fill").font(.caption).foregroundStyle(.green)
        }
    }

    @ViewBuilder private var modelPicker: some View {
        let needsRefresh = aiService.selectedProvider == .openRouter
        if needsRefresh && aiService.availableModels.isEmpty {
            HStack {
                Text("No models loaded").foregroundStyle(.secondary); Spacer()
                Button { Task { await aiService.fetchOpenRouterModels() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        } else if !aiService.availableModels.isEmpty && aiService.selectedProvider != .ollama && aiService.selectedProvider != .custom {
            HStack {
                Picker("Model", selection: Binding(get: { aiService.currentModel }, set: { aiService.selectModel($0) })) {
                    ForEach(aiService.availableModels, id: \.self) { Text($0).tag($0) }
                }
                if needsRefresh {
                    Spacer()
                    Button { Task { await aiService.fetchOpenRouterModels() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                }
            }
        }
    }

    @ViewBuilder private var providerConfig: some View {
        switch aiService.selectedProvider {
        case .ollama: ollamaConfig
        case .custom: customConfig
        default: apiKeyField(canVerify: true)
        }
    }

    private var ollamaConfig: some View {
        Group {
            if isEditingURL {
                HStack {
                    TextField("Base URL", text: $ollamaBaseURL).textFieldStyle(.roundedBorder)
                    Button("Save") { aiService.updateOllamaBaseURL(ollamaBaseURL); checkOllamaConnection(); isEditingURL = false }.buttonStyle(.bordered)
                }
            } else {
                LabeledContent("Server") {
                    HStack {
                        Text(ollamaBaseURL).foregroundStyle(.secondary)
                        Button("Edit") { isEditingURL = true }.buttonStyle(.bordered)
                        Button { ollamaBaseURL = "http://localhost:11434"; aiService.updateOllamaBaseURL(ollamaBaseURL); checkOllamaConnection() } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }.buttonStyle(.bordered).help("Reset to default")
                    }
                }
            }
            if !ollamaModels.isEmpty {
                Picker("Model", selection: $selectedOllamaModel) { ForEach(ollamaModels) { Text($0.name).tag($0.name) } }
                    .onChange(of: selectedOllamaModel) { _, new in aiService.updateSelectedOllamaModel(new) }
            }
        }
    }

    private var customConfig: some View {
        Group {
            TextField("API Endpoint URL", text: $aiService.customBaseURL).textFieldStyle(.roundedBorder)
            TextField("Model Name", text: $aiService.customModel).textFieldStyle(.roundedBorder)
            apiKeyField(canVerify: !aiService.customBaseURL.isEmpty && !aiService.customModel.isEmpty)
        }
    }

    @ViewBuilder private func apiKeyField(canVerify: Bool) -> some View {
        if aiService.isAPIKeyValid {
            HStack {
                LabeledContent("API Key") { Text("Set").foregroundStyle(.secondary) }
                Spacer()
                Button("Remove", role: .destructive) { aiService.clearAPIKey() }.buttonStyle(.bordered)
            }
        } else {
            SecureField("API Key", text: $apiKey).textFieldStyle(.roundedBorder)
            HStack {
                if let url = apiKeyURL { Link(destination: url) { Label("Get API Key", systemImage: "key.fill").font(.caption) }.buttonStyle(.plain) }
                Spacer()
                Button {
                    isVerifying = true
                    aiService.saveAPIKey(apiKey) { success, errorMessage in
                        isVerifying = false
                        if !success { alertMessage = errorMessage ?? "Verification failed"; showAlert = true }
                        apiKey = ""
                    }
                } label: {
                    HStack { if isVerifying { ProgressView().controlSize(.small) }; Text("Verify and Save") }
                }.glassActionButton().disabled(apiKey.isEmpty || !canVerify)
            }
        }
    }

    private func checkOllamaConnection() {
        isCheckingOllama = true
        aiService.checkOllamaConnection { connected in
            if connected {
                Task { ollamaModels = await aiService.fetchOllamaModels(); isCheckingOllama = false }
            } else {
                ollamaModels = []; isCheckingOllama = false
                alertMessage = "Could not connect to Ollama. Please check if Ollama is running and the base URL is correct."; showAlert = true
            }
        }
    }

    private var apiKeyURL: URL? {
        switch aiService.selectedProvider {
        case .groq: URL(string: "https://console.groq.com/keys")
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .gemini: URL(string: "https://makersuite.google.com/app/apikey")
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
        case .mistral: URL(string: "https://console.mistral.ai/api-keys")
        case .elevenLabs: URL(string: "https://elevenlabs.io/speech-synthesis")
        case .deepgram: URL(string: "https://console.deepgram.com/api-keys")
        case .soniox: URL(string: "https://console.soniox.com/")
        case .openRouter: URL(string: "https://openrouter.ai/keys")
        case .cerebras: URL(string: "https://cloud.cerebras.ai/")
        case .deepseek: URL(string: "https://platform.deepseek.com/api_keys")
        case .xai: URL(string: "https://console.x.ai/")
        default: nil
        }
    }
}
