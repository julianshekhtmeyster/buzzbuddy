import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState

    @State private var name = ""
    @State private var weightLbs = ""
    @State private var heightIn = ""
    @State private var ddName = ""
    @State private var ddPhone = ""
    @State private var showReactionBaselineTest = false
    @State private var reactionBaselineMs: Double?
    @State private var showGyroBaselineTest = false
    @State private var gyroBaselineScore: Double?
    @State private var showMemoryBaselineTest = false
    @State private var memoryBaselineScore: Double?

    var body: some View {
        Form {
            Section("About you") {
                TextField("Name", text: $name)
                TextField("Weight (lbs)", text: $weightLbs)
                    .keyboardType(.decimalPad)
                TextField("Height (in)", text: $heightIn)
                    .keyboardType(.decimalPad)
            }

            Section("Designated driver") {
                TextField("Name", text: $ddName)
                TextField("Phone", text: $ddPhone)
                    .keyboardType(.phonePad)
            }

            Section("Sober baseline") {
                if let ms = reactionBaselineMs {
                    Text("Reaction baseline: \(Int(ms)) ms")
                } else {
                    Button("Run reaction baseline test") { showReactionBaselineTest = true }
                }

                if let score = gyroBaselineScore {
                    Text("Balance baseline: \(String(format: "%.2f", score))")
                } else {
                    Button("Run balance baseline test") { showGyroBaselineTest = true }
                }

                if let score = memoryBaselineScore {
                    Text("Memory baseline: \(Int(score))% accurate")
                } else {
                    Button("Run memory baseline test") { showMemoryBaselineTest = true }
                }
            }

            if let error = appState.errorMessage {
                Text(error).foregroundStyle(.red)
            }

            Button(appState.isLoading ? "Saving..." : "Start my night") {
                submit()
            }
            .disabled(!canSubmit || appState.isLoading)
        }
        .sheet(isPresented: $showReactionBaselineTest) {
            ReactionTestView { ms in
                reactionBaselineMs = ms
                showReactionBaselineTest = false
            }
        }
        .sheet(isPresented: $showGyroBaselineTest) {
            GyroBalanceTestView { score in
                gyroBaselineScore = score
                showGyroBaselineTest = false
            }
        }
        .sheet(isPresented: $showMemoryBaselineTest) {
            MemoryRecallTestView { accuracy in
                memoryBaselineScore = accuracy
                showMemoryBaselineTest = false
            }
        }
    }

    private var canSubmit: Bool {
        reactionBaselineMs != nil
            && gyroBaselineScore != nil
            && memoryBaselineScore != nil
            && !name.isEmpty
            && Double(weightLbs) != nil
            && Double(heightIn) != nil
            && !ddName.isEmpty
    }

    private func submit() {
        guard let ms = reactionBaselineMs,
              let gyroScore = gyroBaselineScore,
              let memoryScore = memoryBaselineScore,
              let weightLbs = Double(weightLbs),
              let heightIn = Double(heightIn) else { return }

        let weightKg = weightLbs * 0.453592
        let heightCm = heightIn * 2.54
        let bmi = weightKg / pow(heightCm / 100, 2)

        Task {
            await appState.completeOnboarding(
                name: name,
                weightKg: weightKg,
                heightCm: heightCm,
                bmi: bmi,
                reactionBaselineMs: ms,
                gyroBaselineScore: gyroScore,
                memoryBaselineScore: memoryScore,
                ddName: ddName,
                ddPhone: ddPhone
            )
        }
    }
}

#Preview {
    OnboardingView().environmentObject(AppState())
}
