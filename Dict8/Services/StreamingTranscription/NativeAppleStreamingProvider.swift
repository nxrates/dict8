import Foundation
import os

/// Streams microphone PCM into Apple SpeechAnalyzer and emits live drafts.
final class NativeAppleStreamingProvider: StreamingTranscriptionProvider {
    private let logger = Logger(subsystem: "com.prakashjoshipax.dict8", category: "NativeAppleStreaming")
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>
    private var started = false

    init() {
        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        eventsContinuation?.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        guard #available(macOS 26, *) else {
            throw StreamingTranscriptionError.connectionFailed("Apple Speech requires macOS 26 or later.")
        }

        let languageCode = language ?? "auto"
        try await NativeAppleSpeechEngine.shared.start(languageCode: languageCode) { [weak self] update in
            self?.eventsContinuation?.yield(.partial(text: update.displayText))
        }
        started = true
        eventsContinuation?.yield(.sessionStarted)
        logger.notice("Apple Speech streaming started")
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard #available(macOS 26, *) else {
            throw StreamingTranscriptionError.connectionFailed("Apple Speech requires macOS 26 or later.")
        }
        try await NativeAppleSpeechEngine.shared.sendAudioChunk(data)
    }

    func commit() async throws {
        guard #available(macOS 26, *) else {
            throw StreamingTranscriptionError.connectionFailed("Apple Speech requires macOS 26 or later.")
        }
        let text = try await NativeAppleSpeechEngine.shared.finish()
        started = false
        eventsContinuation?.yield(.committed(text: text))
    }

    func disconnect() async {
        guard started else {
            eventsContinuation?.finish()
            return
        }
        started = false
        if #available(macOS 26, *) {
            await NativeAppleSpeechEngine.shared.cancel()
        }
        eventsContinuation?.finish()
        logger.notice("Apple Speech streaming disconnected")
    }
}
