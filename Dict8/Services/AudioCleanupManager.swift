import Foundation
import SwiftData

/// A utility class that manages automatic cleanup of audio files while preserving transcript data
class AudioCleanupManager {
    static let shared = AudioCleanupManager()

    private var cleanupTimer: Timer?

    // Default cleanup settings
    private let defaultRetentionDays = 7
    private let cleanupCheckInterval: TimeInterval = 86400 // Check once per day (in seconds)

    private init() {}

    /// Start the automatic cleanup process
    func startAutomaticCleanup(modelContext: ModelContext) {
        // Cancel any existing timer
        cleanupTimer?.invalidate()

        // Perform initial cleanup
        Task {
            await performCleanup(modelContext: modelContext)
        }

        // Schedule regular cleanup
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupCheckInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.performCleanup(modelContext: modelContext)
            }
        }
    }

    /// Stop the automatic cleanup process
    func stopAutomaticCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    /// Get information about the files that would be cleaned up
    func getCleanupInfo(modelContext: ModelContext) async -> (fileCount: Int, totalSize: Int64, transcriptions: [Transcription]) {
        do {
            let transcriptions = try await fetchEligibleTranscriptions(modelContext: modelContext)
            var fileCount = 0
            var totalSize: Int64 = 0
            var eligibleTranscriptions: [Transcription] = []

            for transcription in transcriptions {
                if let url = audioFileURL(for: transcription) {
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let fileSize = attributes[.size] as? Int64 {
                        totalSize += fileSize
                        fileCount += 1
                        eligibleTranscriptions.append(transcription)
                    }
                }
            }

            return (fileCount, totalSize, eligibleTranscriptions)
        } catch {
            return (0, 0, [])
        }
    }

    /// Perform the cleanup operation
    private func performCleanup(modelContext: ModelContext) async {
        // Check if automatic cleanup is enabled
        let isCleanupEnabled = UserDefaults.standard.bool(forKey: "IsAudioCleanupEnabled")
        guard isCleanupEnabled else { return }

        do {
            let transcriptions = try await fetchEligibleTranscriptions(modelContext: modelContext)
            try await MainActor.run {
                var deletedCount = 0
                for transcription in transcriptions {
                    if let url = audioFileURL(for: transcription) {
                        do {
                            try FileManager.default.removeItem(at: url)
                            transcription.audioFileURL = nil
                            deletedCount += 1
                        } catch {
                            // Skip this file - don't update audioFileURL if deletion failed
                        }
                    }
                }
                if deletedCount > 0 {
                    try modelContext.save()
                }
            }
        } catch {
            // Silently fail - cleanup is non-critical
        }
    }

    /// Run cleanup manually - can be called from settings
    func runManualCleanup(modelContext: ModelContext) async {
        await performCleanup(modelContext: modelContext)
    }

    /// Run cleanup on the specified transcriptions
    func runCleanupForTranscriptions(modelContext: ModelContext, transcriptions: [Transcription]) async -> (deletedCount: Int, errorCount: Int) {
        do {
            // Execute SwiftData operations on the main thread
            return try await MainActor.run {
                var deletedCount = 0
                var errorCount = 0

                for transcription in transcriptions {
                    if let url = audioFileURL(for: transcription) {
                        do {
                            try FileManager.default.removeItem(at: url)
                            transcription.audioFileURL = nil
                            deletedCount += 1
                        } catch {
                            errorCount += 1
                        }
                    }
                }

                if deletedCount > 0 || errorCount > 0 {
                    try? modelContext.save()
                }

                return (deletedCount, errorCount)
            }
        } catch {
            return (0, 0)
        }
    }

    /// Format file size in human-readable form
    func formatFileSize(_ size: Int64) -> String {
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.allowedUnits = [.useKB, .useMB, .useGB]
        byteCountFormatter.countStyle = .file
        return byteCountFormatter.string(fromByteCount: size)
    }

    // MARK: - Private Helpers

    /// Fetches transcriptions with audio files older than the retention period.
    private func fetchEligibleTranscriptions(modelContext: ModelContext) async throws -> [Transcription] {
        let effectiveRetentionDays = UserDefaults.standard.integer(forKey: "AudioRetentionPeriod")
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -effectiveRetentionDays, to: Date()) else {
            return []
        }

        return try await MainActor.run {
            let descriptor = FetchDescriptor<Transcription>(
                predicate: #Predicate<Transcription> { transcription in
                    transcription.timestamp < cutoffDate &&
                    transcription.audioFileURL != nil
                }
            )
            return try modelContext.fetch(descriptor)
        }
    }

    /// Returns the file URL for a transcription's audio file, if it exists on disk.
    private func audioFileURL(for transcription: Transcription) -> URL? {
        guard let urlString = transcription.audioFileURL,
              let url = URL(string: urlString),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }
}
