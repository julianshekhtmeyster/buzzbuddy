//
//  BaselineView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/11/26.
//


import SwiftUI

/// Where sober baselines are captured and re-taken. Unlike onboarding, this
/// never gates the rest of the app -- a user can navigate to Events,
/// Contacts, etc. with any (or none) of these set, and come back here later.
struct BaselineView: View {
    @EnvironmentObject var appState: AppState

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

    private var hasServerBaseline: Bool {
        appState.reactionBaselineMs != nil
            || appState.gyroBaselineScore != nil
            || appState.memoryBaselinePercent != nil
    }

    private var displayedReactionMs: Double? { appState.reactionBaselineMs ?? pendingReactionMs }
    private var displayedGyroScore: Double? { appState.gyroBaselineScore ?? pendingGyroScore }
    private var displayedMemoryPercent: Double? { appState.memoryBaselinePercent ?? pendingMemoryPercent }
    private var displayedGaitScore: Double? { appState.gaitBaselineScore }

    var body: some View {
        NavigationStack {
            Form {
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
            .navigationTitle("Baseline")
        }
        .sheet(isPresented: $showReactionBaselineTest) {
            ReactionTestView { ms in
                showReactionBaselineTest = false
                capture(reactionMs: ms)
            }
        }
        .sheet(isPresented: $showGyroBaselineTest) {
            GyroBalanceTestView { score in
                showGyroBaselineTest = false
                capture(gyroScore: score)
            }
        }
        .sheet(isPresented: $showMemoryBaselineTest) {
            MemoryBaselineTestView { percent in
                showMemoryBaselineTest = false
                capture(memoryPercent: percent)
            }
        }
        .sheet(isPresented: $showGaitBaselineTest) {
            GaitTestView { score in
                showGaitBaselineTest = false
                Task { await appState.updateBaseline(gaitBaselineScore: score) }
            }
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
