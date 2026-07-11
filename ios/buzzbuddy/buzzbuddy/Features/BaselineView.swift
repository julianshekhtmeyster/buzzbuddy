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
            VStack(spacing: 0) {
                Text("Baseline")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 14)

                ScrollView {
                    content
                        .padding(.horizontal, 12)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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

    @ViewBuilder
    private var content: some View {
        if needsProfile {
            profileContent
        } else {
            baselineContent
        }
    }

    // MARK: - Profile (onboarding)

    private var profileContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionGroup(title: "About you") {
                formField(icon: "person.fill", text: $name, placeholder: "Name")
                formField(icon: "scalemass.fill", text: $weightLbs, placeholder: "Weight (lbs)", keyboardType: .decimalPad)
                heightField
            }

            sectionGroup(title: "Designated driver") {
                formField(icon: "person.crop.circle", text: $ddName, placeholder: "Name")
                formField(icon: "phone.fill", text: $ddPhone, placeholder: "Phone", keyboardType: .phonePad)
            }

            if let error = appState.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.leading, 4)
            }

            saveProfileButton
        }
    }

    private var heightField: some View {
        HStack(spacing: 10) {
            Image(systemName: "ruler.fill")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            TextField("Height (ft)", text: $heightFeet)
                .font(.system(size: 16))
                .keyboardType(.numberPad)

            Divider()
                .frame(height: 18)

            TextField("Height (in)", text: $heightInches)
                .font(.system(size: 16))
                .keyboardType(.numberPad)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }

    private var saveProfileButton: some View {
        HStack {
            Spacer()
            Button {
                submitProfile()
            } label: {
                Text(appState.isLoading ? "Saving..." : "Save profile")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(canSubmitProfile && !appState.isLoading ? .white : Color.gray)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(
                                canSubmitProfile && !appState.isLoading
                                    ? Color.yellow
                                    : Color.yellow.opacity(0.35)
                            )
                    )
            }
            .disabled(!canSubmitProfile || appState.isLoading)
        }
        .padding(.top, 12)
    }

    // MARK: - Baseline tests

    private var baselineContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionGroup(title: "Tests") {
                testRow(
                    icon: "bolt.fill",
                    title: "Reaction",
                    value: displayedReactionMs.map { "\(Int($0)) ms" },
                    isRetest: displayedReactionMs != nil
                ) {
                    showReactionBaselineTest = true
                }
                testRow(
                    icon: "figure.stand",
                    title: "Balance",
                    value: displayedGyroScore.map { String(format: "%.2f", $0) },
                    isRetest: displayedGyroScore != nil
                ) {
                    showGyroBaselineTest = true
                }
                testRow(
                    icon: "brain.head.profile",
                    title: "Memory",
                    value: displayedMemoryPercent.map { "\(Int($0))% accurate" },
                    isRetest: displayedMemoryPercent != nil
                ) {
                    showMemoryBaselineTest = true
                }
                testRow(
                    icon: "figure.walk",
                    title: "Walking",
                    value: displayedGaitScore.map { String(format: "%.2f", $0) },
                    isRetest: displayedGaitScore != nil
                ) {
                    showGaitBaselineTest = true
                }
            }

            if !hasServerBaseline
                && (pendingReactionMs != nil || pendingGyroScore != nil || pendingMemoryPercent != nil) {
                Text("All three are needed before your baseline is saved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }

            if let error = appState.baselineErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.leading, 4)
            }
        }
    }

    // MARK: - Shared row builders

    private func sectionGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 10) {
                content()
            }
        }
    }

    private func formField(
        icon: String,
        text: Binding<String>,
        placeholder: String,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: text)
                .font(.system(size: 16))
                .keyboardType(keyboardType)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }

    private func testRow(
        icon: String,
        title: String,
        value: String?,
        isRetest: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)

                Text(value ?? "Not set")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: action) {
                Text(isRetest ? "Retest" : "Run test")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(appState.isLoading ? Color.gray : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(appState.isLoading ? Color.yellow.opacity(0.35) : Color.yellow)
                    )
            }
            .buttonStyle(.plain)
            .disabled(appState.isLoading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }

    // MARK: - Actions

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
