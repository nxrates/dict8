import SwiftUI

struct NotchRecorderView: View {
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: NotchWindowManager
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @State private var isHovering = false
    @ObservedObject private var powerModeManager = PowerModeManager.shared

    private var menuBarHeight: CGFloat {
        guard let screen = NSScreen.main else { return NSStatusBar.system.thickness }
        return screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top
            : NSApplication.shared.mainMenu?.menuBarHeight ?? NSStatusBar.system.thickness
    }

    private var exactNotchWidth: CGFloat {
        guard let screen = NSScreen.main, screen.safeAreaInsets.left > 0 else { return 200 }
        return screen.safeAreaInsets.left * 2
    }

    var body: some View {
        Group {
            if windowManager.isVisible {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Spacer()
                        Rectangle().fill(Color.clear).frame(width: exactNotchWidth).contentShape(Rectangle())
                        RecorderStatusDisplay(currentState: whisperState.recordingState, audioMeter: recorder.audioMeter, menuBarHeight: menuBarHeight)
                            .padding(.trailing, 16)
                        Spacer()
                    }
                    .frame(height: menuBarHeight)

                    // Bottom: partial transcript
                    TimelineView(.animation(minimumInterval: 0.1)) { _ in
                        let hasText = whisperState.recordingState == .recording && !whisperState.partialTranscript.isEmpty
                        VStack(spacing: 0) {
                            Divider().background(Color.white.opacity(0.15))
                            Text(whisperState.partialTranscript)
                                .font(.caption).foregroundColor(.white.opacity(0.8))
                                .lineLimit(1).truncationMode(.head)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        }
                        .opacity(hasText ? 1 : 0)
                        .frame(height: hasText ? nil : 0).clipped()
                    }
                }
                .clipShape(NotchShape(topCornerRadius: 6, bottomCornerRadius: 12))
                .notchGlass()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onHover { isHovering = $0 }
                .opacity(windowManager.isVisible ? 1 : 0)
            }
        }
    }
}

// MARK: - Notch Glass Modifier

private struct NotchGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: NotchShape(topCornerRadius: 6, bottomCornerRadius: 12))
        } else {
            content
                .background(Color.black)
        }
    }
}

private extension View {
    func notchGlass() -> some View {
        modifier(NotchGlassModifier())
    }
}
