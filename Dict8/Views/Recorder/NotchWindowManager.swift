import SwiftUI
import AppKit

@MainActor
class NotchWindowManager: ObservableObject, RecorderWindowManaging {
    @Published var isVisible = false
    var windowController: NSWindowController?
    var currentPanel: NotchRecorderPanel?
    let whisperState: WhisperState
    let recorder: Recorder
    let hideNotificationName = "HideNotchRecorder"

    /// Public access preserved for existing callers that reference `notchPanel`.
    var notchPanel: NotchRecorderPanel? {
        get { currentPanel }
        set { currentPanel = newValue }
    }

    init(whisperState: WhisperState, recorder: Recorder) {
        self.whisperState = whisperState
        self.recorder = recorder
        NotificationCenter.default.addObserver(self, selector: #selector(handleHideNotification), name: NSNotification.Name("HideNotchRecorder"), object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func handleHideNotification() { hide() }

    func makePanel(for screen: NSScreen) -> (panel: NotchRecorderPanel, contentView: NSView) {
        let metrics = NotchRecorderPanel.calculateWindowMetrics()
        let panel = NotchRecorderPanel(contentRect: metrics.frame)
        let view = NotchRecorderView(whisperState: whisperState, recorder: recorder)
            .environmentObject(self).environmentObject(whisperState.enhancementService!)
        let hostingController = NotchRecorderHostingController(rootView: view)
        return (panel, hostingController.view)
    }
}
