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
            ReviewingTestView(pendingTest: pendingTest)
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
            case .gait:
                GaitTestView { score in
                    Task { await appState.submitTestResult(testType: pendingTest, rawValue: score) }
                }
            case .unknown:
                UnsupportedTestView(pendingTest: pendingTest)
            }
        }
    }
}

/// Shown while `submitTestResult` is in flight. AppState briefly holds this
/// phase after a fresh reasoning line arrives (see AppState.performSubmit)
/// so the dropdown below has time to flip from placeholder to real content
/// before the phase advances out from under it.
private struct ReviewingTestView: View {
    @EnvironmentObject var appState: AppState
    let pendingTest: String
    @State private var isExpanded = false
    @State private var baselineReasoningCount = 0

    private var newReasoningLines: [String] {
        guard let log = appState.session?.reasoningLog, log.count > baselineReasoningCount else { return [] }
        return Array(log.suffix(log.count - baselineReasoningCount))
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("AI requested: \(pendingTest) test")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView("Reviewing your result...")

            AIReasoningDropdown(lines: newReasoningLines, isExpanded: $isExpanded)
        }
        .padding()
        .onAppear {
            baselineReasoningCount = appState.session?.reasoningLog.count ?? 0
        }
    }
}

/// Collapsed by default; tapping reveals `lines`, or a placeholder while
/// the AI is still working (i.e. `lines` is still empty).
private struct AIReasoningDropdown: View {
    let lines: [String]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "brain")
                    Text("AI reasoning")
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                if lines.isEmpty {
                    Text("Analyzing your result…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(lines, id: \.self) { line in
                            Text("• \(line)").font(.footnote)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
        .padding(.horizontal)
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
