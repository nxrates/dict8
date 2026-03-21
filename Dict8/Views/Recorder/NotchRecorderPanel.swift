import SwiftUI
import AppKit

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class NotchRecorderPanel: KeyablePanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        let metrics = NotchRecorderPanel.calculateWindowMetrics()
        super.init(contentRect: metrics.frame, styleMask: [.nonactivatingPanel, .fullSizeContentView, .hudWindow], backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .statusBar + 3
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
        styleMask.remove(.titled)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
        ignoresMouseEvents = false
        isMovable = false

        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenParametersChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    static func calculateWindowMetrics() -> (frame: NSRect, notchWidth: CGFloat, notchHeight: CGFloat) {
        guard let screen = NSScreen.main else {
            return (NSRect(x: 0, y: 0, width: 280, height: 24), 280, 24)
        }
        let safeAreaInsets = screen.safeAreaInsets
        let notchHeight: CGFloat = safeAreaInsets.top > 0 ? safeAreaInsets.top : NSStatusBar.system.thickness
        let baseNotchWidth: CGFloat = safeAreaInsets.left > 0 ? safeAreaInsets.left * 2 : 200
        let totalWidth = baseNotchWidth + 160 // controls + padding
        let maxContentHeight: CGFloat = 200
        let frame = NSRect(
            x: screen.frame.midX - totalWidth / 2,
            y: screen.frame.maxY - maxContentHeight,
            width: totalWidth,
            height: maxContentHeight
        )
        return (frame, baseNotchWidth, notchHeight)
    }

    func show() {
        let metrics = NotchRecorderPanel.calculateWindowMetrics()
        setFrame(metrics.frame, display: true)
        orderFrontRegardless()
    }

    func hide(completion: @escaping () -> Void) { completion() }

    @objc private func handleScreenParametersChange() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            let metrics = NotchRecorderPanel.calculateWindowMetrics()
            self?.setFrame(metrics.frame, display: true)
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

class NotchRecorderHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .dark
        visualEffect.state = .active
        visualEffect.blendingMode = .withinWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.95).cgColor

        let maskLayer = CAShapeLayer()
        let path = CGMutablePath()
        let b = view.bounds
        let r: CGFloat = 12
        path.move(to: CGPoint(x: b.minX, y: b.minY))
        path.addLine(to: CGPoint(x: b.maxX, y: b.minY))
        path.addLine(to: CGPoint(x: b.maxX, y: b.maxY - r))
        path.addQuadCurve(to: CGPoint(x: b.maxX - r, y: b.maxY), control: CGPoint(x: b.maxX, y: b.maxY))
        path.addLine(to: CGPoint(x: b.minX + r, y: b.maxY))
        path.addQuadCurve(to: CGPoint(x: b.minX, y: b.maxY - r), control: CGPoint(x: b.minX, y: b.maxY))
        path.closeSubpath()
        maskLayer.path = path
        visualEffect.layer?.mask = maskLayer

        view.addSubview(visualEffect, positioned: .below, relativeTo: nil)
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            visualEffect.topAnchor.constraint(equalTo: view.topAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
