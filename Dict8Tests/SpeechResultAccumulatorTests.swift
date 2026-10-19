import Testing
@testable import Dict8

struct SpeechResultAccumulatorTests {
    @Test func keepsLastVolatileResultWhenFinalizationEndsTheStream() {
        var accumulator = SpeechResultAccumulator()

        _ = accumulator.receive("Hello world", isFinal: false)

        #expect(accumulator.completedText == "Hello world")
    }

    @Test func replacesVolatileTextWhenAResultBecomesFinal() {
        var accumulator = SpeechResultAccumulator()

        _ = accumulator.receive("Hello", isFinal: false)
        _ = accumulator.receive("Hello", isFinal: true)
        _ = accumulator.receive(" world", isFinal: false)

        #expect(accumulator.completedText == "Hello world")
    }

    @Test func displayTextJoinsFinalizedAndVolatile() {
        var accumulator = SpeechResultAccumulator()

        let first = accumulator.receive("The quick ", isFinal: true)
        #expect(first.displayText == "The quick ")

        let second = accumulator.receive("brown fox", isFinal: false)
        #expect(second.displayText == "The quick brown fox")
        #expect(second.finalizedText == "The quick ")
        #expect(second.volatileText == "brown fox")
    }
}
