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
            NeedsProfileView()
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

/// Human-readable name for a `pendingTest`/`test_type` string, used on the
/// Continue button so it says what's coming up next instead of just "Continue".
private func testDisplayName(_ pendingTest: String) -> String {
    switch TestKind(pendingTest: pendingTest) {
    case .reaction: return "Reaction Test"
    case .balance: return "Balance Test"
    case .memory: return "Memory Test"
    case .gait: return "Walking Test"
    case .unknown: return "Next Test"
    }
}

/// Shown while `submitTestResult` is in flight and after it resolves. Once
/// the result is in, this deliberately does NOT auto-advance -- it reveals
/// the AI's reasoning for this round word by word and waits for the user to
/// tap the bottom button (AppState.continueAfterReview()) before moving to
/// the next test or the verdict.
private struct ReviewingTestView: View {
    @EnvironmentObject var appState: AppState
    let pendingTest: String
    @State private var baselineReasoningCount = 0
    @State private var revealFinished = false

    private var newReasoningLines: [String] {
        guard let log = appState.session?.reasoningLog, log.count > baselineReasoningCount else { return [] }
        return Array(log.suffix(log.count - baselineReasoningCount))
    }

    private var nextStepLabel: String {
        guard let nextTest = appState.session?.pendingTest else { return "See Your Results" }
        return "Continue to \(testDisplayName(nextTest))"
    }

    var body: some View {
        VStack(spacing: 12) {
            if appState.isLoading {
                Spacer()
                ProgressView("Reviewing your result...")
                Spacer()
            } else {
                AIReasoningText(
                    lines: newReasoningLines,
                    onRevealFinished: { revealFinished = true }
                )
                .padding(.horizontal)
                .padding(.top)

                if !revealFinished {
                    Spacer()
                }

                if revealFinished {
                    Button {
                        appState.continueAfterReview()
                    } label: {
                        Text(nextStepLabel)
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
        .onAppear {
            baselineReasoningCount = appState.session?.reasoningLog.count ?? 0
        }
    }
}

/// Reveals `lines` word by word as they arrive (simulating the AI "thinking"
/// live, even though the backend actually returns the full text in one
/// shot), filling the space top to bottom with no background, icon, or
/// label -- just the reasoning itself, at a single consistent size. Fully
/// revealed lines stay visible. Calls `onRevealFinished` once every line
/// has finished animating in.
private struct AIReasoningText: View {
    let lines: [String]
    var onRevealFinished: () -> Void

    @State private var revealedLineCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if lines.isEmpty {
                Text("Analyzing your result…")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    if index < revealedLineCount {
                        Text(line)
                    } else if index == revealedLineCount {
                        TypewriterLine(text: line) {
                            revealedLineCount += 1
                            if revealedLineCount == lines.count {
                                onRevealFinished()
                            }
                        }
                    }
                }
            }
        }
        .font(.body)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if lines.isEmpty { onRevealFinished() }
        }
    }
}

/// Reveals `text` a word at a time, then calls `onFinished` once the whole
/// line is visible.
private struct TypewriterLine: View {
    let text: String
    var onFinished: () -> Void

    @State private var visibleWordCount = 0

    private var words: [String] { text.split(separator: " ").map(String.init) }

    var body: some View {
        Text(words.prefix(visibleWordCount).joined(separator: " "))
            .onAppear { revealNext() }
    }

    private func revealNext() {
        guard visibleWordCount < words.count else {
            onFinished()
            return
        }
        visibleWordCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            revealNext()
        }
    }
}

/// Profile setup (name/weight/height/DD contact) lives on the Baseline tab
/// alongside sober test capture -- one page, not a form embedded here.
private struct NeedsProfileView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text("Set up your profile before starting a check-in.")
                .font(.title3)
                .multilineTextAlignment(.center)
            Text("Your name, weight, height, and designated driver contact live on the Baseline tab, alongside your sober test results.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Go to the Baseline tab") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
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
