import SwiftUI
import AppKit

// MARK: - Glass Background

private struct GlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            content
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

// MARK: - Mini Recorder Panel

class MiniRecorderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true; level = .floating; hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = true; isMovableByWindowBackground = true
        backgroundColor = .clear; isOpaque = false; hasShadow = false
        titlebarAppearsTransparent = true; titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
    }

    static func calculateWindowMetrics() -> NSRect {
        guard let screen = NSScreen.main else { return NSRect(x: 0, y: 0, width: 360, height: 110) }
        let width: CGFloat = 360, height: CGFloat = 110
        let visibleFrame = screen.visibleFrame
        return NSRect(x: visibleFrame.midX - width / 2, y: visibleFrame.midY - height / 2, width: width, height: height)
    }

    func show() { setFrame(Self.calculateWindowMetrics(), display: true); orderFrontRegardless() }
    func hide(completion: @escaping () -> Void) { completion() }
}

// MARK: - Mini Recorder View

struct MiniRecorderView: View {
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: MiniWindowManager
    @EnvironmentObject private var enhancementService: AIEnhancementService

    var body: some View {
        if windowManager.isVisible {
            RecorderStatusDisplay(currentState: whisperState.recordingState, audioMeter: recorder.audioMeter)
                .padding(.horizontal, 0)
                .frame(width: 360, height: 90)
                .modifier(GlassModifier())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
