import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

struct SettingsView: View {
    #if !LOCAL_BUILD
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    #endif
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @EnvironmentObject private var whisperState: WhisperState
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @StateObject private var deviceManager = AudioDeviceManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    @ObservedObject private var mediaController = MediaController.shared
    @ObservedObject private var playbackController = PlaybackController.shared
    #if !LOCAL_BUILD
    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = true
    #endif
    @AppStorage("restoreClipboardAfterPaste") private var restoreClipboardAfterPaste = true
    @AppStorage("clipboardRestoreDelay") private var clipboardRestoreDelay = 2.0
    @AppStorage("useAppleScriptPaste") private var useAppleScriptPaste = false
    @State private var isCustomCancelEnabled = false
    @State private var isCustomCancelExpanded = false
    @State private var isSoundFeedbackExpanded = false
    @State private var isMuteSystemExpanded = false
    @State private var isRestoreClipboardExpanded = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Hotkey") {
                    HStack(spacing: 8) {
                        hotkeyPicker(binding: $hotkeyManager.selectedHotkey1)
                        if hotkeyManager.selectedHotkey1 == .custom {
                            KeyboardShortcuts.Recorder(for: .toggleMiniRecorder).controlSize(.small)
                        }
                    }
                }
            } header: { Text("Shortcuts") } footer: { Text("Quick tap for hands-free recording, hold for push-to-talk.") }

            Section("Additional Shortcuts") {
                LabeledContent("Paste Last Transcription (Original)") { KeyboardShortcuts.Recorder(for: .pasteLastTranscription).controlSize(.small) }
                LabeledContent("Paste Last Transcription (Enhanced)") { KeyboardShortcuts.Recorder(for: .pasteLastEnhancement).controlSize(.small) }
                LabeledContent("Retry Last Transcription") { KeyboardShortcuts.Recorder(for: .retryLastTranscription).controlSize(.small) }
                ExpandableSettingsRow(isExpanded: $isCustomCancelExpanded, isEnabled: $isCustomCancelEnabled, label: "Custom Cancel Shortcut") {
                    LabeledContent("Shortcut") { KeyboardShortcuts.Recorder(for: .cancelRecorder).controlSize(.small) }
                }
                .onChange(of: isCustomCancelEnabled) { _, newValue in
                    if !newValue { KeyboardShortcuts.setShortcut(nil, for: .cancelRecorder); isCustomCancelExpanded = false }
                }
            }

            Section("Recording Feedback") {
                ExpandableSettingsRow(isExpanded: $isSoundFeedbackExpanded, isEnabled: $soundManager.isEnabled, label: "Sound Feedback") { EmptyView() }
                ExpandableSettingsRow(isExpanded: $isMuteSystemExpanded, isEnabled: $mediaController.isSystemMuteEnabled, label: "Mute Audio While Recording") {
                    Picker("Resume Delay", selection: $mediaController.audioResumptionDelay) {
                        Text("0s").tag(0.0); Text("1s").tag(1.0); Text("2s").tag(2.0); Text("3s").tag(3.0); Text("4s").tag(4.0); Text("5s").tag(5.0)
                    }
                }
                ExpandableSettingsRow(isExpanded: $isRestoreClipboardExpanded, isEnabled: $restoreClipboardAfterPaste, label: "Restore Clipboard After Paste") {
                    Picker("Restore Delay", selection: $clipboardRestoreDelay) {
                        Text("250ms").tag(0.25); Text("500ms").tag(0.5); Text("1s").tag(1.0); Text("2s").tag(2.0); Text("3s").tag(3.0); Text("4s").tag(4.0); Text("5s").tag(5.0)
                    }
                }
                Toggle(isOn: $useAppleScriptPaste) {
                    HStack(spacing: 4) {
                        Text("Use AppleScript Paste")
                        InfoTip("Enable this if pasting doesn't work with your keyboard layout (e.g. Neo2). Uses AppleScript instead of simulated key events.")
                    }
                }
            }

            PowerModeSection()
            Section("Interface") {
                Picker("Recorder Style", selection: $whisperState.recorderType) {
                    Text("Notch").tag("notch"); Text("Mini").tag("mini")
                }.pickerStyle(.segmented)
            }
            ExperimentalSection()

            Section("General") {
                Toggle("Hide Dock Icon", isOn: $menuBarManager.isMenuBarOnly)
                LaunchAtLogin.Toggle("Launch at Login")
                #if !LOCAL_BUILD
                Toggle("Auto-check Updates", isOn: $autoUpdateCheck)
                    .onChange(of: autoUpdateCheck) { _, newValue in updaterViewModel.toggleAutoUpdates(newValue) }
                Button("Check for Updates") { updaterViewModel.checkForUpdates() }.disabled(!updaterViewModel.canCheckForUpdates)
                #endif
            }

            Section { AudioCleanupSettingsView() } header: { Text("Privacy") } footer: {
                Text("Control how Dict8 handles your transcription data and audio recordings.")
            }

            Section {
                LabeledContent("Export Settings") {
                    Button("Export") {
                        ImportExportService.shared.exportSettings(
                            enhancementService: enhancementService, whisperPrompt: WhisperPrompt(),
                            hotkeyManager: hotkeyManager, menuBarManager: menuBarManager,
                            mediaController: mediaController, playbackController: playbackController,
                            soundManager: soundManager, whisperState: whisperState)
                    }
                }
                LabeledContent("Import Settings") {
                    Button("Import") {
                        ImportExportService.shared.importSettings(
                            enhancementService: enhancementService, whisperPrompt: WhisperPrompt(),
                            hotkeyManager: hotkeyManager, menuBarManager: menuBarManager,
                            mediaController: mediaController, playbackController: playbackController,
                            soundManager: soundManager, whisperState: whisperState)
                    }
                }
            } header: { Text("Backup") } footer: {
                Text("Export or import all your settings, prompts, power modes, dictionary, and custom models.")
            }

            Section("Audio Input") {
                Picker("Mode", selection: Binding(
                    get: { deviceManager.inputMode },
                    set: { deviceManager.selectInputMode($0) }
                )) {
                    ForEach(AudioInputMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch deviceManager.inputMode {
                case .systemDefault:
                    LabeledContent("Active Device") {
                        Text(deviceManager.getSystemDefaultDeviceName() ?? "No device available")
                            .foregroundColor(.secondary)
                    }
                case .custom:
                    ForEach(deviceManager.availableDevices, id: \.id) { device in
                        Button {
                            deviceManager.selectDevice(id: device.id)
                        } label: {
                            HStack {
                                Image(systemName: deviceManager.selectedDeviceID == device.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(deviceManager.selectedDeviceID == device.id ? .accentColor : .secondary)
                                Text(device.name).foregroundColor(.primary)
                                Spacer()
                                if deviceManager.getCurrentDevice() == device.id {
                                    Text("Active").font(.caption).foregroundColor(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            PermissionsSectionsView()
        }
        .formStyle(.grouped)
        .onAppear { isCustomCancelEnabled = KeyboardShortcuts.getShortcut(for: .cancelRecorder) != nil }
    }

    @ViewBuilder
    private func hotkeyPicker(binding: Binding<HotkeyManager.HotkeyOption>) -> some View {
        Picker("", selection: binding) {
            ForEach(HotkeyManager.HotkeyOption.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }.labelsHidden().frame(width: 140)
    }
}

// MARK: - Expandable Settings Row

struct ExpandableSettingsRow<Content: View>: View {
    @Binding var isExpanded: Bool
    @Binding var isEnabled: Bool
    let label: String
    var infoMessage: String? = nil
    var infoURL: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { isEnabled && isExpanded },
            set: { isExpanded = $0 }
        )) {
            content()
        } label: {
            Toggle(isOn: $isEnabled) {
                HStack(spacing: 4) {
                    Text(label)
                    if let message = infoMessage {
                        if let url = infoURL { InfoTip(message, learnMoreURL: url) } else { InfoTip(message) }
                    }
                }
            }
        }
        .onChange(of: isEnabled) { _, newValue in
            if newValue { isExpanded = true } else { isExpanded = false }
        }
    }
}

// MARK: - Power Mode Section

struct PowerModeSection: View {
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    @AppStorage("powerModeUIFlag") private var powerModeUIFlag = false
    @AppStorage(PowerModeDefaults.autoRestoreKey) private var powerModeAutoRestoreEnabled = false
    @State private var showDisableAlert = false
    @State private var isExpanded = false

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { powerModeUIFlag },
            set: { new in
                if new { powerModeUIFlag = true }
                else if powerModeManager.configurations.allSatisfy({ !$0.isEnabled }) { powerModeUIFlag = false }
                else { showDisableAlert = true }
            })
    }

    var body: some View {
        Section {
            ExpandableSettingsRow(isExpanded: $isExpanded, isEnabled: toggleBinding, label: "Power Mode",
                infoMessage: "Apply custom settings based on active app or website.", infoURL: "https://github.com/pde-rent/dict8 {
                Toggle(isOn: $powerModeAutoRestoreEnabled) {
                    HStack(spacing: 4) {
                        Text("Auto-Restore Preferences")
                        InfoTip("After each recording session, revert preferences to what was configured before Power Mode was activated.")
                    }
                }
            }
        } header: { Text("Power Mode") }
        .alert("Power Mode Still Active", isPresented: $showDisableAlert) {
            Button("Got it", role: .cancel) {}
        } message: { Text("Disable or remove your Power Modes first.") }
    }
}

// MARK: - Experimental Section

struct ExperimentalSection: View {
    @ObservedObject private var playbackController = PlaybackController.shared
    @ObservedObject private var mediaController = MediaController.shared
    @State private var isPauseMediaExpanded = false

    var body: some View {
        Section {
            ExpandableSettingsRow(isExpanded: $isPauseMediaExpanded, isEnabled: $playbackController.isPauseMediaEnabled,
                label: "Pause Media While Recording", infoMessage: "Pauses playing media when recording starts and resumes when done.") {
                Picker("Resume Delay", selection: $mediaController.audioResumptionDelay) {
                    Text("0s").tag(0.0); Text("1s").tag(1.0); Text("2s").tag(2.0); Text("3s").tag(3.0); Text("4s").tag(4.0); Text("5s").tag(5.0)
                }
            }
        } header: { Text("Experimental") }
    }
}

// MARK: - Power Mode Defaults

enum PowerModeDefaults {
    static let autoRestoreKey = "powerModeAutoRestoreEnabled"
}
