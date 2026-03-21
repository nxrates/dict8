import SwiftUI

struct TranscriptionDetailView: View {
    let transcription: Transcription

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Text(transcription.timestamp.formatted(date: .abbreviated, time: .shortened))
                        Text("·")
                        Text(transcription.duration.formatTiming())
                        if let model = transcription.transcriptionModelName { Text("·"); Text(model) }
                        if let tDur = transcription.transcriptionDuration { Text("·"); Text("STT: \(tDur.formatTiming())") }
                        if let eDur = transcription.enhancementDuration { Text("·"); Text("LLM: \(eDur.formatTiming())") }
                        Spacer()
                        AnimatedCopyButton(textToCopy: transcription.enhancedText ?? transcription.text)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(transcription.enhancedText ?? transcription.text)
                        .font(.body)
                        .textSelection(.enabled)

                    if let enhanced = transcription.enhancedText, !enhanced.isEmpty {
                        Divider()
                        Text("Original").font(.caption).foregroundStyle(.secondary)
                        Text(transcription.text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }

            if let urlString = transcription.audioFileURL, let url = URL(string: urlString),
               FileManager.default.fileExists(atPath: url.path) {
                Divider()
                AudioPlayerView(url: url).padding()
            }
        }
    }
}
