import Foundation

/// Pure scoring/input-gating rules for a single memory-recall round, kept
/// separate from the view so they're directly testable without UI
/// automation. `accuracy` requires equal lengths on purpose -- a length
/// mismatch previously let `zip` silently drop extra incorrect digits
/// instead of counting against the score.
enum MemoryRecallScoring {
    static func canAppendDigit(currentInputCount: Int, sequenceLength: Int) -> Bool {
        currentInputCount < sequenceLength
    }

    static func canSubmit(inputCount: Int, sequenceLength: Int) -> Bool {
        inputCount == sequenceLength
    }

    /// 0...100. Returns 0 if the lengths don't match rather than scoring a
    /// truncated prefix.
    static func accuracy(sequence: [Int], input: [Int]) -> Double {
        guard !sequence.isEmpty, sequence.count == input.count else { return 0 }
        let matches = zip(sequence, input).filter { $0 == $1 }.count
        return (Double(matches) / Double(sequence.count)) * 100
    }
}

/// Averages the per-round accuracies from a multi-round memory baseline.
enum MemoryBaselineScoring {
    static func average(of roundScores: [Double]) -> Double {
        guard !roundScores.isEmpty else { return 0 }
        return roundScores.reduce(0, +) / Double(roundScores.count)
    }
}
