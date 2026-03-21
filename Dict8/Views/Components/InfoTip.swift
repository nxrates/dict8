import SwiftUI

struct InfoTip: View {
    var message: String
    var learnMoreLink: URL?
    @State private var isShowingTip = false

    init(_ message: String) { self.message = message; self.learnMoreLink = nil }
    init(_ message: String, learnMoreURL: String) { self.message = message; self.learnMoreLink = URL(string: learnMoreURL) }

    var body: some View {
        Image(systemName: "info.circle.fill")
            .foregroundColor(.secondary)
            .contentShape(Rectangle())
            .onTapGesture { isShowingTip.toggle() }
            .popover(isPresented: $isShowingTip) {
                VStack(alignment: .leading, spacing: 0) {
                    if let url = learnMoreLink {
                        (Text(message + " ").font(.caption).foregroundColor(.secondary)
                        + Text("Learn more").font(.caption).foregroundColor(.accentColor))
                            .onTapGesture { NSWorkspace.shared.open(url) }
                    } else {
                        Text(message).font(.caption).foregroundColor(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding()
            }
    }
}
