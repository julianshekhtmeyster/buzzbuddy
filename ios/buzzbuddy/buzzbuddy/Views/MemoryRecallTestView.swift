import SwiftUI

/// Shows short digit sequences and reports positional recall accuracy from
/// zero to one hundred percent.
struct MemoryRecallTestView: View {
    var onComplete: (Double) -> Void

    private enum Stage {
        case instructions
        case showing
        case distractor
        case entering
        case complete(Double)
    }

    @State private var stage: Stage = .instructions
    @State private var totalRounds = TestEngine.Memory.roundRange.lowerBound
    @State private var expectedSequences: [String] = []
    @State private var enteredSequences: [String] = []
    @State private var currentSequence = ""
    @State private var entry = ""
    @State private var transitionTask: Task<Void, Never>?
    @FocusState private var entryFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Text(progressText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            switch stage {
            case .instructions:
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                Text("Memory Recall")
                    .font(.title2.bold())
                Text("Memorize each number. It will disappear, then you’ll enter it from memory.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Start Memory Test") { beginTest() }
                    .buttonStyle(.borderedProminent)

            case .showing:
                Text("Memorize this number")
                    .font(.title3)
                Text(currentSequence)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .tracking(8)
                    .monospacedDigit()

            case .distractor:
                ProgressView()
                    .controlSize(.large)
                Text("Keep it in mind...")
                    .font(.title3)

            case .entering:
                Text("Enter the number")
                    .font(.title3)
                TextField("Digits", text: $entry)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($entryFocused)
                    .onChange(of: entry) { _, newValue in
                        entry = String(newValue.filter(\.isNumber).prefix(currentSequence.count))
                    }
                Button(enteredSequences.count + 1 == totalRounds ? "Finish" : "Next Round") {
                    submitRound()
                }
                .buttonStyle(.borderedProminent)
                .disabled(entry.count != currentSequence.count)

            case .complete(let accuracy):
                Text("Memory accuracy")
                    .font(.title2)
                Text("\(Int(accuracy.rounded()))%")
                    .font(.system(size: 52, weight: .bold))
                Button("Continue") { onComplete(accuracy) }
                    .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
        .onDisappear { transitionTask?.cancel() }
    }

    private var progressText: String {
        switch stage {
        case .instructions:
            return "2–3 short rounds"
        case .complete:
            return "Completed \(totalRounds) rounds"
        default:
            return "Round \(enteredSequences.count + 1) of \(totalRounds)"
        }
    }

    private func beginTest() {
        totalRounds = Int.random(in: TestEngine.Memory.roundRange)
        expectedSequences = []
        enteredSequences = []
        beginRound()
    }

    private func beginRound() {
        entry = ""
        entryFocused = false
        currentSequence = TestEngine.Memory.makeSequence(
            length: Int.random(in: TestEngine.Memory.digitRange)
        )
        expectedSequences.append(currentSequence)
        stage = .showing

        transitionTask?.cancel()
        transitionTask = Task {
            try? await Task.sleep(for: .seconds(TestEngine.Memory.displayDuration))
            guard !Task.isCancelled else { return }
            stage = .distractor
            try? await Task.sleep(for: .seconds(TestEngine.Memory.distractorDuration))
            guard !Task.isCancelled else { return }
            stage = .entering
            entryFocused = true
        }
    }

    private func submitRound() {
        guard entry.count == currentSequence.count else { return }
        enteredSequences.append(entry)
        entryFocused = false

        if enteredSequences.count < totalRounds {
            beginRound()
        } else if let accuracy = TestEngine.Memory.accuracyPercentage(
            expected: expectedSequences,
            entered: enteredSequences
        ) {
            stage = .complete(accuracy)
        }
    }
}

#Preview {
    MemoryRecallTestView { _ in }
}
