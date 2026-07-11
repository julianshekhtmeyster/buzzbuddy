import SwiftUI

/// Runs a single reaction-time trial and reports the elapsed milliseconds.
/// Reused both to capture the sober baseline and for each AI-requested test.
struct ReactionTestView: View {
    var onComplete: (Double) -> Void

    private enum Stage {
        case waiting
        case ready
        case tooSoon
        case result(Double)
    }

    @State private var stage: Stage = .waiting
    @State private var startTime: Date?
    @State private var pendingFlip: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 24) {
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
                Text("Too soon — tap to retry")
                    .font(.title2)
                Rectangle()
                    .fill(.orange)
                    .frame(height: 240)
                    .onTapGesture { restart() }
            case .result(let ms):
                Text("\(Int(ms)) ms")
                    .font(.system(size: 48, weight: .bold))
                Button("Continue") { onComplete(ms) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear { restart() }
        .onDisappear { pendingFlip?.cancel() }
    }

    private func tapTooSoon() {
        pendingFlip?.cancel()
        stage = .tooSoon
    }

    private func tapOnTarget() {
        let ms = Date().timeIntervalSince(startTime ?? Date()) * 1000
        stage = .result(ms)
    }

    private func restart() {
        stage = .waiting
        let delay = Double.random(in: 1.5...4.0)
        pendingFlip = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            startTime = Date()
            stage = .ready
        }
    }
}

#Preview {
    ReactionTestView { _ in }
}
