import SwiftUI

struct VerdictView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            if let session = appState.session {
                Text(title(for: session.status))
                    .font(.largeTitle.bold())

                Text("Confidence: \(Int(session.confidence * 100))%")
                    .font(.headline)

                if session.notified {
                    Text("Your designated driver has been notified.")
                        .foregroundStyle(.orange)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(session.reasoningLog, id: \.self) { line in
                            Text("• \(line)").font(.footnote)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("BuzzBuddy does not estimate BAC and does not tell you whether it's legal for you to drive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private func title(for status: String) -> String {
        switch status {
        case "CLEAR": return "Clear"
        case "MILDLY_IMPAIRED": return "Mildly Impaired"
        case "SEVERELY_IMPAIRED": return "Severely Impaired"
        default: return status
        }
    }
}

#Preview {
    VerdictView().environmentObject(AppState())
}
