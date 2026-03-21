import Foundation
import KeyboardShortcuts
import Carbon
import AppKit
import os

extension KeyboardShortcuts.Name {
    static let toggleMiniRecorder = Self("toggleMiniRecorder")
    static let pasteLastTranscription = Self("pasteLastTranscription")
    static let pasteLastEnhancement = Self("pasteLastEnhancement")
    static let retryLastTranscription = Self("retryLastTranscription")
    static let openHistoryWindow = Self("openHistoryWindow")
}

@MainActor
class HotkeyManager: ObservableObject {
    @Published var selectedHotkey1: HotkeyOption {
        didSet {
            UserDefaults.standard.set(selectedHotkey1.rawValue, forKey: "selectedHotkey1")
            setupHotkeyMonitoring()
        }
    }

    private let logger = Logger(subsystem: "com.prakashjoshipax.dict8", category: "HotkeyManager")
    private var whisperState: WhisperState
    private var miniRecorderShortcutManager: MiniRecorderShortcutManager
    private var powerModeShortcutManager: PowerModeShortcutManager

    // MARK: - Helper Properties
    private var canProcessHotkeyAction: Bool {
        whisperState.recordingState != .transcribing && whisperState.recordingState != .enhancing && whisperState.recordingState != .busy
    }

    // NSEvent monitoring for modifier keys
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

    // Unified press tracking for modifier keys and custom shortcuts
    private var modifierTracker = PressTracker()
    private var shortcutTracker = PressTracker()
    private let briefPressThreshold = 0.5

    // Debounce for Fn key
    private var fnDebounceTask: Task<Void, Never>?
    private var pendingFnKeyState: Bool? = nil
    private var pendingFnEventTime: TimeInterval? = nil

    // Custom shortcut cooldown
    private var lastShortcutTriggerTime: Date?
    private let shortcutCooldownInterval: TimeInterval = 0.5

    enum HotkeyOption: String, CaseIterable {
        case none = "none"
        case rightOption = "rightOption"
        case leftOption = "leftOption"
        case leftControl = "leftControl"
        case rightControl = "rightControl"
        case fn = "fn"
        case rightCommand = "rightCommand"
        case rightShift = "rightShift"
        case custom = "custom"

        var displayName: String {
            switch self {
            case .none: return "None"
            case .rightOption: return "Right Option (\u{2325})"
            case .leftOption: return "Left Option (\u{2325})"
            case .leftControl: return "Left Control (\u{2303})"
            case .rightControl: return "Right Control (\u{2303})"
            case .fn: return "Fn"
            case .rightCommand: return "Right Command (\u{2318})"
            case .rightShift: return "Right Shift (\u{21E7})"
            case .custom: return "Custom"
            }
        }

        var keyCode: CGKeyCode? {
            switch self {
            case .rightOption: return 0x3D
            case .leftOption: return 0x3A
            case .leftControl: return 0x3B
            case .rightControl: return 0x3E
            case .fn: return 0x3F
            case .rightCommand: return 0x36
            case .rightShift: return 0x3C
            case .custom, .none: return nil
            }
        }

        var isModifierKey: Bool {
            return self != .custom && self != .none
        }
    }

    // MARK: - PressTracker

    private enum TrackerKind { case modifier, shortcut }

    private struct PressTracker {
        var currentKeyState = false
        var pressEventTime: TimeInterval?
        var isHandsFreeMode = false

        mutating func reset() {
            currentKeyState = false
            pressEventTime = nil
            isHandsFreeMode = false
        }
    }

    private func tracker(for kind: TrackerKind) -> PressTracker {
        switch kind {
        case .modifier: return modifierTracker
        case .shortcut: return shortcutTracker
        }
    }

    private func setTracker(_ value: PressTracker, for kind: TrackerKind) {
        switch kind {
        case .modifier: modifierTracker = value
        case .shortcut: shortcutTracker = value
        }
    }

