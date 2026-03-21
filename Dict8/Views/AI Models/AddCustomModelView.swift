import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum AddModelTab: String, CaseIterable {
    case cloud = "Cloud Model"
    case local = "Local Model (Import)"
}

enum AddModelContext {
    case speechToText
    case enhancement
}

struct AddCustomModelCardView: View {
    @ObservedObject var customModelManager: CustomModelManager
    var editingModel: CustomCloudModel? = nil
    var whisperState: WhisperState? = nil
    var modelContext: AddModelContext = .speechToText
    var onModelAdded: () -> Void

    @State private var isExpanded = false
    @State private var selectedTab: AddModelTab = .cloud
    @State private var displayName = ""
    @State private var apiEndpoint = ""
    @State private var apiKey = ""
    @State private var modelName = ""
    @State private var isMultilingual = true
    @State private var validationErrors: [String] = []
    @State private var showingAlert = false
    @State private var isSaving = false

    private var isEditing: Bool { editingModel != nil }
    private var isFormValid: Bool {
        [displayName, apiEndpoint, apiKey, modelName].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isExpanded {
                Button { prefill(); withAnimation { isExpanded = true } } label: {
                    Label(isEditing ? "Edit Model" : "Add Model", systemImage: "plus")
                }
                .glassActionButton()
                .frame(maxWidth: .infinity)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(isEditing ? "Edit Custom Model" : "Add Model").font(.headline)
                        Spacer()
                        Button { withAnimation { isExpanded = false; clearForm() } } label: {
                            Image(systemName: "xmark")
                        }.buttonStyle(.bordered)
                    }

                    if !isEditing {
                        Picker("", selection: $selectedTab) {
                            ForEach(AddModelTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if selectedTab == .cloud || isEditing {
                        cloudModelForm
                    } else {
                        localImportForm
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .alert("Validation Errors", isPresented: $showingAlert) { Button("OK") {} } message: { Text(validationErrors.joined(separator: "\n")) }
        .onChange(of: editingModel) { _, newValue in
            guard newValue != nil else { return }
            prefill()
            selectedTab = .cloud
            withAnimation { isExpanded = true }
        }
    }

    // MARK: - Cloud Model Form

    private var cloudModelForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            if modelContext == .enhancement {
                Label("Only OpenAI-compatible chat completion APIs are supported", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Only OpenAI-compatible transcription APIs are supported", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }

            FormField(title: "Display Name", text: $displayName, placeholder: "My Custom Model")
            FormField(title: "API Endpoint", text: $apiEndpoint, placeholder: modelContext == .enhancement ? "https://api.example.com/v1/chat/completions" : "https://api.example.com/v1/audio/transcriptions")
            FormField(title: "API Key", text: $apiKey, placeholder: "your-api-key", isSecure: true)
            FormField(title: "Model Name", text: $modelName, placeholder: modelContext == .enhancement ? "gpt-4.1-mini" : "whisper-1")
            Toggle("Multilingual Model", isOn: $isMultilingual)

            HStack(spacing: 12) {
                Button("Cancel") { withAnimation { isExpanded = false; clearForm() } }
                    .buttonStyle(.bordered)
                Button { addModel() } label: {
                    HStack(spacing: 6) {
                        if isSaving { ProgressView().controlSize(.small) }
                        Text(isEditing ? "Update Model" : "Add Model")
                    }
                }
                .glassActionButton()
                .disabled(!isFormValid || isSaving)
            }
        }
    }

    // MARK: - Local Import Form

    private var localImportForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import a local Whisper ggml model file (.bin or .gguf).")
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Cancel") { withAnimation { isExpanded = false; clearForm() } }
                    .buttonStyle(.bordered)
                Button { presentImportPanel() } label: {
                    Label("Choose File...", systemImage: "square.and.arrow.down")
                }
                .glassActionButton()
            }
        }
    }

    // MARK: - Actions

    private func prefill() {
        guard let editing = editingModel else {
            if apiEndpoint.isEmpty {
                apiEndpoint = modelContext == .enhancement
                    ? "https://api.example.com/v1/chat/completions"
                    : "https://api.example.com/v1/audio/transcriptions"
            }
            if modelName.isEmpty {
                modelName = modelContext == .enhancement ? "gpt-4.1-mini" : "large-v3-turbo"
            }
            return
        }
        displayName = editing.displayName; apiEndpoint = editing.apiEndpoint
        apiKey = editing.apiKey; modelName = editing.modelName; isMultilingual = editing.isMultilingualModel
    }

    private func clearForm() {
        displayName = ""; apiEndpoint = ""; apiKey = ""; modelName = ""; isMultilingual = true
        selectedTab = .cloud
    }

    private func addModel() {
        let t = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let name = t(displayName).lowercased().replacingOccurrences(of: " ", with: "-")
        validationErrors = customModelManager.validateModel(name: name, displayName: t(displayName), apiEndpoint: t(apiEndpoint), apiKey: t(apiKey), modelName: t(modelName), excludingId: editingModel?.id)
        guard validationErrors.isEmpty else { showingAlert = true; return }

        isSaving = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let model = CustomCloudModel(id: editingModel?.id ?? UUID(), name: name, displayName: t(displayName), description: "Custom transcription model", apiEndpoint: t(apiEndpoint), modelName: t(modelName), isMultilingual: isMultilingual)
            guard APIKeyManager.shared.saveCustomModelAPIKey(t(apiKey), forModelId: model.id) else {
                validationErrors = ["Failed to save API Key to Keychain."]; showingAlert = true; isSaving = false; return
            }
            if isEditing { customModelManager.updateCustomModel(model) } else { customModelManager.addCustomModel(model) }
            onModelAdded()
            withAnimation { isExpanded = false; clearForm(); isSaving = false }
        }
    }

    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "bin"),
            UTType(filenameExtension: "gguf")
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Select a Whisper ggml model file"
        if panel.runModal() == .OK, let url = panel.url, let ws = whisperState {
            Task { @MainActor in
                await ws.importLocalModel(from: url)
                onModelAdded()
                withAnimation { isExpanded = false; clearForm() }
            }
        }
    }
}

struct FormField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var isSecure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if isSecure {
                SecureField(placeholder, text: $text).textFieldStyle(.roundedBorder)
            } else {
                TextField(placeholder, text: $text).textFieldStyle(.roundedBorder)
            }
        }
    }
}
