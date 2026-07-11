import CoreMotion
import SwiftUI

/// Runs a single balance trial: hold the phone steady for 5 seconds while we
/// sample the gyroscope, then report a stability score (higher = steadier).
/// Reused both to capture the sober baseline and for each AI-requested test.
struct GyroBalanceTestView: View {
    var onComplete: (Double) -> Void

    private static let duration: Double = 5.0

    @State private var motionManager = CMMotionManager()
    @State private var samples: [Double] = []
    @State private var timeRemaining: Double = GyroBalanceTestView.duration
    @State private var isRunning = false
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 24) {
            Text(isRunning ? "Hold your phone as steady as possible" : "Ready to test your balance")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Stand on one leg to balance")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ZStack {
                Circle().stroke(lineWidth: 8).opacity(0.2)
                Circle()
                    .trim(from: 0, to: CGFloat(timeRemaining / Self.duration))
                    .stroke(isRunning ? Color.blue : Color.gray, lineWidth: 8)
                    .rotationEffect(.degrees(-90))
                Text(String(format: "%.1f", timeRemaining))
                    .font(.system(size: 48, weight: .bold))
            }
            .frame(width: 160, height: 160)

            if !isRunning {
                Button("Start Balance Test") { start() }
                    .font(.title2)
                    .fontWeight(.semibold)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .padding()
        .onDisappear { stop() }
    }

    private func start() {
        guard motionManager.isDeviceMotionAvailable else {
            // No motion hardware (e.g. some Simulator configs) — report a
            // neutral score rather than blocking the flow.
            onComplete(1.0)
            return
        }

        samples = []
        timeRemaining = Self.duration
        isRunning = true

        motionManager.deviceMotionUpdateInterval = 0.05
        motionManager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let motion else { return }
            let rate = motion.rotationRate
            samples.append(sqrt(rate.x * rate.x + rate.y * rate.y + rate.z * rate.z))
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            timeRemaining -= 0.1
            if timeRemaining <= 0 {
                finish()
            }
        }
    }

    private func finish() {
        let score = stabilityScore(from: samples)
        stop()
        onComplete(score)
    }

    private func stop() {
        motionManager.stopDeviceMotionUpdates()
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    /// Higher = steadier. Converts average rotation-rate magnitude (wobble)
    /// into a bounded score comparable across baseline and live tests.
    private func stabilityScore(from samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 1.0 }
        let avgWobble = samples.reduce(0, +) / Double(samples.count)
        return 1.0 / (1.0 + avgWobble * 10)
    }
}

#Preview {
    GyroBalanceTestView { _ in }
}
