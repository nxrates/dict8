import Foundation
import SwiftData
import LLMkit

final class SonioxStreamingProvider: LLMKitStreamingProviderBase {
    private let client = LLMkit.SonioxStreamingClient()
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init()
    }

    override func clientTranscriptionEvents() -> AsyncStream<LLMkit.StreamingTranscriptionEvent>? { client.transcriptionEvents }
    override func clientSendAudioChunk(_ data: Data) async throws { try await client.sendAudioChunk(data) }
    override func clientCommit() async throws { try await client.commit() }
    override func clientDisconnect() async { await client.disconnect() }

    override func connect(model: any TranscriptionModel, language: String?) async throws {
        let apiKey = try requireAPIKey(provider: "Soniox")
        let vocabulary = StreamingVocabularyHelper.fetchTerms(modelContext: modelContext)
        beginConnect()
        do {
            try await client.connect(apiKey: apiKey, model: model.name, language: language, customVocabulary: vocabulary)
        } catch {
            handleConnectFailure()
            throw mapError(error)
        }
    }
}
