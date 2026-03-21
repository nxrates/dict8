import Foundation
import KeyboardShortcuts
import AppKit

extension KeyboardShortcuts.Name {
    static let escapeRecorder = Self("escapeRecorder")
    static let cancelRecorder = Self("cancelRecorder")
    static let toggleEnhancement = Self("toggleEnhancement")

    // AI Prompt and Power Mode selection shortcuts (data-driven)
    static let promptNames: [KeyboardShortcuts.Name] = (1...10).map { .init("selectPrompt\($0)") }
    static let powerModeNames: [KeyboardShortcuts.Name] = (1...10).map { .init("selectPowerMode\($0)") }
}

@MainActor
class MiniRecorderShortcutManager: ObservableObject {
    private var whisperState: WhisperState
    private var visibilityTask: Task<Void, Never>?

    private var isCancelHandlerSetup = false

    // Double-tap Escape handling
    private var escFirstPressTime: Date? = nil
    private let escSecondPressThreshold: TimeInterval = 1.5
    private var isEscapeHandlerSetup = false
    private var escapeTimeoutTask: Task<Void, Never>?

    private static let digitKeys: [KeyboardShortcuts.Key] = [.one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .zero]

    init(whisperState: WhisperState) {
        self.whisperState = whisperState
        setupVisibilityObserver()
        setupEnhancementShortcut()
        setupEscapeHandlerOnce()
        setupCancelHandlerOnce()
        setupPromptHandlers()
        setupPowerModeHandlers()

        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange), name: .AppSettingsDidChange, object: nil)
    }

    @objc private func settingsDidChange() {
        Task {
            if await whisperState.isMiniRecorderVisible {
                if EnhancementShortcutSettings.shared.isToggleEnhancementShortcutEnabled {
                    KeyboardShortcuts.setShortcut(.init(.e, modifiers: .command), for: .toggleEnhancement)
                } else {
                    removeEnhancementShortcut()
                }
            }
        }
    }

    private func setupVisibilityObserver() {
        visibilityTask = Task { @MainActor in
            for await isVisible in whisperState.$isMiniRecorderVisible.values {
                if isVisible {
                    activateEscapeShortcut()
                    activateCancelShortcut()
                    if EnhancementShortcutSettings.shared.isToggleEnhancementShortcutEnabled {
                        KeyboardShortcuts.setShortcut(.init(.e, modifiers: .command), for: .toggleEnhancement)
                    } else {
                        removeEnhancementShortcut()
                    }
                    activatePromptShortcuts()
                    activatePowerModeShortcuts()
                } else {
                    deactivateEscapeShortcut()
                    deactivateCancelShortcut()
                    removeEnhancementShortcut()
                    removePromptShortcuts()
                    removePowerModeShortcuts()
                }
            }
        }
    }

    // Setup escape handler once
    private func setupEscapeHandlerOnce() {
        guard !isEscapeHandlerSetup else { return }
        isEscapeHandlerSetup = true

        KeyboardShortcuts.onKeyDown(for: .escapeRecorder) { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      await self.whisperState.isMiniRecorderVisible else { return }

                // Don't process if custom shortcut is configured
                guard KeyboardShortcuts.getShortcut(for: .cancelRecorder) == nil else { return }

                let now = Date()
                if let firstTime = self.escFirstPressTime,
                   now.timeIntervalSince(firstTime) <= self.escSecondPressThreshold {
                    self.escFirstPressTime = nil
                    await self.whisperState.cancelRecording()
                } else {
                    self.escFirstPressTime = now
                    SoundManager.shared.playEscSound()
                    NotificationManager.shared.showNotification(
                        title: "Press ESC again to cancel recording",
                        type: .info,
                        duration: self.escSecondPressThreshold
                    )
                    self.escapeTimeoutTask = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64((self?.escSecondPressThreshold ?? 1.5) * 1_000_000_000))
                        await MainActor.run {
                            self?.escFirstPressTime = nil
                        }
                    }
                }
            }
        }
    }

    private func activateEscapeShortcut() {
        // Don't activate if custom shortcut is configured
        guard KeyboardShortcuts.getShortcut(for: .cancelRecorder) == nil else { return }
        KeyboardShortcuts.setShortcut(.init(.escape), for: .escapeRecorder)
    }

    // Setup cancel handler once
    private func setupCancelHandlerOnce() {
        guard !isCancelHandlerSetup else { return }
        isCancelHandlerSetup = true

        KeyboardShortcuts.onKeyDown(for: .cancelRecorder) { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      await self.whisperState.isMiniRecorderVisible,
                      KeyboardShortcuts.getShortcut(for: .cancelRecorder) != nil else { return }

                await self.whisperState.cancelRecording()
            }
        }
    }

    private func activateCancelShortcut() {
        // Handler checks if shortcut exists
    }

    private func deactivateEscapeShortcut() {
        KeyboardShortcuts.setShortcut(nil, for: .escapeRecorder)
        escFirstPressTime = nil
        escapeTimeoutTask?.cancel()
        escapeTimeoutTask = nil
    }

    private func deactivateCancelShortcut() {
        // Shortcut managed by user settings
    }

    private func setupEnhancementShortcut() {
        KeyboardShortcuts.onKeyDown(for: .toggleEnhancement) { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      await self.whisperState.isMiniRecorderVisible,
                      let enhancementService = await self.whisperState.getEnhancementService() else { return }
                enhancementService.isEnhancementEnabled.toggle()
            }
        }
    }

    // MARK: - Power Mode Shortcuts (data-driven)

    private func setupPowerModeHandlers() {
        for (i, name) in KeyboardShortcuts.Name.powerModeNames.enumerated() {
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                Task { @MainActor in
                    guard let self = self,
                          await self.whisperState.isMiniRecorderVisible else { return }
                    let powerModeManager = PowerModeManager.shared
                    if !powerModeManager.enabledConfigurations.isEmpty {
                        let availableConfigurations = powerModeManager.enabledConfigurations
                        if i < availableConfigurations.count {
                            let selectedConfig = availableConfigurations[i]
                            powerModeManager.setActiveConfiguration(selectedConfig)
                            await PowerModeSessionManager.shared.beginSession(with: selectedConfig)
                        }
                    }
                }
            }
        }
    }

    private func activatePowerModeShortcuts() {
        for (i, name) in KeyboardShortcuts.Name.powerModeNames.enumerated() {
            KeyboardShortcuts.setShortcut(.init(Self.digitKeys[i], modifiers: .option), for: name)
        }
    }

    private func removePowerModeShortcuts() {
        for name in KeyboardShortcuts.Name.powerModeNames {
            KeyboardShortcuts.setShortcut(nil, for: name)
        }
    }

    // MARK: - Prompt Shortcuts (data-driven)

    private func setupPromptHandlers() {
        for (i, name) in KeyboardShortcuts.Name.promptNames.enumerated() {
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                Task { @MainActor in
                    guard let self = self,
                          await self.whisperState.isMiniRecorderVisible else { return }
                    guard let enhancementService = await self.whisperState.getEnhancementService() else { return }
                    let availablePrompts = enhancementService.allPrompts
                    if i < availablePrompts.count {
                        if !enhancementService.isEnhancementEnabled {
                            enhancementService.isEnhancementEnabled = true
                        }
                        enhancementService.setActivePrompt(availablePrompts[i])
                    }
                }
            }
        }
    }

    private func activatePromptShortcuts() {
        for (i, name) in KeyboardShortcuts.Name.promptNames.enumerated() {
            KeyboardShortcuts.setShortcut(.init(Self.digitKeys[i], modifiers: .command), for: name)
        }
    }

    private func removePromptShortcuts() {
        for name in KeyboardShortcuts.Name.promptNames {
            KeyboardShortcuts.setShortcut(nil, for: name)
        }
    }

    private func removeEnhancementShortcut() {
        KeyboardShortcuts.setShortcut(nil, for: .toggleEnhancement)
    }

    deinit {
        visibilityTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        Task { @MainActor in
            deactivateEscapeShortcut()
            deactivateCancelShortcut()
            removeEnhancementShortcut()
            removePowerModeShortcuts()
        }
    }
}
