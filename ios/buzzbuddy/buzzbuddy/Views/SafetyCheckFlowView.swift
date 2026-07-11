import SwiftUI

/// The full BuzzBuddy safety-check flow: baseline setup, starting an event,
/// taking whichever test the AI examiner requests, and the final verdict.
struct SafetyCheckFlowView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.phase {
            case .onboarding:
                OnboardingView()
            case .readyToStartEvent:
                StartEventView()
            case .takingTest(let pendingTest):
                VStack(spacing: 8) {
                    Text("AI requested: \(pendingTest) test")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if pendingTest == "gyro" || pendingTest == "balance" {
                        GyroBalanceTestView { score in
                            Task { await appState.submitTestResult(testType: pendingTest, rawValue: score) }
                        }
                    } else if pendingTest == "memory" {
                        MemoryRecallTestView { accuracy in
                            Task { await appState.submitTestResult(testType: "memory", rawValue: accuracy) }
                        }
                    } else {
                        ReactionTestView { ms in
                            Task { await appState.submitTestResult(testType: "reaction", rawValue: ms) }
                        }
                    }
                }
            case .verdict:
                VerdictView()
            }
        }
    }
}

#Preview {
    SafetyCheckFlowView().environmentObject(AppState())
}
