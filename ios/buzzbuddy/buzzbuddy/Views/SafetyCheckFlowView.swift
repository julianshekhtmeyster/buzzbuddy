import SwiftUI

/// The full BuzzBuddy safety-check flow: onboarding, starting an event,
/// taking whichever test the AI examiner requests, and the final verdict.
/// Sober baselines are captured separately, from the Baseline tab.
/// Observes the app-wide AppState injected by BuzzBuddyApp -- never creates
/// its own, so every tab that embeds this shares one session.
struct SafetyCheckFlowView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        switch appState.phase {
        case .onboarding:
            OnboardingView()
        case .restoring:
            ProgressView("Restoring your check-in...")
        case .restoreFailed:
            RestoreFailedView()
        case .readyToStartEvent:
            StartEventView()
        case .startingEvent:
            ProgressView("Starting your check-in...")
        case .takingTest(let pendingTest):
            TestPromptView(pendingTest: pendingTest)
        case .reviewingTest(let pendingTest):
            VStack(spacing: 12) {
                Text("AI requested: \(pendingTest) test")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView("Reviewing your result...")
            }
        case .submissionFailed(let pendingTest, _, _):
            SubmissionFailedView(pendingTest: pendingTest)
        case .unsupportedTest(let pendingTest):
            UnsupportedTestView(pendingTest: pendingTest)
        case .verdict:
            VerdictView()
        }
    }
}

/// Routes a `pendingTest` string to its test view. Only reaction, gyro/
/// balance, and memory are recognized -- anything else is a controlled
/// error, never a silent fallback to the reaction test.
private struct TestPromptView: View {
    @EnvironmentObject var appState: AppState
    let pendingTest: String

    var body: some View {
        VStack(spacing: 8) {
            Text("AI requested: \(pendingTest) test")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch TestKind(pendingTest: pendingTest) {
            case .reaction:
                ReactionGame { ms in
                    Task { await appState.submitTestResult(testType: pendingTest, rawValue: Double(ms)) }
                }
            case .balance:
                GyroBalanceTestView { variance in
                    Task { await appState.submitTestResult(testType: pendingTest, rawValue: variance) }
                }
            case .memory:
                MemoryGame { accuracy in
                    Task { await appState.submitTestResult(testType: pendingTest, rawValue: Double(accuracy)) }
                }
            case .unknown:
                UnsupportedTestView(pendingTest: pendingTest)
            }
        }
    }
}

private struct UnsupportedTestView: View {
    let pendingTest: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("The examiner requested a test type this app version doesn't support (\"\(pendingTest)\").")
                .multilineTextAlignment(.center)
            Text("Update the app, or contact support if this keeps happening.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct SubmissionFailedView: View {
    @EnvironmentObject var appState: AppState
    let pendingTest: String

    var body: some View {
        VStack(spacing: 12) {
            Text("AI requested: \(pendingTest) test")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.red)
            if let error = appState.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button("Retry") {
                Task { await appState.retrySubmission() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isLoading)
        }
        .padding()
    }
}

private struct RestoreFailedView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Couldn't restore your active check-in.")
                .multilineTextAlignment(.center)
            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Retry") {
                Task { await appState.retryRestore() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isLoading)

            Button("Start a new check-in", role: .destructive) {
                appState.discardSession()
            }
        }
        .padding()
    }
}

#Preview {
    SafetyCheckFlowView().environmentObject(AppState())
}
