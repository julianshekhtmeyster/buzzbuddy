import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState

    @State private var name = ""
    @State private var weightLbs = ""
    @State private var heightFeet = ""
    @State private var heightInches = ""
    @State private var ddName = ""
    @State private var ddPhone = ""
    @State private var showReactionBaselineTest = false
    @State private var reactionBaselineMs: Double?
    @State private var showGyroBaselineTest = false
    @State private var gyroBaselineScore: Double?
    @State private var showMemoryBaselineTest = false
    @State private var memoryBaselinePercent: Double?

    var body: some View {
        Form {
            Section("About you") {
                TextField("Name", text: $name)
                TextField("Weight (lbs)", text: $weightLbs)
                    .keyboardType(.decimalPad)
                HStack {
                    TextField("Height (ft)", text: $heightFeet)
                        .keyboardType(.numberPad)
                    TextField("Height (in)", text: $heightInches)
                        .keyboardType(.numberPad)
                }
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

                if let score = memoryBaselinePercent {
                    Text("Memory baseline: \(Int(score))% accurate")
                } else {
                    Button("Run memory baseline test") { showMemoryBaselineTest = true }
                }
            }

            if let error = appState.errorMessage {
                Text(error).foregroundStyle(.red)
            }

            Button(appState.isLoading ? "Saving..." : "Finish setup") {
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
            MemoryBaselineTestView { percent in
                memoryBaselinePercent = percent
                showMemoryBaselineTest = false
            }
        }
    }

    private var canSubmit: Bool {
        reactionBaselineMs != nil
            && gyroBaselineScore != nil
            && memoryBaselinePercent != nil
            && OnboardingValidation.isNonEmpty(name)
            && OnboardingValidation.isValidWeightLbs(weightLbs)
            && OnboardingValidation.isValidHeight(feet: heightFeet, inches: heightInches)
            && OnboardingValidation.isNonEmpty(ddName)
            && OnboardingValidation.isNonEmpty(ddPhone)
    }

    private func submit() {
        guard let ms = reactionBaselineMs,
              let gyroScore = gyroBaselineScore,
              let memoryScore = memoryBaselinePercent,
              OnboardingValidation.isValidWeightLbs(weightLbs),
              OnboardingValidation.isValidHeight(feet: heightFeet, inches: heightInches),
              let weightLbsValue = Double(weightLbs),
              let heightInValue = OnboardingValidation.totalHeightInches(feet: heightFeet, inches: heightInches)
        else { return }

        let weightKg = weightLbsValue * 0.453592
        let heightCm = heightInValue * 2.54
        let bmi = weightKg / pow(heightCm / 100, 2)

        Task {
            await appState.completeOnboarding(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                weightKg: weightKg,
                heightCm: heightCm,
                bmi: bmi,
                reactionBaselineMs: ms,
                gyroBaselineScore: gyroScore,
                memoryBaselinePercent: memoryScore,
                ddName: ddName.trimmingCharacters(in: .whitespacesAndNewlines),
                ddPhone: ddPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}

#Preview {
    OnboardingView().environmentObject(AppState())
}
