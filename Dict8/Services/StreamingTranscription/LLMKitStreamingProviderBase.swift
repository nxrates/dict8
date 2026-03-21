import Foundation
import LLMkit
import SwiftData

/// Base class for LLMkit-backed streaming providers.
/// Subclasses only need to implement `makeClient()` and `connectClient(...)`.
class LLMKitStreamingProviderBase: StreamingTranscriptionProvider {
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private var forwardingTask: Task<Void, Never>?
    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    init() {
        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        forwardingTask?.cancel()
        eventsContinuation?.finish()
    }

    // MARK: - Override points

    /// The underlying LLMkit client's transcriptionEvents stream to forward from.
    func clientTranscriptionEvents() -> AsyncStream<LLMkit.StreamingTranscriptionEvent>? { nil }

    /// Send audio to the underlying client.
    func clientSendAudioChunk(_ data: Data) async throws { }

    /// Commit on the underlying client.
    func clientCommit() async throws { }

    /// Disconnect the underlying client.
    func clientDisconnect() async { }

    // MARK: - StreamingTranscriptionProvider

    func connect(model: any TranscriptionModel, language: String?) async throws {
        fatalError("Subclasses must override connect()")
    }

    func sendAudioChunk(_ data: Data) async throws {
        do { try await clientSendAudioChunk(data) }
        catch { throw mapError(error) }
    }

    func commit() async throws {
        do { try await clientCommit() }
        catch { throw mapError(error) }
    }

    func disconnect() async {
        forwardingTask?.cancel()
        forwardingTask = nil
        await clientDisconnect()
        eventsContinuation?.finish()
    }

    // MARK: - Shared Helpers

    func startEventForwarding() {
        guard let events = clientTranscriptionEvents() else { return }
        forwardingTask = Task { [weak self] in
            for await event in events {
                switch event {
                case .sessionStarted:
                    self?.eventsContinuation?.yield(.sessionStarted)
                case .partial(let text):
                    self?.eventsContinuation?.yield(.partial(text: text))
                case .committed(let text):
                    self?.eventsContinuation?.yield(.committed(text: text))
                case .error(let message):
                    self?.eventsContinuation?.yield(.error(StreamingTranscriptionError.serverError(message)))
                }
            }
        }
    }

    func beginConnect() {
        forwardingTask?.cancel()
        startEventForwarding()
    }

    func handleConnectFailure() {
        forwardingTask?.cancel()
        forwardingTask = nil
    }

    func mapError(_ error: Error) -> Error {
        guard let llmError = error as? LLMKitError else { return error }
        switch llmError {
        case .missingAPIKey:
            return StreamingTranscriptionError.missingAPIKey
        case .httpError(_, let message):
            return StreamingTranscriptionError.serverError(message)
        case .networkError(let detail):
            return StreamingTranscriptionError.connectionFailed(detail)
        default:
            return StreamingTranscriptionError.serverError(llmError.localizedDescription ?? "Unknown error")
        }
    }

    func requireAPIKey(provider: String) throws -> String {
        guard let key = APIKeyManager.shared.getAPIKey(forProvider: provider), !key.isEmpty else {
            throw StreamingTranscriptionError.missingAPIKey
        }
        return key
    }
}

/// Shared vocabulary fetching for streaming providers that support it.
enum StreamingVocabularyHelper {
    static func fetchTerms(modelContext: ModelContext, limit: Int? = nil) -> [String] {
        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\.word)])
        guard let words = try? modelContext.fetch(descriptor) else { return [] }
        var seen = Set<String>()
        var unique: [String] = []
        for word in words {
            let trimmed = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if !seen.contains(key) { seen.insert(key); unique.append(trimmed) }
        }
        return limit.map { Array(unique.prefix($0)) } ?? unique
    }
}
