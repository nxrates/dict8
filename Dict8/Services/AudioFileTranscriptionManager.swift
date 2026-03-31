import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import os

@MainActor
class AudioTranscriptionManager: ObservableObject {
    static let shared = AudioTranscriptionManager()

    @Published var isProcessing = false
    @Published var processingPhase: ProcessingPhase = .idle
    @Published var currentTranscription: Transcription?
    @Published var errorMessage: String?

    private var currentTask: Task<Void, Error>?
    private let audioProcessor = AudioProcessor()
    private let logger = Logger(subsystem: "com.prakashjoshipax.dict8", category: "AudioTranscriptionManager")

    enum ProcessingPhase: String {
        case idle, loading, processingAudio, transcribing, enhancing, completed
        var message: String {
            switch self {
            case .idle: return ""
            case .loading: return "Loading transcription model..."
            case .processingAudio: return "Processing audio file for transcription..."
            case .transcribing: return "Transcribing audio..."
            case .enhancing: return "Enhancing transcription with AI..."
            case .completed: return "Transcription completed!"
            }
        }
    }

    private init() {}

    func startProcessing(url: URL, modelContext: ModelContext, whisperState: WhisperState) {
        cancelProcessing()
        isProcessing = true
        processingPhase = .loading
        errorMessage = nil

        currentTask = Task {
            do {
                guard let currentModel = whisperState.currentTranscriptionModel else { throw TranscriptionError.noModelSelected }
                let serviceRegistry = TranscriptionServiceRegistry(whisperState: whisperState, modelsDirectory: whisperState.modelsDirectory)

                processingPhase = .processingAudio
                let samples = try await audioProcessor.processAudioToSamples(url)
                let duration = CMTimeGetSeconds(try await AVURLAsset(url: url).load(.duration))

                let recordingsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("com.prakashjoshipax.Dict8/Recordings")
                let permanentURL = recordingsDirectory.appendingPathComponent("transcribed_\(UUID().uuidString).wav")
                try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
                try audioProcessor.saveSamplesAsWav(samples: samples, to: permanentURL)

                processingPhase = .transcribing
                let transcriptionStart = Date()
                var text = try await serviceRegistry.transcribe(audioURL: permanentURL, model: currentModel)
                let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
                text = TranscriptionHelper.postProcess(text, modelContext: modelContext)

                let pmInfo = TranscriptionHelper.powerModeInfo()

                if let es = whisperState.enhancementService, es.isEnhancementEnabled, es.isConfigured {
                    processingPhase = .enhancing
                    do {
                        let (enhanced, enhDur, promptName) = try await es.enhance(text)
                        currentTranscription = TranscriptionHelper.save(text: text, duration: duration, audioURL: permanentURL, model: currentModel, transcriptionDuration: transcriptionDuration, enhancedText: enhanced, enhancementDuration: enhDur, promptName: promptName, enhancementService: es, powerMode: pmInfo, context: modelContext)
                    } catch {
                        logger.error("Enhancement failed: \(error.localizedDescription, privacy: .public)")
                        currentTranscription = TranscriptionHelper.save(text: text, duration: duration, audioURL: permanentURL, model: currentModel, transcriptionDuration: transcriptionDuration, powerMode: pmInfo, context: modelContext)
                    }
                } else {
                    currentTranscription = TranscriptionHelper.save(text: text, duration: duration, audioURL: permanentURL, model: currentModel, transcriptionDuration: transcriptionDuration, powerMode: pmInfo, context: modelContext)
                }

                processingPhase = .completed
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await serviceRegistry.cleanup()
                finishProcessing()
            } catch {
                handleError(error)
            }
        }
    }

    func cancelProcessing() { currentTask?.cancel() }
    private func finishProcessing() { isProcessing = false; processingPhase = .idle; currentTask = nil }
    private func handleError(_ error: Error) {
        logger.error("Transcription error: \(error.localizedDescription, privacy: .public)")
        errorMessage = error.localizedDescription; isProcessing = false; processingPhase = .idle; currentTask = nil
    }
}

enum TranscriptionError: Error, LocalizedError {
    case noModelSelected, transcriptionCancelled
    var errorDescription: String? {
        switch self {
        case .noModelSelected: return "No transcription model selected"
        case .transcriptionCancelled: return "Transcription was cancelled"
        }
    }
}

// MARK: - Shared helpers to eliminate Transcription creation duplication

@MainActor enum TranscriptionHelper {
    static func postProcess(_ text: String, modelContext: ModelContext) -> String {
        var t = TranscriptionOutputFilter.filter(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if UserDefaults.standard.bool(forKey: "IsTextFormattingEnabled") { t = WhisperTextFormatter.format(t) }
        t = WordReplacementService.shared.applyReplacements(to: t, using: modelContext)
        return t
    }

    static func powerModeInfo() -> (name: String?, emoji: String?) {
        let config = PowerModeManager.shared.currentActiveConfiguration
        let active = config?.isEnabled == true
        return (active ? config?.name : nil, active ? config?.emoji : nil)
    }

    @discardableResult
    static func save(
        text: String, duration: Double, audioURL: URL, model: any TranscriptionModel,
        transcriptionDuration: Double, enhancedText: String? = nil, enhancementDuration: Double? = nil,
        promptName: String? = nil, enhancementService: AIEnhancementService? = nil,
        powerMode: (name: String?, emoji: String?), context: ModelContext
    ) -> Transcription {
        let t = Transcription(
            text: text, duration: duration, enhancedText: enhancedText,
            audioFileURL: audioURL.absoluteString, transcriptionModelName: model.displayName,
            aiEnhancementModelName: enhancedText != nil ? enhancementService?.getAIService()?.currentModel : nil,
            promptName: promptName, transcriptionDuration: transcriptionDuration,
            enhancementDuration: enhancementDuration,
            aiRequestSystemMessage: enhancedText != nil ? enhancementService?.lastSystemMessageSent : nil,
            aiRequestUserMessage: enhancedText != nil ? enhancementService?.lastUserMessageSent : nil,
            powerModeName: powerMode.name, powerModeEmoji: powerMode.emoji
        )
        context.insert(t)
        try? context.save()
        NotificationCenter.default.post(name: .transcriptionCreated, object: t)
        NotificationCenter.default.post(name: .transcriptionCompleted, object: t)
        return t
    }
}
