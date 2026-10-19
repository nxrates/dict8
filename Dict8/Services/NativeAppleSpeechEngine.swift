@preconcurrency import AVFoundation
import Foundation
import os
import Speech

/// Prewarmed, streaming Apple SpeechAnalyzer session.
///
/// Talkify's latency comes from keeping a high-priority lingering analyzer
/// warm and feeding PCM while the user speaks (volatile + fast results).
/// Dict8's previous native path waited for the WAV and ran a cold analyzer.
@available(macOS 26, *)
actor NativeAppleSpeechEngine {
    static let shared = NativeAppleSpeechEngine()

    private let logger = Logger(subsystem: "com.prakashjoshipax.dict8", category: "NativeAppleSpeechEngine")

    enum EngineError: Error, LocalizedError {
        case unavailable
        case unsupportedLocale
        case missingAudioFormat
        case sessionAlreadyActive
        case noActiveSession
        case conversionFailed

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Apple Speech is unavailable on this Mac."
            case .unsupportedLocale:
                return "The selected language is not supported by Apple Speech."
            case .missingAudioFormat:
                return "Apple Speech did not provide a compatible audio format."
            case .sessionAlreadyActive:
                return "A dictation session is already active."
            case .noActiveSession:
                return "No dictation session is active."
            case .conversionFailed:
                return "Failed to convert microphone audio for Apple Speech."
            }
        }
    }

    private struct PreparedSession: @unchecked Sendable {
        let locale: Locale
        let transcriber: SpeechTranscriber
        let analyzer: SpeechAnalyzer
        let audioFormat: AVAudioFormat
    }

    private struct ActiveSession {
        let prepared: PreparedSession
        let continuation: AsyncStream<AnalyzerInput>.Continuation
        let resultTask: Task<String, any Error>
        let converter: AVAudioConverter?
        let sourceFormat: AVAudioFormat
    }

    private var preparedSessions: [String: PreparedSession] = [:]
    private var buildTasks: [String: Task<PreparedSession, any Error>] = [:]
    private var activeSession: ActiveSession?
    private var isStarting = false

    func prewarm(languageCode: String) async throws {
        try await requestSpeechAccess()
        let locale = try await resolveLocale(languageCode)
        try await ensureWarm(locale: locale)
    }

    func start(
        languageCode: String,
        updateHandler: @escaping @Sendable (SpeechResultAccumulator.Update) -> Void
    ) async throws {
        guard activeSession == nil, !isStarting else { throw EngineError.sessionAlreadyActive }
        isStarting = true
        defer { isStarting = false }

        try await requestSpeechAccess()
        let locale = try await resolveLocale(languageCode)
        let prepared = try await takePreparedSession(locale: locale)
        try Task.checkCancellation()

        let (stream, continuation) = AsyncStream.makeStream(
            of: AnalyzerInput.self,
            bufferingPolicy: .bufferingNewest(64)
        )

        let resultTask = Task { () throws -> String in
            var accumulator = SpeechResultAccumulator()
            for try await result in prepared.transcriber.results {
                let text = String(result.text.characters)
                updateHandler(accumulator.receive(text, isFinal: result.isFinal))
            }
            return accumulator.completedText
        }

        let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!

        let converter: AVAudioConverter?
        if sourceFormat == prepared.audioFormat {
            converter = nil
        } else {
            converter = AVAudioConverter(from: sourceFormat, to: prepared.audioFormat)
            if converter == nil {
                resultTask.cancel()
                continuation.finish()
                throw EngineError.conversionFailed
            }
        }

        activeSession = ActiveSession(
            prepared: prepared,
            continuation: continuation,
            resultTask: resultTask,
            converter: converter,
            sourceFormat: sourceFormat
        )

        do {
            try await prepared.analyzer.start(inputSequence: stream)
            try Task.checkCancellation()
        } catch {
            activeSession = nil
            continuation.finish()
            await prepared.analyzer.cancelAndFinishNow()
            resultTask.cancel()
            throw error
        }
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard let session = activeSession else { throw EngineError.noActiveSession }
        guard let sourceBuffer = Self.floatBuffer(from: data, format: session.sourceFormat) else {
            return
        }

        let outputBuffer: AVAudioPCMBuffer
        if let converter = session.converter {
            outputBuffer = try Self.convert(sourceBuffer, using: converter, outputFormat: session.prepared.audioFormat)
        } else {
            outputBuffer = sourceBuffer
        }

        _ = session.continuation.yield(AnalyzerInput(buffer: outputBuffer))
    }

    func finish() async throws -> String {
        guard let session = activeSession else { throw EngineError.noActiveSession }
        activeSession = nil

        session.continuation.finish()
        do {
            try await session.prepared.analyzer.finalizeAndFinishThroughEndOfInput()
            let text = try await session.resultTask.value
            prewarmAfterSession(locale: session.prepared.locale)
            return text
        } catch {
            await session.prepared.analyzer.cancelAndFinishNow()
            session.resultTask.cancel()
            prewarmAfterSession(locale: session.prepared.locale)
            throw error
        }
    }

    func cancel() async {
        guard let session = activeSession else { return }
        activeSession = nil
        session.continuation.finish()
        await session.prepared.analyzer.cancelAndFinishNow()
        session.resultTask.cancel()
        prewarmAfterSession(locale: session.prepared.locale)
    }

    // MARK: - Locale

    private func resolveLocale(_ simpleCode: String) async throws -> Locale {
        let mapped = Self.mapToAppleLocale(simpleCode)
        if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: mapped)) {
            return supported
        }
        if let current = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            return current
        }
        if let english = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) {
            return english
        }
        throw EngineError.unsupportedLocale
    }

    private func ensureWarm(locale: Locale) async throws {
        let key = locale.identifier(.bcp47)
        if preparedSessions[key] != nil { return }

        let task: Task<PreparedSession, any Error>
        if let existing = buildTasks[key] {
            task = existing
        } else {
            task = Task { try await makePreparedSession(locale: locale) }
            buildTasks[key] = task
        }

        do {
            let prepared = try await task.value
            if preparedSessions[key] == nil {
                preparedSessions[key] = prepared
            }
            if buildTasks[key] == task {
                buildTasks[key] = nil
            }
        } catch {
            if buildTasks[key] == task {
                buildTasks[key] = nil
            }
            throw error
        }
    }

    private func takePreparedSession(locale: Locale) async throws -> PreparedSession {
        try await ensureWarm(locale: locale)
        let key = locale.identifier(.bcp47)
        guard let prepared = preparedSessions[key] else {
            throw EngineError.unavailable
        }
        preparedSessions[key] = nil
        return prepared
    }

    private func makePreparedSession(locale requestedLocale: Locale) async throws -> PreparedSession {
        guard SpeechTranscriber.isAvailable else {
            throw EngineError.unavailable
        }

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw EngineError.unsupportedLocale
        }

        _ = try? await AssetInventory.reserve(locale: locale)

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            logger.notice("Downloading Apple Speech assets for \(locale.identifier(.bcp47), privacy: .public)")
            try await request.downloadAndInstall()
        }

        let modules: [any SpeechModule] = [transcriber]
        guard let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            throw EngineError.missingAudioFormat
        }

        let analyzer = SpeechAnalyzer(
            modules: modules,
            options: SpeechAnalyzer.Options(priority: .high, modelRetention: .lingering)
        )
        try await analyzer.prepareToAnalyze(in: audioFormat)

        logger.notice("Apple Speech analyzer warm for \(locale.identifier(.bcp47), privacy: .public)")
        return PreparedSession(
            locale: locale,
            transcriber: transcriber,
            analyzer: analyzer,
            audioFormat: audioFormat
        )
    }

    private func prewarmAfterSession(locale: Locale) {
        Task {
            try? await ensureWarm(locale: locale)
        }
    }

    private func requestSpeechAccess() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .denied, .restricted:
            throw EngineError.unavailable
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            if !granted { throw EngineError.unavailable }
        @unknown default:
            throw EngineError.unavailable
        }
    }

    static func mapToAppleLocale(_ simpleCode: String) -> String {
        let mapping = [
            "en": "en-US", "es": "es-ES", "fr": "fr-FR", "de": "de-DE",
            "ar": "ar-SA", "it": "it-IT", "ja": "ja-JP", "ko": "ko-KR",
            "pt": "pt-BR", "yue": "yue-CN", "zh": "zh-CN",
        ]
        if simpleCode == "auto" { return Locale.current.identifier }
        return mapping[simpleCode] ?? (simpleCode.contains("-") ? simpleCode : "en-US")
    }

    // MARK: - PCM

    private static func floatBuffer(from data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        data.withUnsafeBytes { rawPtr in
            let int16Ptr = rawPtr.bindMemory(to: Int16.self)
            let floatPtr = buffer.floatChannelData![0]
            for i in 0..<sampleCount {
                floatPtr[i] = Float(int16Ptr[i]) / 32767.0
            }
        }
        return buffer
    }

    private static func convert(
        _ inputBuffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw EngineError.conversionFailed
        }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }

        if let conversionError {
            throw conversionError
        }
        guard status == .haveData || status == .inputRanDry else {
            throw EngineError.conversionFailed
        }
        return outputBuffer
    }
}
