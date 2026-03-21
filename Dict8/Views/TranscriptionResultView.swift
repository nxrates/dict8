import SwiftUI

enum TranscriptionTab: String, CaseIterable {
    case original = "Original"
    case enhanced = "Enhanced"
}

struct TranscriptionResultView: View {
    let transcription: Transcription
    @State private var selectedTab: TranscriptionTab = .original

    private var availableTabs: [TranscriptionTab] {
        var tabs: [TranscriptionTab] = [.original]
        if transcription.enhancedText != nil { tabs.append(.enhanced) }
        return tabs
    }

    private var textForSelectedTab: String {
        switch selectedTab {
        case .original: return transcription.text
        case .enhanced: return transcription.enhancedText ?? ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcription Result").font(.headline)
                Spacer()
                if availableTabs.count > 1 {
                    Picker("Tab", selection: $selectedTab) {
                        ForEach(availableTabs, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).fixedSize()
                }
                AnimatedCopyButton(textToCopy: textForSelectedTab)
                AnimatedSaveButton(textToSave: textForSelectedTab)
            }

            ScrollView {
                Text(textForSelectedTab).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Duration: \(transcription.duration.formatMinutesSeconds())").font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }
}
