import Foundation
import SwiftData
import os
import AppKit

@MainActor
final class ModelPrewarmService: ObservableObject {
    private let whisperState: WhisperState
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.prakashjoshipax.dict8", category: "ModelPrewarm")
    private lazy var serviceRegistry = TranscriptionServiceRegistry(
        whisperState: whisperState,
        modelsDirectory: whisperState.modelsDirectory
    )
    private let prewarmAudioURL = Bundle.main.url(forResource: "esc", withExtension: "wav")
    private let prewarmEnabledKey = "PrewarmModelOnWake"

    init(whisperState: WhisperState, modelContext: ModelContext) {
        self.whisperState = whisperState
        self.modelContext = modelContext

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

        switch model.provider {
        case .local, .parakeet: break
        default: return
        }

        guard let audioURL = prewarmAudioURL else {
            logger.error("Prewarm audio file (esc.wav) not found")
            return
        }

        let startTime = Date()
        do {
            let _ = try await serviceRegistry.transcribe(audioURL: audioURL, model: model)
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
