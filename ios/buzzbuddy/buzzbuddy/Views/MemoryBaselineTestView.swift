import SwiftUI

/// Runs the memory-recall test three times back-to-back and reports the
/// average accuracy as the sober baseline. A single 5-digit round only
/// produces scores in 20% increments (0/20/40/60/80/100), which is too
/// coarse for a baseline value -- three rounds averaged give finer
/// resolution. Blocks interactive dismissal so a partial (1- or 2-round)
/// baseline can't be saved by swiping away mid-flow.
struct MemoryBaselineTestView: View {
    var onComplete: (Double) -> Void

    private static let totalRounds = 3

    @State private var round = 1
    @State private var roundScores: [Double] = []

    var body: some View {
        VStack(spacing: 12) {
            Text("Memory baseline \(round) of \(Self.totalRounds)")
                .font(.caption)
                .foregroundStyle(.secondary)

            MemoryRecallTestView { accuracy in
                roundScores.append(accuracy)
                if round < Self.totalRounds {
                    round += 1
                } else {
                    onComplete(MemoryBaselineScoring.average(of: roundScores))
                }
            }
            // Forces a fresh MemoryRecallTestView instance (new random
            // sequence, reset input) each round.
            .id(round)
        }
        .interactiveDismissDisabled()
    }
}

#Preview {
    MemoryBaselineTestView { _ in }
}
