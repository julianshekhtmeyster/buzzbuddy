import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState

    @State private var name = ""
    @State private var weightLbs = ""
    @State private var heightFeet = ""
    @State private var heightInches = ""
    @State private var ddName = ""
    @State private var ddPhone = ""

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

            if let error = appState.errorMessage {
                Text(error).foregroundStyle(.red)
            }

            Button(appState.isLoading ? "Saving..." : "Finish setup") {
                submit()
            }
            .disabled(!canSubmit || appState.isLoading)
        }
    }

    private var canSubmit: Bool {
        OnboardingValidation.isNonEmpty(name)
            && OnboardingValidation.isValidWeightLbs(weightLbs)
            && OnboardingValidation.isValidHeight(feet: heightFeet, inches: heightInches)
            && OnboardingValidation.isNonEmpty(ddName)
            && OnboardingValidation.isNonEmpty(ddPhone)
    }

    private func submit() {
        guard OnboardingValidation.isValidWeightLbs(weightLbs),
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
                ddName: ddName.trimmingCharacters(in: .whitespacesAndNewlines),
                ddPhone: ddPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}

#Preview {
    OnboardingView().environmentObject(AppState())
}
