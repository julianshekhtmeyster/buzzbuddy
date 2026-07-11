import Foundation

/// Shared configuration and scoring for baseline and in-session tests.
///
/// Every scorer returns the single `raw_value` expected by the API:
/// reaction time in milliseconds, gyroscope rotation-rate variance, or memory
/// accuracy as a percentage.
enum TestEngine {
    enum Reaction {
        static let trialRange = 5...7
        static let delayRange = 1.0...4.0

        static func meanMilliseconds(
            from trialMilliseconds: [Double],
            discardingWarmup: Bool = true
        ) -> Double? {
            let scoredTrials = discardingWarmup
                ? Array(trialMilliseconds.dropFirst())
                : trialMilliseconds
            guard !scoredTrials.isEmpty else { return nil }
            return scoredTrials.reduce(0, +) / Double(scoredTrials.count)
        }
    }

    enum Gyro {
        static let holdDuration = 12.0
        static let sampleInterval = 1.0 / 50.0

        /// Population variance of the rotation-rate magnitude, in
        /// `(radians/second)^2`.
        static func rotationRateVariance(from magnitudes: [Double]) -> Double? {
            guard !magnitudes.isEmpty else { return nil }
            let mean = magnitudes.reduce(0, +) / Double(magnitudes.count)
            return magnitudes.reduce(0) { total, value in
                let difference = value - mean
                return total + difference * difference
            } / Double(magnitudes.count)
        }
    }

    enum Memory {
        static let roundRange = 2...3
        static let digitRange = 4...6
        static let displayDuration = 3.0
        static let distractorDuration = 1.0

        static func makeSequence(length: Int) -> String {
            (0..<length).map { _ in String(Int.random(in: 0...9)) }.joined()
        }

        /// Percentage of digits recalled in their correct positions across
        /// all rounds. Missing or extra digits do not receive credit.
        static func accuracyPercentage(expected: [String], entered: [String]) -> Double? {
            guard expected.count == entered.count, !expected.isEmpty else { return nil }

            var correctDigits = 0
            var totalDigits = 0
            for (answer, response) in zip(expected, entered) {
                let answerDigits = Array(answer)
                let responseDigits = Array(response)
                totalDigits += answerDigits.count
                correctDigits += answerDigits.indices.reduce(0) { correct, index in
                    guard responseDigits.indices.contains(index),
                          responseDigits[index] == answerDigits[index] else {
                        return correct
                    }
                    return correct + 1
                }
            }

            guard totalDigits > 0 else { return nil }
            return Double(correctDigits) / Double(totalDigits) * 100.0
        }
    }
}
