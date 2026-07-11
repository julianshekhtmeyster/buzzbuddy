import SwiftUI

/// Runs several reaction-time trials and reports the mean in milliseconds.
/// The first trial is a warm-up and is not included in the result.
struct ReactionTestView: View {
    var onComplete: (Double) -> Void

    private enum Stage {
        case waiting
        case ready
        case tooSoon
        case trialResult(Double)
        case complete(Double)
    }

    @State private var stage: Stage = .waiting
    @State private var targetAppearedAt: TimeInterval?
    @State private var pendingFlip: Task<Void, Never>?
    @State private var trialMilliseconds: [Double] = []
    @State private var totalTrials = TestEngine.Reaction.trialRange.lowerBound

    var body: some View {
        VStack(spacing: 24) {
            Text(progressText)
                .font(.caption)
                .foregroundStyle(.secondary)

            switch stage {
            case .waiting:
                Text("Wait for green...")
                    .font(.title2)
                Rectangle()
                    .fill(.red)
                    .frame(height: 240)
                    .onTapGesture { tapTooSoon() }
            case .ready:
                Text("Tap now!")
                    .font(.title2)
                Rectangle()
                    .fill(.green)
                    .frame(height: 240)
                    .onTapGesture { tapOnTarget() }
            case .tooSoon:
                Text("Too soon — retry this trial")
                    .font(.title2)
                Rectangle()
                    .fill(.orange)
                    .frame(height: 240)
                    .onTapGesture { restart() }
            case .trialResult(let ms):
                Text("\(Int(ms)) ms")
                    .font(.system(size: 48, weight: .bold))
                Button(trialMilliseconds.count == totalTrials ? "See Result" : "Next Trial") {
                    advance()
                }
                .buttonStyle(.borderedProminent)
            case .complete(let mean):
                Text("Average reaction time")
                    .font(.title2)
                Text("\(Int(mean.rounded())) ms")
                    .font(.system(size: 48, weight: .bold))
                Text("Warm-up trial excluded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Continue") { onComplete(mean) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear { beginTest() }
        .onDisappear { pendingFlip?.cancel() }
    }

    private var progressText: String {
        switch stage {
        case .complete:
            return "Completed \(totalTrials) trials"
        default:
            let current = min(trialMilliseconds.count + 1, totalTrials)
            return current == 1
                ? "Warm-up trial • 1 of \(totalTrials)"
                : "Scored trial \(current - 1) of \(totalTrials - 1)"
        }
    }

    private func beginTest() {
        totalTrials = Int.random(in: TestEngine.Reaction.trialRange)
        trialMilliseconds = []
        restart()
    }

    private func tapTooSoon() {
        pendingFlip?.cancel()
        stage = .tooSoon
    }

    private func tapOnTarget() {
        guard let targetAppearedAt else { return }
        let milliseconds = (ProcessInfo.processInfo.systemUptime - targetAppearedAt) * 1000
        trialMilliseconds.append(milliseconds)
        stage = .trialResult(milliseconds)
    }

    private func restart() {
        pendingFlip?.cancel()
        targetAppearedAt = nil
        stage = .waiting
        let delay = Double.random(in: TestEngine.Reaction.delayRange)
        pendingFlip = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, stageIsWaiting else { return }
            targetAppearedAt = ProcessInfo.processInfo.systemUptime
            stage = .ready
        }
    }

    private var stageIsWaiting: Bool {
        if case .waiting = stage { return true }
        return false
    }

    private func advance() {
        if trialMilliseconds.count < totalTrials {
            restart()
        } else if let mean = TestEngine.Reaction.meanMilliseconds(from: trialMilliseconds) {
            stage = .complete(mean)
        }
    }
}

#Preview {
    ReactionTestView { _ in }
}
