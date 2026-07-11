import SwiftUI

/// Shown to an existing (already-onboarded) user who is missing one or more
/// sober baselines -- e.g. they onboarded before the memory-recall baseline
/// existed. Only prompts for whichever baseline(s) are actually missing,
/// and PATCHes the existing backend user rather than creating a new one.
struct BaselineUpgradeView: View {
    @EnvironmentObject var appState: AppState

    @State private var showReactionBaselineTest = false
    @State private var reactionBaselineMs: Double?
    @State private var showGyroBaselineTest = false
    @State private var gyroBaselineScore: Double?
    @State private var showMemoryBaselineTest = false
    @State private var memoryBaselinePercent: Double?

    private var needsReaction: Bool { appState.reactionBaselineMs == nil }
    private var needsGyro: Bool { appState.gyroBaselineScore == nil }
    private var needsMemory: Bool { appState.memoryBaselinePercent == nil }

    private var canSubmit: Bool {
        (!needsReaction || reactionBaselineMs != nil)
            && (!needsGyro || gyroBaselineScore != nil)
            && (!needsMemory || memoryBaselinePercent != nil)
    }

    var body: some View {
        Form {
            Section {
                Text("BuzzBuddy added a new sober baseline test since your profile was set up. Complete the missing test(s) below to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Missing baseline") {
                if needsReaction {
                    if let ms = reactionBaselineMs {
                        Text("Reaction baseline: \(Int(ms)) ms")
                    } else {
                        Button("Run reaction baseline test") { showReactionBaselineTest = true }
                    }
                }

                if needsGyro {
                    if let score = gyroBaselineScore {
                        Text("Balance baseline: \(String(format: "%.2f", score))")
                    } else {
                        Button("Run balance baseline test") { showGyroBaselineTest = true }
                    }
                }

                if needsMemory {
                    if let score = memoryBaselinePercent {
                        Text("Memory baseline: \(Int(score))% accurate")
                    } else {
                        Button("Run memory baseline test") { showMemoryBaselineTest = true }
                    }
                }
            }

            if let error = appState.errorMessage {
                Text(error).foregroundStyle(.red)
            }

            Button(appState.isLoading ? "Saving..." : "Continue") {
                Task {
                    await appState.completeBaselineUpgrade(
                        reactionBaselineMs: reactionBaselineMs,
                        gyroBaselineScore: gyroBaselineScore,
                        memoryBaselinePercent: memoryBaselinePercent
                    )
                }
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
}

#Preview {
    BaselineUpgradeView().environmentObject(AppState())
}
