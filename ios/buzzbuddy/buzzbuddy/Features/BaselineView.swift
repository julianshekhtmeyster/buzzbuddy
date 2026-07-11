//
//  BaselineView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/11/26.
//


import SwiftUI

/// The one page for everything about the user while sober: their profile
/// (name/weight/height/DD contact) and their sober baseline test results.
/// Unlike a check-in, this never gates the rest of the app -- a user can
/// navigate to Events, Contacts, etc. with any (or none) of this set, and
/// come back here later. Profile setup used to be a separate onboarding
/// screen and baseline capture used separate test views from the real
/// AI-requested tests; both are consolidated here so there's a single
/// source of truth and the baseline is measured with the same games used
/// for the real check-in.
struct BaselineView: View {
    @EnvironmentObject var appState: AppState

    // Profile fields -- only relevant before onboarding is complete.
    @State private var name = ""
    @State private var weightLbs = ""
    @State private var heightFeet = ""
    @State private var heightInches = ""
    @State private var ddName = ""
    @State private var ddPhone = ""

    @State private var showReactionBaselineTest = false
    @State private var showGyroBaselineTest = false
    @State private var showMemoryBaselineTest = false
    @State private var showGaitBaselineTest = false

    // Locally captured values not yet confirmed to exist server-side --
    // only used during first-ever capture, when the backend requires all
    // three fields in a single call (its Baseline row can't be created
    // partially, since the columns are non-nullable). Once a baseline
    // exists server-side, edits submit immediately as independent partial
    // updates (retests).
    @State private var pendingReactionMs: Double?
    @State private var pendingGyroScore: Double?
    @State private var pendingMemoryPercent: Double?

    private var needsProfile: Bool {
        if case .onboarding = appState.phase { return true }
        return false
    }

    private var hasServerBaseline: Bool {
        appState.reactionBaselineMs != nil
            || appState.gyroBaselineScore != nil
            || appState.memoryBaselinePercent != nil
    }

    private var displayedReactionMs: Double? { appState.reactionBaselineMs ?? pendingReactionMs }
    private var displayedGyroScore: Double? { appState.gyroBaselineScore ?? pendingGyroScore }
    private var displayedMemoryPercent: Double? { appState.memoryBaselinePercent ?? pendingMemoryPercent }
    private var displayedGaitScore: Double? { appState.gaitBaselineScore }

    private var canSubmitProfile: Bool {
        OnboardingValidation.isNonEmpty(name)
            && OnboardingValidation.isValidWeightLbs(weightLbs)
            && OnboardingValidation.isValidHeight(feet: heightFeet, inches: heightInches)
            && OnboardingValidation.isNonEmpty(ddName)
            && OnboardingValidation.isNonEmpty(ddPhone)
    }

    var body: some View {
        NavigationStack {
            Form {
                if needsProfile {
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

                    Button(appState.isLoading ? "Saving..." : "Save profile") {
                        submitProfile()
                    }
                    .disabled(!canSubmitProfile || appState.isLoading)
                } else {
                    Section("Reaction") {
                        if let ms = displayedReactionMs {
                            Text("\(Int(ms)) ms")
                        } else {
                            Text("Not set").foregroundStyle(.secondary)
                        }
                        Button(displayedReactionMs == nil ? "Run test" : "Retest") {
                            showReactionBaselineTest = true
                        }
                        .disabled(appState.isLoading)
                    }

                    Section("Balance") {
                        if let score = displayedGyroScore {
                            Text(String(format: "%.2f", score))
                        } else {
                            Text("Not set").foregroundStyle(.secondary)
                        }
                        Button(displayedGyroScore == nil ? "Run test" : "Retest") {
                            showGyroBaselineTest = true
                        }
                        .disabled(appState.isLoading)
                    }

                    Section("Memory") {
                        if let percent = displayedMemoryPercent {
                            Text("\(Int(percent))% accurate")
                        } else {
                            Text("Not set").foregroundStyle(.secondary)
                        }
                        Button(displayedMemoryPercent == nil ? "Run test" : "Retest") {
                            showMemoryBaselineTest = true
                        }
                        .disabled(appState.isLoading)
                    }

                    Section("Walking") {
                        if let score = displayedGaitScore {
                            Text(String(format: "%.2f", score))
                        } else {
                            Text("Not set").foregroundStyle(.secondary)
                        }
                        Button(displayedGaitScore == nil ? "Run test" : "Retest") {
                            showGaitBaselineTest = true
                        }
                        .disabled(appState.isLoading)
                    }

                    if !hasServerBaseline
                        && (pendingReactionMs != nil || pendingGyroScore != nil || pendingMemoryPercent != nil) {
                        Text("All three are needed before your baseline is saved.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let error = appState.baselineErrorMessage {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Baseline")
        }
        .sheet(isPresented: $showReactionBaselineTest) {
            ReactionGame { ms in
                showReactionBaselineTest = false
                capture(reactionMs: Double(ms))
            }
        }
        .sheet(isPresented: $showGyroBaselineTest) {
            GyroBalanceTestView { score in
                showGyroBaselineTest = false
                capture(gyroScore: score)
            }
        }
        .sheet(isPresented: $showMemoryBaselineTest) {
            MemoryGame { accuracy in
                showMemoryBaselineTest = false
                capture(memoryPercent: Double(accuracy))
            }
        }
        .sheet(isPresented: $showGaitBaselineTest) {
            GaitTestView { score in
                showGaitBaselineTest = false
                Task { await appState.updateBaseline(gaitBaselineScore: score) }
            }
        }
    }

    private func submitProfile() {
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

    /// Retests (a baseline already exists server-side) submit immediately
    /// as a partial update. First-ever captures accumulate locally and
    /// only submit once all three are present, since the backend can't
    /// create a partial Baseline row.
    private func capture(reactionMs: Double? = nil, gyroScore: Double? = nil, memoryPercent: Double? = nil) {
        if hasServerBaseline {
            Task {
                await appState.updateBaseline(
                    reactionBaselineMs: reactionMs,
                    gyroBaselineScore: gyroScore,
                    memoryBaselinePercent: memoryPercent
                )
            }
            return
        }

        if let reactionMs { pendingReactionMs = reactionMs }
        if let gyroScore { pendingGyroScore = gyroScore }
        if let memoryPercent { pendingMemoryPercent = memoryPercent }

        guard let reaction = pendingReactionMs,
              let gyro = pendingGyroScore,
              let memory = pendingMemoryPercent
        else { return }

        Task {
            await appState.updateBaseline(
                reactionBaselineMs: reaction,
                gyroBaselineScore: gyro,
                memoryBaselinePercent: memory
            )
        }
    }
}

#Preview {
    BaselineView().environmentObject(AppState())
}
