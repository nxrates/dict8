import Foundation
import LLMkit

final class ElevenLabsStreamingProvider: LLMKitStreamingProviderBase {
    private let client = LLMkit.ElevenLabsStreamingClient()

    override func clientTranscriptionEvents() -> AsyncStream<LLMkit.StreamingTranscriptionEvent>? { client.transcriptionEvents }
    override func clientSendAudioChunk(_ data: Data) async throws { try await client.sendAudioChunk(data) }
    override func clientCommit() async throws { try await client.commit() }
    override func clientDisconnect() async { await client.disconnect() }

    override func connect(model: any TranscriptionModel, language: String?) async throws {
        let apiKey = try requireAPIKey(provider: "ElevenLabs")
        beginConnect()
        do {
            try await client.connect(apiKey: apiKey, model: "scribe_v2_realtime", language: language)
        } catch {
            handleConnectFailure()
            throw mapError(error)
        }
    }
}
