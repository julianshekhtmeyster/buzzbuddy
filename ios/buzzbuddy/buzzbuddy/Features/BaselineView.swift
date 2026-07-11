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

    var body: some View {
        NavigationStack {
            Form {
                Section("Reaction") {
                    if let ms = appState.reactionBaselineMs {
                        Text("\(Int(ms)) ms")
                    } else {
                        Text("Not set").foregroundStyle(.secondary)
                    }
                    Button(appState.reactionBaselineMs == nil ? "Run test" : "Retest") {
                        showReactionBaselineTest = true
                    }
                    .disabled(appState.isLoading)
                }

                Section("Balance") {
                    if let score = appState.gyroBaselineScore {
                        Text(String(format: "%.2f", score))
                    } else {
                        Text("Not set").foregroundStyle(.secondary)
                    }
                    Button(appState.gyroBaselineScore == nil ? "Run test" : "Retest") {
                        showGyroBaselineTest = true
                    }
                    .disabled(appState.isLoading)
                }

                Section("Memory") {
                    if let percent = appState.memoryBaselinePercent {
                        Text("\(Int(percent))% accurate")
                    } else {
                        Text("Not set").foregroundStyle(.secondary)
                    }
                    Button(appState.memoryBaselinePercent == nil ? "Run test" : "Retest") {
                        showMemoryBaselineTest = true
                    }
                    .disabled(appState.isLoading)
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
                Task { await appState.updateBaseline(reactionBaselineMs: ms) }
            }
        }
        .sheet(isPresented: $showGyroBaselineTest) {
            GyroBalanceTestView { score in
                showGyroBaselineTest = false
                Task { await appState.updateBaseline(gyroBaselineScore: score) }
            }
        }
        .sheet(isPresented: $showMemoryBaselineTest) {
            MemoryBaselineTestView { percent in
                showMemoryBaselineTest = false
                Task { await appState.updateBaseline(memoryBaselinePercent: percent) }
            }
        }
    }
}

#Preview {
    BaselineView().environmentObject(AppState())
}
