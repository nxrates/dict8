import SwiftUI
import AppKit

/// Shared state and lifecycle logic for recorder window managers.
/// Both MiniWindowManager and NotchWindowManager use identical show/hide/toggle
/// patterns; this protocol with default implementations eliminates the duplication.
protocol RecorderWindowManaging: ObservableObject where Self: AnyObject {
    associatedtype Panel: NSPanel

    var isVisible: Bool { get set }
    var windowController: NSWindowController? { get set }
    var whisperState: WhisperState { get }
    var recorder: Recorder { get }

    /// Creates the panel and returns it along with the content view to install.
    func makePanel(for screen: NSScreen) -> (panel: Panel, contentView: NSView)
    /// Returns the current panel, if any.
    var currentPanel: Panel? { get set }
    /// The notification name that triggers hiding.
    var hideNotificationName: String { get }
}

extension RecorderWindowManaging {
    func show() {
        guard !isVisible else { return }
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        initializeWindow(screen: screen)
        isVisible = true
        if let panel = currentPanel {
            // Both panel types expose show() via their own custom method
            (panel as? MiniRecorderPanel)?.show()
            (panel as? NotchRecorderPanel)?.show()
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        let cleanup: () -> Void = { [weak self] in self?.deinitializeWindow() }
        if let panel = currentPanel as? MiniRecorderPanel {
            panel.hide(completion: cleanup)
        } else if let panel = currentPanel as? NotchRecorderPanel {
            panel.hide(completion: cleanup)
        } else {
            cleanup()
        }
    }

    func toggle() { isVisible ? hide() : show() }

    func initializeWindow(screen: NSScreen) {
        deinitializeWindow()
        let (panel, contentView) = makePanel(for: screen)
        panel.contentView = contentView
        currentPanel = panel
        windowController = NSWindowController(window: panel)
        panel.orderFrontRegardless()
    }

    func deinitializeWindow() {
        currentPanel?.orderOut(nil)
        windowController?.close()
        windowController = nil
        currentPanel = nil
    }
}
