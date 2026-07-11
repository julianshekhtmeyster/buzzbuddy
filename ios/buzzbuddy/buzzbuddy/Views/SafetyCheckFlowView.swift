import SwiftUI

/// The full BuzzBuddy safety-check flow: baseline setup, starting an event,
/// taking whichever test the AI examiner requests, and the final verdict.
struct SafetyCheckFlowView: View {
    @StateObject private var appState = AppState()

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
                    } else {
                        // "reaction", and "memory" until a dedicated memory test exists.
                        ReactionTestView { ms in
                            Task { await appState.submitTestResult(testType: "reaction", rawValue: ms) }
                        }
                    }
                }
            case .verdict:
                VerdictView()
            }
        }
        .environmentObject(appState)
    }
}

#Preview {
    SafetyCheckFlowView()
}
