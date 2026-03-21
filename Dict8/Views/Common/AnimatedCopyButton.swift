import SwiftUI

struct AnimatedCopyButton: View {
    let textToCopy: String
    @State private var isCopied = false

    var body: some View {
        Button {
            let _ = ClipboardManager.copyToClipboard(textToCopy)
            withAnimation { isCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { isCopied = false } }
        } label: {
            Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .opacity(isCopied ? 0.7 : 1)
        .animation(.easeInOut(duration: 0.2), value: isCopied)
    }
}
