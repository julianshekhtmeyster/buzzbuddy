import SwiftUI

/// Shows a short digit sequence to memorize, then asks the user to tap it
/// back in order. Reports recall accuracy as a 0...100 percentage. Reused
/// both to capture the sober baseline and for each AI-requested test.
struct MemoryRecallTestView: View {
    var onComplete: (Double) -> Void

    private static let sequenceLength = 5
    private static let memorizeDuration: Double = 4.0

    private enum Stage {
        case memorize
        case recall
        case result(Double)
    }

    @State private var sequence: [Int] = []
    @State private var stage: Stage = .memorize
    @State private var input: [Int] = []
    @State private var timeRemaining: Double = MemoryRecallTestView.memorizeDuration
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 24) {
            switch stage {
            case .memorize:
                Text("Memorize this sequence")
                    .font(.title3)
                Text(sequence.map(String.init).joined(separator: " "))
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                ProgressView(value: Self.memorizeDuration - timeRemaining, total: Self.memorizeDuration)
                    .padding(.horizontal, 40)
            case .recall:
                Text("Tap the digits back in order")
                    .font(.title3)
                Text(input.map(String.init).joined(separator: " "))
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .frame(minHeight: 40)
                digitPad
                HStack {
                    Button("Clear") { input = [] }
                    Spacer()
                    Button("Submit") { finish() }
                        .buttonStyle(.borderedProminent)
                        .disabled(input.isEmpty)
                }
                .padding(.horizontal, 32)
            case .result(let accuracy):
                Text("\(Int(accuracy))% accurate")
                    .font(.system(size: 48, weight: .bold))
                Button("Continue") { onComplete(accuracy) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear { start() }
        .onDisappear { timer?.invalidate() }
    }

    private var digitPad: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
            ForEach(0..<10, id: \.self) { digit in
                Button {
                    input.append(digit)
                } label: {
                    Text("\(digit)")
                        .font(.title3.bold())
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(.blue.opacity(0.15)))
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private func start() {
        sequence = (0..<Self.sequenceLength).map { _ in Int.random(in: 0...9) }
        input = []
        stage = .memorize
        timeRemaining = Self.memorizeDuration
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            timeRemaining -= 0.1
            if timeRemaining <= 0 {
                timer?.invalidate()
                stage = .recall
            }
        }
    }

    private func finish() {
        let matches = zip(sequence, input).filter { $0 == $1 }.count
        let accuracy = (Double(matches) / Double(sequence.count)) * 100
        stage = .result(accuracy)
    }
}

#Preview {
    MemoryRecallTestView { _ in }
}