    init(whisperState: WhisperState) {
        self.selectedHotkey1 = HotkeyOption(rawValue: UserDefaults.standard.string(forKey: "selectedHotkey1") ?? "") ?? .rightCommand

        self.whisperState = whisperState
        self.miniRecorderShortcutManager = MiniRecorderShortcutManager(whisperState: whisperState)
        self.powerModeShortcutManager = PowerModeShortcutManager(whisperState: whisperState)

        KeyboardShortcuts.onKeyUp(for: .pasteLastTranscription) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                LastTranscriptionService.pasteLastTranscription(from: self.whisperState.modelContext)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .pasteLastEnhancement) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                LastTranscriptionService.pasteLastEnhancement(from: self.whisperState.modelContext)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .retryLastTranscription) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                LastTranscriptionService.retryLastTranscription(from: self.whisperState.modelContext, whisperState: self.whisperState)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .openHistoryWindow) {
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .navigateToDestination,
                    object: nil,
                    userInfo: ["destination": "History"]
                )
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.setupHotkeyMonitoring()
        }
    }

    private func setupHotkeyMonitoring() {
        removeAllMonitoring()
        setupModifierKeyMonitoring()
        setupCustomShortcutMonitoring()
    }

    private func setupModifierKeyMonitoring() {
        guard selectedHotkey1.isModifierKey && selectedHotkey1 != .none else { return }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            Task { @MainActor in
                await self.handleModifierKeyEvent(event)
            }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            Task { @MainActor in
                await self.handleModifierKeyEvent(event)
            }
            return event
        }
    }

    private func setupCustomShortcutMonitoring() {
        if selectedHotkey1 == .custom {
            KeyboardShortcuts.onKeyDown(for: .toggleMiniRecorder) { [weak self] in
                let eventTime = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in await self?.handleCustomShortcutKeyDown(eventTime: eventTime) }
            }
            KeyboardShortcuts.onKeyUp(for: .toggleMiniRecorder) { [weak self] in
                let eventTime = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in await self?.handleCustomShortcutKeyUp(eventTime: eventTime) }
            }
        }
    }

    private func removeAllMonitoring() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        modifierTracker.reset()
        shortcutTracker.reset()
    }

    private func handleModifierKeyEvent(_ event: NSEvent) async {
        let keycode = event.keyCode
        let flags = event.modifierFlags
        let eventTime = event.timestamp

        guard selectedHotkey1.isModifierKey && selectedHotkey1.keyCode == keycode else { return }

        var isKeyPressed = false

        switch selectedHotkey1 {
        case .rightOption, .leftOption:
            isKeyPressed = flags.contains(.option)
        case .leftControl, .rightControl:
            isKeyPressed = flags.contains(.control)
        case .fn:
            isKeyPressed = flags.contains(.function)
            pendingFnKeyState = isKeyPressed
            pendingFnEventTime = eventTime
            fnDebounceTask?.cancel()
            fnDebounceTask = Task { [pendingState = isKeyPressed, pendingTime = eventTime] in
                try? await Task.sleep(nanoseconds: 75_000_000)
                if pendingFnKeyState == pendingState {
                    await self.processPress(kind: .modifier, isKeyPressed: pendingState, eventTime: pendingTime)
                }
            }
            return
        case .rightCommand:
            isKeyPressed = flags.contains(.command)
        case .rightShift:
            isKeyPressed = flags.contains(.shift)
        case .custom, .none:
            return
        }

        await processPress(kind: .modifier, isKeyPressed: isKeyPressed, eventTime: eventTime)
    }

    private func processPress(kind: TrackerKind, isKeyPressed: Bool, eventTime: TimeInterval) async {
        var t = tracker(for: kind)
        guard isKeyPressed != t.currentKeyState else { return }
        t.currentKeyState = isKeyPressed

        if isKeyPressed {
            t.pressEventTime = eventTime

            if t.isHandsFreeMode {
                t.isHandsFreeMode = false
                setTracker(t, for: kind)
                guard canProcessHotkeyAction else { return }
                await whisperState.handleToggleMiniRecorder()
                return
            }

            setTracker(t, for: kind)
            if !whisperState.isMiniRecorderVisible {
                guard canProcessHotkeyAction else { return }
                await whisperState.handleToggleMiniRecorder()
            }
        } else {
            if let startTime = t.pressEventTime {
                let pressDuration = eventTime - startTime

                if pressDuration < briefPressThreshold {
                    t.isHandsFreeMode = true
                } else {
                    t.pressEventTime = nil
                    setTracker(t, for: kind)
                    guard canProcessHotkeyAction else { return }
                    await whisperState.handleToggleMiniRecorder()
                    return
                }
            }
            t.pressEventTime = nil
            setTracker(t, for: kind)
        }
    }

    private func handleCustomShortcutKeyDown(eventTime: TimeInterval) async {
        if let lastTrigger = lastShortcutTriggerTime,
           Date().timeIntervalSince(lastTrigger) < shortcutCooldownInterval {
            return
        }

        guard !shortcutTracker.currentKeyState else { return }
        shortcutTracker.currentKeyState = true
        lastShortcutTriggerTime = Date()
        shortcutTracker.pressEventTime = eventTime

        if shortcutTracker.isHandsFreeMode {
            shortcutTracker.isHandsFreeMode = false
            guard canProcessHotkeyAction else { return }
            await whisperState.handleToggleMiniRecorder()
            return
        }

        if !whisperState.isMiniRecorderVisible {
            guard canProcessHotkeyAction else { return }
            await whisperState.handleToggleMiniRecorder()
        }
    }

    private func handleCustomShortcutKeyUp(eventTime: TimeInterval) async {
        guard shortcutTracker.currentKeyState else { return }
        shortcutTracker.currentKeyState = false

        if let startTime = shortcutTracker.pressEventTime {
            let pressDuration = eventTime - startTime

            if pressDuration < briefPressThreshold {
                shortcutTracker.isHandsFreeMode = true
            } else {
                guard canProcessHotkeyAction else { return }
                await whisperState.handleToggleMiniRecorder()
            }
        }
        shortcutTracker.pressEventTime = nil
    }

    var isShortcutConfigured: Bool {
        (selectedHotkey1 == .custom) ? (KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder) != nil) : true
    }

    func updateShortcutStatus() {
        if selectedHotkey1 == .custom {
            setupHotkeyMonitoring()
        }
    }

    deinit {
        Task { @MainActor in
            removeAllMonitoring()
        }
    }
}
