import SwiftUI

struct VerdictView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showDDCompanionPreview = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let session = appState.session {
                    Text(title(for: session.status))
                        .font(.largeTitle.bold())

                    Text("Confidence: \(Int(session.confidence * 100))%")
                        .font(.headline)

                    if session.notified {
                        Text("Your designated driver has been notified.")
                            .foregroundStyle(.orange)

                        Button("Preview DD companion") {
                            showDDCompanionPreview = true
                        }
                        .buttonStyle(.bordered)
                    }

                    // The one compressed takeaway, featured front-and-center --
                    // distinct from the per-round trace below.
                    if let summary = session.finalSummary, !summary.isEmpty {
                        Text(summary)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    DisclosureGroup("Full reasoning") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(session.reasoningLog, id: \.self) { line in
                                Text("• \(line)").font(.footnote)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }
                    .font(.subheadline)

                    Text("BuzzBuddy does not estimate BAC and does not tell you whether it's legal for you to drive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    // fullScreenCover has no built-in dismiss (no swipe-down,
                    // no back button) -- without this, finishing a check-in
                    // leaves the user stuck here with no way back to the tabs.
                    Button {
                        appState.discardSession()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 8)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showDDCompanionPreview) {
            if let sessionId = appState.session?.id {
                DDCompanionPreviewView(sessionId: sessionId)
            }
        }
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
