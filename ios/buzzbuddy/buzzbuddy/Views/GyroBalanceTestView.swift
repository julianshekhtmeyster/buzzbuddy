import CoreMotion
import SwiftUI

/// Runs a balance trial while sampling the gyroscope, then reports the
/// variance of the rotation-rate magnitude.
/// Reused both to capture the sober baseline and for each AI-requested test.
struct GyroBalanceTestView: View {
    var onComplete: (Double) -> Void

    private static let duration = TestEngine.Gyro.holdDuration

    @State private var motionManager = CMMotionManager()
    @State private var samples: [Double] = []
    @State private var timeRemaining: Double = GyroBalanceTestView.duration
    @State private var isRunning = false
    @State private var timer: Timer?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Text(isRunning ? "Hold your phone as steady as possible" : "Ready to test your balance")
                .font(.title3)
                .multilineTextAlignment(.center)

            ZStack {
                Circle().stroke(lineWidth: 8).opacity(0.2)
                Circle()
                    .trim(from: 0, to: CGFloat(timeRemaining / Self.duration))
                    .stroke(isRunning ? Color.blue : Color.gray, lineWidth: 8)
                    .rotationEffect(.degrees(-90))
                Text(String(format: "%.1f", timeRemaining))
                    .font(.system(size: 40, weight: .bold))
            }
            .frame(width: 160, height: 160)

            if !isRunning {
                Button("Start Balance Test") { start() }
                    .buttonStyle(.borderedProminent)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .onDisappear { stop() }
    }

    private func start() {
        guard motionManager.isGyroAvailable else {
            errorMessage = "Gyroscope data is unavailable on this device. Please try on an iPhone."
            return
        }

        errorMessage = nil
        samples = []
        timeRemaining = Self.duration
        isRunning = true

        motionManager.gyroUpdateInterval = TestEngine.Gyro.sampleInterval
        motionManager.startGyroUpdates(to: .main) { data, error in
            if let error {
                errorMessage = "Motion sampling stopped: \(error.localizedDescription)"
                stop()
                return
            }
            guard let rate = data?.rotationRate else { return }
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
        stop()
        guard let variance = TestEngine.Gyro.rotationRateVariance(from: samples) else {
            errorMessage = "No motion samples were captured. Please try again."
            return
        }
        onComplete(variance)
    }

    private func stop() {
        motionManager.stopGyroUpdates()
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

}

#Preview {
    GyroBalanceTestView { _ in }
}
