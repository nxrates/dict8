import SwiftUI
import AppKit

class MiniWindowManager: ObservableObject, RecorderWindowManaging {
    @Published var isVisible = false
    var windowController: NSWindowController?
    var currentPanel: MiniRecorderPanel?
    let whisperState: WhisperState
    let recorder: Recorder
    let hideNotificationName = "HideMiniRecorder"

    init(whisperState: WhisperState, recorder: Recorder) {
        self.whisperState = whisperState
        self.recorder = recorder
        NotificationCenter.default.addObserver(self, selector: #selector(handleHideNotification), name: NSNotification.Name("HideMiniRecorder"), object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func handleHideNotification() { hide() }

    func makePanel(for screen: NSScreen) -> (panel: MiniRecorderPanel, contentView: NSView) {
        let panel = MiniRecorderPanel(contentRect: MiniRecorderPanel.calculateWindowMetrics())
        let view = MiniRecorderView(whisperState: whisperState, recorder: recorder)
            .environmentObject(self).environmentObject(whisperState.enhancementService!)
        return (panel, NSHostingController(rootView: view).view)
    }
}
