import Foundation
import SwiftData
import os
import AppKit

@MainActor
final class ModelPrewarmService: ObservableObject {
    private let whisperState: WhisperState
    private let logger = Logger(subsystem: "com.prakashjoshipax.dict8", category: "ModelPrewarm")
    private let prewarmAudioURL = Bundle.main.url(forResource: "esc", withExtension: "wav")
    private let prewarmEnabledKey = "PrewarmModelOnWake"

    init(whisperState: WhisperState, modelContext: ModelContext) {
        self.whisperState = whisperState

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(schedulePrewarm),
            name: NSWorkspace.didWakeNotification, object: nil
        )

        Task {
            try? await Task.sleep(for: .seconds(3))
            await performPrewarm()
        }
    }

    @objc private func schedulePrewarm() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            await performPrewarm()
        }
    }

    private func performPrewarm() async {
        guard UserDefaults.standard.bool(forKey: prewarmEnabledKey) else { return }
        guard let model = whisperState.currentTranscriptionModel else { return }

        let startTime = Date()
        do {
            switch model.provider {
            case .nativeApple:
                guard #available(macOS 26, *) else { return }
                let language = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
                try await NativeAppleSpeechEngine.shared.prewarm(languageCode: language)
            case .parakeet:
                try await whisperState.serviceRegistry.parakeetTranscriptionService.loadModel(for: model)
                _ = try await ParakeetStreamingEngine.shared.load()
            case .local:
                guard let audioURL = prewarmAudioURL else {
                    logger.error("Prewarm audio file (esc.wav) not found")
                    return
                }
                _ = try await whisperState.serviceRegistry.transcribe(audioURL: audioURL, model: model)
            default:
                return
            }
            let duration = Date().timeIntervalSince(startTime)
            logger.notice("Prewarm completed in \(String(format: "%.2f", duration), privacy: .public)s")
        } catch {
            logger.error("Prewarm failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
