import SwiftUI
import AVFoundation
import Cocoa
import KeyboardShortcuts

class PermissionManager: ObservableObject {
    @Published var audioPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var isAccessibilityEnabled = false
    @Published var isScreenRecordingEnabled = false
    @Published var isKeyboardShortcutSet = false

    init() {
        setupNotificationObservers()
        checkAllPermissions()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
    }

    @objc private func applicationDidBecomeActive() { checkAllPermissions() }

    func checkAllPermissions() {
        checkAccessibilityPermissions()
        checkScreenRecordingPermission()
        checkAudioPermissionStatus()
        checkKeyboardShortcut()
    }

    func checkAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let enabled = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async { self.isAccessibilityEnabled = enabled }
    }

    func checkScreenRecordingPermission() {
        DispatchQueue.main.async { self.isScreenRecordingEnabled = CGPreflightScreenCaptureAccess() }
    }

    func requestScreenRecordingPermission() { CGRequestScreenCaptureAccess() }

    func checkAudioPermissionStatus() {
        DispatchQueue.main.async { self.audioPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio) }
    }

    func requestAudioPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { self.audioPermissionStatus = granted ? .authorized : .denied }
        }
    }

    func checkKeyboardShortcut() {
        DispatchQueue.main.async { self.isKeyboardShortcutSet = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder) != nil }
    }
}

/// Sections-only view for embedding inside a Form (e.g., SettingsView).
struct PermissionsSectionsView: View {
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @StateObject private var permissionManager = PermissionManager()

    var body: some View {
        Section("Keyboard Shortcut") {
            permissionRow(
                isGranted: hotkeyManager.selectedHotkey1 != .none,
                description: "Set up a keyboard shortcut to use Dict8 anywhere",
                buttonTitle: "Configure Shortcut",
                action: {
                    NotificationCenter.default.post(
                        name: .navigateToDestination, object: nil,
                        userInfo: ["destination": "Settings"]
                    )
                },
                check: { permissionManager.checkKeyboardShortcut() }
            )
        }

        Section("Microphone Access") {
            permissionRow(
                isGranted: permissionManager.audioPermissionStatus == .authorized,
                description: "Allow Dict8 to record your voice for transcription",
                buttonTitle: permissionManager.audioPermissionStatus == .notDetermined ? "Request Permission" : "Open System Settings",
                action: {
                    if permissionManager.audioPermissionStatus == .notDetermined {
                        permissionManager.requestAudioPermission()
                    } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                },
                check: { permissionManager.checkAudioPermissionStatus() }
            )
        }

        Section {
            permissionRow(
                isGranted: permissionManager.isAccessibilityEnabled,
                description: "Allow Dict8 to paste transcribed text directly at your cursor position",
                buttonTitle: "Open System Settings",
                action: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                },
                check: { permissionManager.checkAccessibilityPermissions() }
            )
        } header: {
            HStack(spacing: 4) {
                Text("Accessibility Access")
                InfoTip("Dict8 uses Accessibility permissions to paste the transcribed text directly into other applications at your cursor's position. This allows for a seamless dictation experience across your Mac.")
            }
        }

        Section {
            permissionRow(
                isGranted: permissionManager.isScreenRecordingEnabled,
                description: "Allow Dict8 to understand context from your screen for transcript Enhancement",
                buttonTitle: "Request Permission",
                action: {
                    permissionManager.requestScreenRecordingPermission()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                },
                check: { permissionManager.checkScreenRecordingPermission() }
            )
        } header: {
            HStack(spacing: 4) {
                Text("Screen Recording Access")
                InfoTip("Dict8 captures on-screen text to understand the context of your voice input, which significantly improves transcription accuracy. Your privacy is important: this data is processed locally and is not stored.",
                       learnMoreURL: "https://github.com/pde-rent/dict8
            }
        }
    }

    @ViewBuilder
    private func permissionRow(isGranted: Bool, description: String, buttonTitle: String, action: @escaping () -> Void, check: @escaping () -> Void) -> some View {
        HStack {
            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
            Button { check() } label: {
                Image(systemName: "arrow.clockwise").foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isGranted ? .green : .orange)
        }
        if !isGranted {
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
    }
}
