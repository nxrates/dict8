import SwiftUI

// MARK: - Glass Action Button

/// Applies `.glassProminent` on macOS 26+, falls back to `.borderedProminent` on earlier versions.
struct GlassActionButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

extension View {
    func glassActionButton() -> some View {
        modifier(GlassActionButtonModifier())
    }
}
