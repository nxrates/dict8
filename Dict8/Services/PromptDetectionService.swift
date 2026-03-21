import Foundation
import os

class PromptDetectionService {
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.dict8",
        category: "promptdetection"
    )

    struct PromptDetectionResult {
        let shouldEnableAI: Bool
        let selectedPromptId: UUID?
        let processedText: String
        let detectedTriggerWord: String?
        let originalEnhancementState: Bool
        let originalPromptId: UUID?
    }

    @MainActor
    func analyzeText(_ text: String, with enhancementService: AIEnhancementService) -> PromptDetectionResult {
        let originalEnhancementState = enhancementService.isEnhancementEnabled
        let originalPromptId = enhancementService.selectedPromptId

        for prompt in enhancementService.allPrompts {
            if !prompt.triggerWords.isEmpty,
               let (detectedWord, processedText) = detectAndStripTriggerWord(from: text, triggerWords: prompt.triggerWords) {
                return PromptDetectionResult(
                    shouldEnableAI: true, selectedPromptId: prompt.id,
                    processedText: processedText, detectedTriggerWord: detectedWord,
                    originalEnhancementState: originalEnhancementState, originalPromptId: originalPromptId
                )
            }
        }

        return PromptDetectionResult(
            shouldEnableAI: false, selectedPromptId: nil,
            processedText: text, detectedTriggerWord: nil,
            originalEnhancementState: originalEnhancementState, originalPromptId: originalPromptId
        )
    }

    func applyDetectionResult(_ result: PromptDetectionResult, to enhancementService: AIEnhancementService) async {
        await MainActor.run {
            if result.shouldEnableAI {
                if !enhancementService.isEnhancementEnabled { enhancementService.isEnhancementEnabled = true }
                if let promptId = result.selectedPromptId { enhancementService.selectedPromptId = promptId }
            }
        }
        if result.shouldEnableAI { try? await Task.sleep(nanoseconds: 50_000_000) }
    }

    func restoreOriginalSettings(_ result: PromptDetectionResult, to enhancementService: AIEnhancementService) async {
        if result.shouldEnableAI {
            await MainActor.run {
                if enhancementService.isEnhancementEnabled != result.originalEnhancementState {
                    enhancementService.isEnhancementEnabled = result.originalEnhancementState
                }
                if let originalId = result.originalPromptId, enhancementService.selectedPromptId != originalId {
                    enhancementService.selectedPromptId = originalId
                }
            }
        }
    }

    // MARK: - Trigger Word Stripping

    private func stripTriggerWord(from text: String, triggerWord: String, position: Position) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerText = trimmedText.lowercased()
        let lowerTrigger = triggerWord.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        switch position {
        case .leading:
            guard lowerText.hasPrefix(lowerTrigger) else { return nil }
            let endIdx = trimmedText.index(trimmedText.startIndex, offsetBy: triggerWord.count)
            if endIdx < trimmedText.endIndex {
                let ch = trimmedText[endIdx]
                if ch.isLetter || ch.isNumber { return nil }
            }
            if endIdx >= trimmedText.endIndex { return "" }
            return cleanRemainder(String(trimmedText[endIdx...]), strippingPattern: "^[,\\.!\\?;:\\s]+")

        case .trailing:
            var cleaned = trimmedText
            let punctuation = CharacterSet(charactersIn: ",.!?;:")
            while let scalar = cleaned.unicodeScalars.last, punctuation.contains(scalar) { cleaned.removeLast() }
            let lowerCleaned = cleaned.lowercased()
            guard lowerCleaned.hasSuffix(lowerTrigger) else { return nil }
            let startIdx = cleaned.index(cleaned.endIndex, offsetBy: -triggerWord.count)
            if startIdx > cleaned.startIndex {
                let ch = cleaned[cleaned.index(before: startIdx)]
                if ch.isLetter || ch.isNumber { return nil }
            }
            return cleanRemainder(String(cleaned[..<startIdx]), strippingPattern: "[,\\.!\\?;:\\s]+$")
        }
    }

    private func cleanRemainder(_ text: String, strippingPattern: String) -> String {
        var result = text.replacingOccurrences(of: strippingPattern, with: "", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if !result.isEmpty { result = result.prefix(1).uppercased() + result.dropFirst() }
        return result
    }

    private func detectAndStripTriggerWord(from text: String, triggerWords: [String]) -> (String, String)? {
        let sorted = triggerWords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        // Try trailing first, then leading (each pass also tries to strip the other side)
        for position in [Position.trailing, .leading] {
            for word in sorted {
                if let after = stripTriggerWord(from: text, triggerWord: word, position: position) {
                    let otherPos: Position = position == .trailing ? .leading : .trailing
                    if let afterBoth = stripTriggerWord(from: after, triggerWord: word, position: otherPos) {
                        return (word, afterBoth)
                    }
                    return (word, after)
                }
            }
        }
        return nil
    }

    private enum Position { case leading, trailing }
}
