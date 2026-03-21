import Foundation
import AppKit

struct ApplicationState: Codable {
    var isEnhancementEnabled: Bool
    var useScreenCaptureContext: Bool
    var selectedPromptId: String?
    var selectedAIProvider: String?
    var selectedAIModel: String?
    var selectedLanguage: String?
    var transcriptionModelName: String?
}

struct PowerModeSession: Codable {
    let id: UUID
    let startTime: Date
    var originalState: ApplicationState
}

@MainActor
class PowerModeSessionManager {
    static let shared = PowerModeSessionManager()
    private let sessionKey = "powerModeActiveSession.v1"
    private var isApplying = false
    private var whisperState: WhisperState?
    private var enhancementService: AIEnhancementService?

    private init() { recoverSession() }

    func configure(whisperState: WhisperState, enhancementService: AIEnhancementService) {
        self.whisperState = whisperState
        self.enhancementService = enhancementService
    }

    var hasActiveSession: Bool { loadSession() != nil }

    func beginSession(with config: PowerModeConfig) async {
        guard let ws = whisperState, let es = enhancementService else { return }
        if loadSession() == nil {
            saveSession(PowerModeSession(id: UUID(), startTime: Date(), originalState: captureState(ws: ws, es: es)))
            NotificationCenter.default.addObserver(self, selector: #selector(updateSessionSnapshot), name: .AppSettingsDidChange, object: nil)
        }
        isApplying = true
        await applyState(from: config)
        isApplying = false
    }

    func endSession() async {
        guard let session = loadSession() else { return }
        isApplying = true
        await restoreState(session.originalState)
        isApplying = false
        NotificationCenter.default.removeObserver(self, name: .AppSettingsDidChange, object: nil)
        clearSession()
    }

    @objc func updateSessionSnapshot() {
        guard !isApplying, var session = loadSession(),
              let ws = whisperState, let es = enhancementService else { return }
        session.originalState = captureState(ws: ws, es: es)
        saveSession(session)
    }

    // MARK: - State capture/restore

    private func captureState(ws: WhisperState, es: AIEnhancementService) -> ApplicationState {
        ApplicationState(
            isEnhancementEnabled: es.isEnhancementEnabled,
            useScreenCaptureContext: es.useScreenCaptureContext,
            selectedPromptId: es.selectedPromptId?.uuidString,
            selectedAIProvider: es.getAIService()?.selectedProvider.rawValue,
            selectedAIModel: es.getAIService()?.currentModel,
            selectedLanguage: UserDefaults.standard.string(forKey: "SelectedLanguage"),
            transcriptionModelName: ws.currentTranscriptionModel?.name
        )
    }

    private func applyState(from config: PowerModeConfig) async {
        guard let es = enhancementService else { return }
        await MainActor.run {
            es.isEnhancementEnabled = config.isAIEnhancementEnabled
            es.useScreenCaptureContext = config.useScreenCapture
            if config.isAIEnhancementEnabled {
                if let pid = config.selectedPrompt, let uuid = UUID(uuidString: pid) { es.selectedPromptId = uuid }
                if let ai = es.getAIService() {
                    if let pn = config.selectedAIProvider, let p = AIProvider(rawValue: pn) { ai.selectedProvider = p }
                    if let m = config.selectedAIModel { ai.selectModel(m) }
                }
            }
            if let lang = config.selectedLanguage {
                UserDefaults.standard.set(lang, forKey: "SelectedLanguage")
                NotificationCenter.default.post(name: .languageDidChange, object: nil)
            }
        }
        await switchModelIfNeeded(config.selectedTranscriptionModelName)
    }

    private func restoreState(_ state: ApplicationState) async {
        guard let es = enhancementService else { return }
        await MainActor.run {
            es.isEnhancementEnabled = state.isEnhancementEnabled
            es.useScreenCaptureContext = state.useScreenCaptureContext
            es.selectedPromptId = state.selectedPromptId.flatMap(UUID.init)
            if let ai = es.getAIService() {
                if let pn = state.selectedAIProvider, let p = AIProvider(rawValue: pn) { ai.selectedProvider = p }
                if let m = state.selectedAIModel { ai.selectModel(m) }
            }
            if let lang = state.selectedLanguage {
                UserDefaults.standard.set(lang, forKey: "SelectedLanguage")
                NotificationCenter.default.post(name: .languageDidChange, object: nil)
            }
        }
        await switchModelIfNeeded(state.transcriptionModelName)
    }

    private func switchModelIfNeeded(_ modelName: String?) async {
        guard let ws = whisperState, let name = modelName,
              let model = await ws.allAvailableModels.first(where: { $0.name == name }),
              ws.currentTranscriptionModel?.name != name else { return }
        await ws.setDefaultTranscriptionModel(model)
        switch model.provider {
        #if canImport(whisper)
        case .local:
            await ws.cleanupModelResources()
            if let local = await ws.availableModels.first(where: { $0.name == name }) {
                try? await ws.loadModel(local)
            }
        #endif
        default: await ws.cleanupModelResources()
        }
    }

    // MARK: - Persistence

    private func recoverSession() {
        guard loadSession() != nil else { return }
        Task { await endSession() }
    }

    private func saveSession(_ session: PowerModeSession) {
        if let data = try? JSONEncoder().encode(session) { UserDefaults.standard.set(data, forKey: sessionKey) }
    }

    private func loadSession() -> PowerModeSession? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(PowerModeSession.self, from: data)
    }

    private func clearSession() { UserDefaults.standard.removeObject(forKey: sessionKey) }
}
