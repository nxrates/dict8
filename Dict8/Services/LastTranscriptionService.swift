import Foundation
import SwiftData

class LastTranscriptionService: ObservableObject {

    static func getLastTranscription(from modelContext: ModelContext) -> Transcription? {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        do {
            let transcriptions = try modelContext.fetch(descriptor)
            return transcriptions.first
        } catch {
            print("Error fetching last transcription: \(error)")
            return nil
        }
    }

    private static func preferredText(from transcription: Transcription) -> String {
        if let enhancedText = transcription.enhancedText, !enhancedText.isEmpty {
            return enhancedText
        }
        return transcription.text
    }

    private static func withLastTranscription(from modelContext: ModelContext, action: (Transcription) -> Void) {
        guard let transcription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(title: "No transcription available", type: .error)
            }
            return
        }
        action(transcription)
    }

    static func copyLastTranscription(from modelContext: ModelContext) {
        withLastTranscription(from: modelContext) { transcription in
            let success = ClipboardManager.copyToClipboard(preferredText(from: transcription))
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: success ? "Last transcription copied" : "Failed to copy transcription",
                    type: success ? .success : .error
                )
            }
        }
    }

    static func pasteLastTranscription(from modelContext: ModelContext) {
        withLastTranscription(from: modelContext) { transcription in
            let text = transcription.text
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                CursorPaster.pasteAtCursor(text)
            }
        }
    }

    static func pasteLastEnhancement(from modelContext: ModelContext) {
        withLastTranscription(from: modelContext) { transcription in
            let text = preferredText(from: transcription)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                CursorPaster.pasteAtCursor(text)
            }
        }
    }

    static func retryLastTranscription(from modelContext: ModelContext, whisperState: WhisperState) {
        Task { @MainActor in
            guard let lastTranscription = getLastTranscription(from: modelContext),
                  let audioURLString = lastTranscription.audioFileURL,
                  let audioURL = URL(string: audioURLString),
                  FileManager.default.fileExists(atPath: audioURL.path) else {
                NotificationManager.shared.showNotification(title: "Cannot retry: Audio file not found", type: .error)
                return
            }

            guard let currentModel = whisperState.currentTranscriptionModel else {
                NotificationManager.shared.showNotification(title: "No transcription model selected", type: .error)
                return
            }

            let transcriptionService = AudioTranscriptionService(modelContext: modelContext, whisperState: whisperState)
            do {
                let newTranscription = try await transcriptionService.retranscribeAudio(from: audioURL, using: currentModel)
                ClipboardManager.copyToClipboard(preferredText(from: newTranscription))
                NotificationManager.shared.showNotification(title: "Copied to clipboard", type: .success)
            } catch {
                NotificationManager.shared.showNotification(title: "Retry failed: \(error.localizedDescription)", type: .error)
            }
        }
    }
}
