import SwiftUI
import KeyboardShortcuts

struct ConfigurationView: View {
    let mode: ConfigurationMode
    let powerModeManager: PowerModeManager
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var aiService: AIService
    @EnvironmentObject private var whisperState: WhisperState
    @Environment(\.presentationMode) private var presentationMode
    @FocusState private var isNameFieldFocused: Bool

    @State private var configName = ""
    @State private var selectedEmoji = "✏️"
    @State private var isAIEnhancementEnabled = false
    @State private var selectedPromptId: UUID?
    @State private var selectedTranscriptionModelName: String?
    @State private var selectedLanguage: String?
    @State private var selectedAIProvider: String?
    @State private var selectedAIModel: String?
    @State private var selectedAppConfigs: [AppConfig] = []
    @State private var websiteConfigs: [URLConfig] = []
    @State private var newWebsiteURL = ""
    @State private var useScreenCapture = false
    @State private var isAutoSendEnabled = false
    @State private var isDefault = false
    @State private var isShowingDeleteConfirmation = false
    @State private var powerModeConfigId = UUID()
    @State private var isShowingAppPicker = false
    @State private var validationError: String?
    @State private var showValidationAlert = false

    private var effectiveModelName: String? {
        selectedTranscriptionModelName ?? whisperState.currentTranscriptionModel?.name
    }

    private var languageSelectionDisabled: Bool {
        guard let name = effectiveModelName,
              let model = whisperState.allAvailableModels.first(where: { $0.name == name })
        else { return false }
        return model.provider == .parakeet || model.provider == .gemini
    }

    private var canSave: Bool { !configName.isEmpty }

    init(mode: ConfigurationMode, powerModeManager: PowerModeManager) {
        self.mode = mode
        self.powerModeManager = powerModeManager
        switch mode {
        case .add:
            let newId = UUID()
            _powerModeConfigId = State(initialValue: newId)
            _selectedAIProvider = State(initialValue: UserDefaults.standard.string(forKey: "selectedAIProvider"))
        case .edit(let c):
            let c = powerModeManager.getConfiguration(with: c.id) ?? c
            _powerModeConfigId = State(initialValue: c.id)
            _configName = State(initialValue: c.name)
            _selectedEmoji = State(initialValue: c.emoji)
            _isAIEnhancementEnabled = State(initialValue: c.isAIEnhancementEnabled)
            _selectedPromptId = State(initialValue: c.selectedPrompt.flatMap { UUID(uuidString: $0) })
            _selectedTranscriptionModelName = State(initialValue: c.selectedTranscriptionModelName)
            _selectedLanguage = State(initialValue: c.selectedLanguage)
            _selectedAppConfigs = State(initialValue: c.appConfigs ?? [])
            _websiteConfigs = State(initialValue: c.urlConfigs ?? [])
            _useScreenCapture = State(initialValue: c.useScreenCapture)
            _isAutoSendEnabled = State(initialValue: c.isAutoSendEnabled)
            _isDefault = State(initialValue: c.isDefault)
            _selectedAIProvider = State(initialValue: c.selectedAIProvider)
            _selectedAIModel = State(initialValue: c.selectedAIModel)
        }
    }

    var body: some View {
        Form {
            Section("General") {
                HStack(spacing: 12) {
                    TextField("", text: $selectedEmoji)
                        .frame(width: 44).font(.title).multilineTextAlignment(.center)
                        .onChange(of: selectedEmoji) { _, val in
                            let cleaned = String(val.filter { $0.unicodeScalars.allSatisfy { $0.properties.isEmoji } }.prefix(1))
                            if selectedEmoji != cleaned && !cleaned.isEmpty { selectedEmoji = cleaned }
                        }
                    TextField("Name", text: $configName)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFieldFocused)
                }
            }

            Section("Trigger Apps") {
                ForEach(selectedAppConfigs) { app in
                    HStack {
                        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                                .resizable().frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "app.fill").frame(width: 24, height: 24)
                        }
                        Text(app.appName)
                        Spacer()
                        Button { selectedAppConfigs.removeAll { $0.id == app.id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundColor(.red)
                        }.buttonStyle(.plain)
                    }
                }
                Button("Add from Running Apps...") { isShowingAppPicker = true }
            }

