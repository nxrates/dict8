import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import os

@MainActor
class AudioTranscriptionService: ObservableObject {
    @Published var isTranscribing = false
    @Published var currentError: TranscriptionError?

    private let modelContext: ModelContext
    private let enhancementService: AIEnhancementService?
    private let whisperState: WhisperState
    private let promptDetectionService = PromptDetectionService()
    private let logger = Logger(subsystem: "com.prakashjoshipax.dict8", category: "AudioTranscriptionService")
    private let serviceRegistry: TranscriptionServiceRegistry

    enum TranscriptionError: Error {
        case noAudioFile, transcriptionFailed, modelNotLoaded, invalidAudioFormat
    }

    init(modelContext: ModelContext, whisperState: WhisperState) {
        self.modelContext = modelContext
        self.whisperState = whisperState
        self.enhancementService = whisperState.enhancementService
        self.serviceRegistry = TranscriptionServiceRegistry(whisperState: whisperState, modelsDirectory: whisperState.modelsDirectory)
    }

    func retranscribeAudio(from url: URL, using model: any TranscriptionModel) async throws -> Transcription {
        guard FileManager.default.fileExists(atPath: url.path) else { throw TranscriptionError.noAudioFile }
        isTranscribing = true

        do {
            let transcriptionStart = Date()
            var text = try await serviceRegistry.transcribe(audioURL: url, model: model)
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
            text = TranscriptionHelper.postProcess(text, modelContext: modelContext)
            let originalText = text

            let duration = CMTimeGetSeconds(try await AVURLAsset(url: url).load(.duration))
            let recordingsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.prakashjoshipax.Dict8/Recordings")
            let permanentURL = recordingsDir.appendingPathComponent("retranscribed_\(UUID().uuidString).wav")
            try FileManager.default.copyItem(at: url, to: permanentURL)

            let pmInfo = TranscriptionHelper.powerModeInfo()

            // Prompt detection
            var promptResult: PromptDetectionService.PromptDetectionResult?
            if let es = enhancementService, es.isConfigured {
                promptResult = await promptDetectionService.analyzeText(text, with: es)
                await promptDetectionService.applyDetectionResult(promptResult!, to: es)
            }

            // Enhancement
            if let es = enhancementService, es.isEnhancementEnabled, es.isConfigured {
                do {
                    let textForAI = promptResult?.processedText ?? text
                    let (enhanced, enhDur, promptName) = try await es.enhance(textForAI)
                    let t = TranscriptionHelper.save(text: originalText, duration: duration, audioURL: permanentURL, model: model, transcriptionDuration: transcriptionDuration, enhancedText: enhanced, enhancementDuration: enhDur, promptName: promptName, enhancementService: es, powerMode: pmInfo, context: modelContext)
                    if let pr = promptResult, pr.shouldEnableAI { await promptDetectionService.restoreOriginalSettings(pr, to: es) }
                    isTranscribing = false
                    return t
                } catch {
                    let t = TranscriptionHelper.save(text: originalText, duration: duration, audioURL: permanentURL, model: model, transcriptionDuration: transcriptionDuration, powerMode: pmInfo, context: modelContext)
                    isTranscribing = false
                    return t
                }
            } else {
                let t = TranscriptionHelper.save(text: originalText, duration: duration, audioURL: permanentURL, model: model, transcriptionDuration: transcriptionDuration, powerMode: pmInfo, context: modelContext)
                isTranscribing = false
                return t
            }
        } catch {
            logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            currentError = .transcriptionFailed
            isTranscribing = false
            throw error
        }
    }
}
