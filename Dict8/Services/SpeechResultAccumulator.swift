import Foundation

/// Accumulates Apple SpeechAnalyzer (and similar) finalized + volatile hypotheses
/// into a single live draft. Final chunks append; volatile chunks replace.
struct SpeechResultAccumulator: Sendable {
    private(set) var finalizedText = ""
    private(set) var volatileText = ""

    mutating func receive(_ text: String, isFinal: Bool) -> Update {
        if isFinal {
            finalizedText += text
            volatileText = ""
        } else {
            volatileText = text
        }
        return Update(finalizedText: finalizedText, volatileText: volatileText)
    }

    var completedText: String {
        finalizedText + volatileText
    }

    struct Update: Sendable {
        let finalizedText: String
        let volatileText: String

        var displayText: String {
            finalizedText + volatileText
        }
    }
}