            Section("Trigger URLs") {
                ForEach(websiteConfigs) { urlConfig in
                    HStack {
                        Image(systemName: "globe").foregroundColor(.secondary)
                        Text(urlConfig.url).lineLimit(1)
                        Spacer()
                        Button { websiteConfigs.removeAll { $0.id == urlConfig.id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundColor(.red)
                        }.buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("e.g. google.com", text: $newWebsiteURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addWebsite() }
                    Button("Add") { addWebsite() }.disabled(newWebsiteURL.isEmpty)
                }
            }

            Section("Transcription") {
                if whisperState.usableModels.isEmpty {
                    Text("No transcription models available.")
                        .foregroundColor(.secondary)
                } else {
                    Picker("Model", selection: Binding(
                        get: { selectedTranscriptionModelName ?? whisperState.currentTranscriptionModel?.name },
                        set: { selectedTranscriptionModelName = $0 }
                    )) {
                        ForEach(whisperState.usableModels, id: \.name) { model in
                            Text(model.displayName).tag(model.name as String?)
                        }
                    }
                    .onChange(of: selectedTranscriptionModelName) { _, newName in
                        if let name = newName ?? whisperState.currentTranscriptionModel?.name,
                           let model = whisperState.allAvailableModels.first(where: { $0.name == name }),
                           model.provider == .parakeet || model.provider == .gemini {
                            selectedLanguage = "auto"
                        }
                    }
                }

                if languageSelectionDisabled {
                    LabeledContent("Language") { Text("Autodetected").foregroundColor(.secondary) }
                        .onAppear { selectedLanguage = "auto" }
                } else if let modelName = effectiveModelName,
                          let modelInfo = whisperState.allAvailableModels.first(where: { $0.name == modelName }),
                          modelInfo.isMultilingualModel {
                    Picker("Language", selection: Binding(
                        get: { selectedLanguage ?? UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto" },
                        set: { selectedLanguage = $0 }
                    )) {
                        ForEach(modelInfo.supportedLanguages.sorted(by: {
                            if $0.key == "auto" { return true }; if $1.key == "auto" { return false }
                            return $0.value < $1.value
                        }), id: \.key) { key, value in
                            Text(value).tag(key as String?)
                        }
                    }
                } else if let modelName = effectiveModelName,
                          let modelInfo = whisperState.allAvailableModels.first(where: { $0.name == modelName }),
                          !modelInfo.isMultilingualModel {
                    EmptyView().onAppear { if selectedLanguage == nil { selectedLanguage = "en" } }
                }
            }

            Section("AI Enhancement") {
                Toggle("Enable AI Enhancement", isOn: $isAIEnhancementEnabled)
                    .onChange(of: isAIEnhancementEnabled) { _, on in
                        guard on else { return }
                        if selectedAIProvider == nil { selectedAIProvider = aiService.selectedProvider.rawValue }
                        if selectedAIModel == nil { selectedAIModel = aiService.currentModel }
                        if selectedPromptId == nil { selectedPromptId = enhancementService.allPrompts.first?.id }
                    }

                if isAIEnhancementEnabled {
                    aiProviderPicker
                    aiModelPicker
                    promptPicker
                    Toggle("Screen Context", isOn: $useScreenCapture)
                }
            }

            Section("Advanced") {
                Toggle(isOn: $isDefault) {
                    HStack(spacing: 6) {
                        Text("Set as default")
                        InfoTip("Default power mode is used when no specific app or website matches are found.")
                    }
                }
                Toggle(isOn: $isAutoSendEnabled) {
                    HStack(spacing: 6) {
                        Text("Auto Send")
                        InfoTip("Automatically presses the Return/Enter key after pasting text.")
                    }
                }
                HStack {
                    Text("Keyboard Shortcut")
                    InfoTip("Assign a unique keyboard shortcut to instantly activate this Power Mode.")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .powerMode(id: powerModeConfigId))
                        .controlSize(.regular).frame(minHeight: 28)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
        .navigationTitle(mode.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") { saveConfiguration() }
                    .keyboardShortcut(.defaultAction).disabled(!canSave)
                    .buttonStyle(.bordered).controlSize(.regular)
            }
            if case .edit = mode {
                ToolbarItem {
                    Button("Delete", role: .destructive) { isShowingDeleteConfirmation = true }
                        .buttonStyle(.bordered).controlSize(.regular)
                }
            }
        }
        .confirmationDialog("Delete Power Mode?", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            if case .edit(let config) = mode {
                Button("Delete", role: .destructive) {
                    powerModeManager.removeConfiguration(with: config.id)
                    presentationMode.wrappedValue.dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if case .edit(let config) = mode {
                Text("Are you sure you want to delete '\(config.name)'? This cannot be undone.")
            }
        }
        .sheet(isPresented: $isShowingAppPicker) {
            RunningAppsPicker(selectedAppConfigs: $selectedAppConfigs, isPresented: $isShowingAppPicker)
        }
        .alert("Cannot Save", isPresented: $showValidationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationError ?? "Please fix errors before saving.")
        }
        .onAppear {
            if case .add = mode {
                if selectedAIProvider == nil { selectedAIProvider = aiService.selectedProvider.rawValue }
                if selectedAIModel == nil || selectedAIModel?.isEmpty == true { selectedAIModel = aiService.currentModel }
            }
            if isAIEnhancementEnabled && selectedPromptId == nil {
                selectedPromptId = enhancementService.allPrompts.first?.id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isNameFieldFocused = true }
        }
    }

    // MARK: - AI Pickers

    @ViewBuilder private var aiProviderPicker: some View {
        let binding = Binding<AIProvider>(
            get: { selectedAIProvider.flatMap(AIProvider.init(rawValue:)) ?? aiService.selectedProvider },
            set: { selectedAIProvider = $0.rawValue; aiService.selectedProvider = $0; selectedAIModel = nil }
        )
        if aiService.connectedProviders.isEmpty {
            LabeledContent("AI Provider") { Text("No providers connected").foregroundColor(.secondary).italic() }
        } else {
            Picker("AI Provider", selection: binding) {
                ForEach(aiService.connectedProviders.filter { $0 != .elevenLabs && $0 != .deepgram }, id: \.self) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .onChange(of: selectedAIProvider) { _, val in
                if let p = val.flatMap({ AIProvider(rawValue: $0) }) { selectedAIModel = p.defaultModel }
            }
        }
    }

    @ViewBuilder private var aiModelPicker: some View {
        let providerName = selectedAIProvider ?? aiService.selectedProvider.rawValue
        if let provider = AIProvider(rawValue: providerName), provider != .custom {
            if aiService.availableModels.isEmpty {
                LabeledContent("AI Model") {
                    Text(provider == .openRouter ? "No models loaded" : "No models available")
                        .foregroundColor(.secondary).italic()
                }
            } else {
                let models = (provider == .openRouter || provider == .ollama) ? aiService.availableModels : provider.availableModels
                Picker("AI Model", selection: Binding(
                    get: { (selectedAIModel?.isEmpty == false ? selectedAIModel : nil) ?? aiService.currentModel },
                    set: { selectedAIModel = $0; aiService.selectModel($0) }
                )) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                if provider == .openRouter {
                    Button("Refresh Models") { Task { await aiService.fetchOpenRouterModels() } }
                }
            }
        }
    }

    @ViewBuilder private var promptPicker: some View {
        if enhancementService.allPrompts.isEmpty {
            LabeledContent("Enhancement Prompt") { Text("No prompts available").foregroundColor(.secondary) }
        } else {
            Picker("Enhancement Prompt", selection: $selectedPromptId) {
                ForEach(enhancementService.allPrompts) { Text($0.title).tag($0.id as UUID?) }
            }
        }
    }

    // MARK: - Actions

    private func addWebsite() {
        guard !newWebsiteURL.isEmpty else { return }
        websiteConfigs.append(URLConfig(url: powerModeManager.cleanURL(newWebsiteURL)))
        newWebsiteURL = ""
    }

    private func getConfigForForm() -> PowerModeConfig {
        let shortcut = KeyboardShortcuts.getShortcut(for: .powerMode(id: powerModeConfigId))
        var config: PowerModeConfig
        if case .edit(let existing) = mode { config = existing }
        else { config = PowerModeConfig(id: powerModeConfigId, name: "", emoji: "", isAIEnhancementEnabled: false) }
        config.name = configName; config.emoji = selectedEmoji
        config.appConfigs = selectedAppConfigs.isEmpty ? nil : selectedAppConfigs
        config.urlConfigs = websiteConfigs.isEmpty ? nil : websiteConfigs
        config.isAIEnhancementEnabled = isAIEnhancementEnabled
        config.selectedPrompt = selectedPromptId?.uuidString
        config.selectedTranscriptionModelName = selectedTranscriptionModelName
        config.selectedLanguage = selectedLanguage; config.useScreenCapture = useScreenCapture
        config.selectedAIProvider = selectedAIProvider; config.selectedAIModel = selectedAIModel
        config.isAutoSendEnabled = isAutoSendEnabled; config.isDefault = isDefault
        config.hotkeyShortcut = shortcut != nil ? "configured" : nil
        return config
    }

    private func saveConfiguration() {
        let config = getConfigForForm()
        let editId: UUID? = if case .edit(let c) = mode { c.id } else { nil }
        let others = powerModeManager.configurations.filter { $0.id != editId }
        if others.contains(where: { $0.name == config.name }) {
            validationError = "A power mode named '\(config.name)' already exists."
            showValidationAlert = true; return
        }
        if isDefault { powerModeManager.setAsDefault(configId: config.id, skipSave: true) }
        switch mode {
        case .add: powerModeManager.addConfiguration(config)
        case .edit: powerModeManager.updateConfiguration(config)
        }
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Running Apps Picker

private struct RunningAppsPicker: View {
    @Binding var selectedAppConfigs: [AppConfig]
    @Binding var isPresented: Bool

    private var runningApps: [(name: String, bundleId: String, icon: NSImage)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let name = app.localizedName, let bid = app.bundleIdentifier else { return nil }
                let icon = app.icon ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)!
                return (name: name, bundleId: bid, icon: icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Running Applications").font(.headline)
                Spacer()
                Button("Done") { isPresented = false }.keyboardShortcut(.return, modifiers: [])
            }
            List(runningApps, id: \.bundleId) { app in
                let isSelected = selectedAppConfigs.contains { $0.bundleIdentifier == app.bundleId }
                HStack {
                    Image(nsImage: app.icon).resizable().frame(width: 24, height: 24)
                    Text(app.name)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark").foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if isSelected {
                        selectedAppConfigs.removeAll { $0.bundleIdentifier == app.bundleId }
                    } else {
                        selectedAppConfigs.append(AppConfig(bundleIdentifier: app.bundleId, appName: app.name))
                    }
                }
            }
        }
        .padding()
        .frame(width: 400, height: 400)
    }
}
