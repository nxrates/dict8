import SwiftUI
import LaunchAtLogin

struct MenuBarView: View {
    @EnvironmentObject var whisperState: WhisperState
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var menuBarManager: MenuBarManager
    #if !LOCAL_BUILD
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
    #endif
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var aiService: AIService
    @ObservedObject var audioDeviceManager = AudioDeviceManager.shared
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var menuRefreshTrigger = false

    var body: some View {
        VStack {
            Button("Toggle Recorder") { whisperState.handleToggleMiniRecorder() }
            Divider()

            // Transcription Model
            Menu {
                ForEach(whisperState.usableModels, id: \.id) { model in
                    Button { Task { await whisperState.setDefaultTranscriptionModel(model) } } label: {
                        HStack { Text(model.displayName); if whisperState.currentTranscriptionModel?.id == model.id { Image(systemName: "checkmark") } }
                    }
                }
                Divider()
                Button("Manage Models") { menuBarManager.openMainWindowAndNavigate(to: "AI Models") }
            } label: { Text("Model: \(whisperState.currentTranscriptionModel?.displayName ?? "None")") }

            Divider()
            Toggle("AI Enhancement", isOn: $enhancementService.isEnhancementEnabled)
            Button { enhancementService.useScreenCaptureContext.toggle(); menuRefreshTrigger.toggle() } label: {
                HStack { Text("Screen Context"); Spacer(); if enhancementService.useScreenCaptureContext { Image(systemName: "checkmark") } }
            }.id("screen-context-\(menuRefreshTrigger)")

            // Prompt
            Menu {
                ForEach(enhancementService.allPrompts) { prompt in
                    Button { enhancementService.setActivePrompt(prompt) } label: {
                        HStack { Image(systemName: prompt.icon).foregroundColor(.accentColor); Text(prompt.title); if enhancementService.selectedPromptId == prompt.id { Spacer(); Image(systemName: "checkmark") } }
                    }
                }
            } label: { Text("Prompt: \(enhancementService.activePrompt?.title ?? "None")") }

            // AI Provider
            Menu {
                ForEach(aiService.connectedProviders, id: \.self) { provider in
                    Button { aiService.selectedProvider = provider } label: {
                        HStack { Text(provider.rawValue); if aiService.selectedProvider == provider { Image(systemName: "checkmark") } }
                    }
                }
                if aiService.connectedProviders.isEmpty { Text("No providers connected").foregroundColor(.secondary) }
            } label: { Text("AI Provider: \(aiService.selectedProvider.rawValue)") }

            // AI Model
            Menu {
                ForEach(aiService.availableModels, id: \.self) { model in
                    Button { aiService.selectModel(model) } label: {
                        HStack { Text(model); if aiService.currentModel == model { Image(systemName: "checkmark") } }
                    }
                }
                if aiService.availableModels.isEmpty { Text("No models available").foregroundColor(.secondary) }
            } label: { Text("AI Model: \(aiService.currentModel)") }

            LanguageSelectionView(whisperState: whisperState, displayMode: .menuItem, whisperPrompt: whisperState.whisperPrompt)

            // Audio Input
            Menu {
                ForEach(audioDeviceManager.availableDevices, id: \.id) { device in
                    Button { audioDeviceManager.selectDeviceAndSwitchToCustomMode(id: device.id) } label: {
                        HStack { Text(device.name); if audioDeviceManager.getCurrentDevice() == device.id { Image(systemName: "checkmark") } }
                    }
                }
                if audioDeviceManager.availableDevices.isEmpty { Text("No devices available").foregroundColor(.secondary) }
            } label: { Text("Audio Input") }

            Menu("Additional") {
                Button { enhancementService.useClipboardContext.toggle(); menuRefreshTrigger.toggle() } label: {
                    HStack { Text("Clipboard Context"); Spacer(); if enhancementService.useClipboardContext { Image(systemName: "checkmark") } }
                }
            }.id("additional-menu-\(menuRefreshTrigger)")

            Divider()
            Button("Retry Last Transcription") { LastTranscriptionService.retryLastTranscription(from: whisperState.modelContext, whisperState: whisperState) }
            Button("Copy Last Transcription") { LastTranscriptionService.copyLastTranscription(from: whisperState.modelContext) }.keyboardShortcut("c", modifiers: [.command, .shift])
            Button("History") { menuBarManager.openMainWindowAndNavigate(to: "History") }.keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Settings") { menuBarManager.openMainWindowAndNavigate(to: "Settings") }.keyboardShortcut(",", modifiers: .command)
            Button(menuBarManager.isMenuBarOnly ? "Show Dock Icon" : "Hide Dock Icon") { menuBarManager.toggleMenuBarOnly() }.keyboardShortcut("d", modifiers: [.command, .shift])
            Toggle("Launch at Login", isOn: $launchAtLoginEnabled).onChange(of: launchAtLoginEnabled) { _, newValue in LaunchAtLogin.isEnabled = newValue }
            Divider()
            #if !LOCAL_BUILD
            Button("Check for Updates") { updaterViewModel.checkForUpdates() }.disabled(!updaterViewModel.canCheckForUpdates)
            #endif
            Button("Help and Support") { EmailSupport.openSupportEmail() }
            Divider()
            Button("Quit Dict8") { NSApplication.shared.terminate(nil) }
        }
    }
}
