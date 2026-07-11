//
//  GaitTestView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/11/26.
//

import SwiftUI

/// Runs a single gait trial: hold the phone against your chest and walk
/// forward for 10 seconds while CoreMotion records acceleration/rotation,
/// then reports a stability score (higher = steadier gait). Reused both to
/// capture the sober baseline and for each AI-requested test -- see
/// GyroBalanceTestView for the same onComplete(Double) convention.
struct GaitTestView: View {
    var onComplete: (Double) -> Void

    private static let countdownSeconds = 5
    private static let recordingSeconds: Double = 10

    @StateObject private var recorder = MotionRecorder()

    @State private var countdown = GaitTestView.countdownSeconds
    @State private var isCountingDown = false
    @State private var isRecording = false
    @State private var completed = false


    var body: some View {

        VStack(spacing: 30) {

            Text("Walking")
                .font(.largeTitle)
                .bold()


            if isCountingDown {

                Text("\(countdown)")
                    .font(.system(size: 80))

                Text("Get ready...")
            }


            else if isRecording {

                Text("Walk Forward 10 Steps")
                    .font(.title)

                Text("Hold your phone firmly against your chest")

                ProgressView()
            }


            else if completed {

                Text("Complete")
                    .font(.largeTitle)

            }


            else {

                Text("""
                Hold your phone firmly against your chest.

                Walk forward naturally for 10 seconds.
                """)
                .multilineTextAlignment(.center)


                Button {
                    startCountdown()
                } label: {
                    Text("Start Test")
                        .font(.title2)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onDisappear { recorder.stopRecording() }
    }


    private func startCountdown() {

        isCountingDown = true
        countdown = Self.countdownSeconds

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in

            countdown -= 1

            if countdown == 0 {
                timer.invalidate()

                isCountingDown = false
                startRecording()
            }
        }
    }


    private func startRecording() {

        guard recorder.isAvailable else {
            // No motion hardware (e.g. some Simulator configs) — report a
            // neutral score rather than blocking the flow.
            completed = true
            onComplete(1.0)
            return
        }

        isRecording = true

        recorder.startRecording()


        DispatchQueue.main.asyncAfter(deadline: .now() + Self.recordingSeconds) {
            finishRecording()
        }
    }


    private func finishRecording() {

        recorder.stopRecording()

        let data = GaitTestData(
            timestamp: Date(),
            duration: recorder.duration,
            acceleration: recorder.acceleration,
            rotation: recorder.rotation,
            pitch: recorder.pitch,
            roll: recorder.roll
        )


        completed = true
        isRecording = false

        let score = Self.stabilityScore(from: data)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            onComplete(score)
        }
    }


    /// Higher = steadier. Converts step-to-step variance in acceleration
    /// magnitude into a bounded score comparable across baseline and live
    /// tests, matching GyroBalanceTestView's stabilityScore convention.
    private static func stabilityScore(from data: GaitTestData) -> Double {

        var magnitudes: [Double] = []
        magnitudes.reserveCapacity(data.acceleration.count)

        for sample: [Double] in data.acceleration {
            guard sample.count == 3 else { continue }
            let x: Double = sample[0]
            let y: Double = sample[1]
            let z: Double = sample[2]
            magnitudes.append(sqrt(x * x + y * y + z * z))
        }

        guard !magnitudes.isEmpty else { return 1.0 }

        var sum: Double = 0
        for value: Double in magnitudes { sum += value }
        let mean: Double = sum / Double(magnitudes.count)

        var squaredDiffSum: Double = 0
        for value: Double in magnitudes {
            let diff: Double = value - mean
            squaredDiffSum += diff * diff
        }
        let variance: Double = squaredDiffSum / Double(magnitudes.count)
        let strideVariability: Double = sqrt(variance)

        return 1.0 / (1.0 + strideVariability * 10)
    }
}

#Preview {
    GaitTestView { _ in }
}
