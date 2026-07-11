import SwiftUI

struct StartEventView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var eventName = "Tonight"

    /// The backend rejects event creation with no baseline on file (there's
    /// nothing to detect deviation from) -- check client-side first so the
    /// user gets a helpful nudge instead of a raw error string.
    private var hasBaseline: Bool {
        appState.reactionBaselineMs != nil
            && appState.gyroBaselineScore != nil
            && appState.memoryBaselinePercent != nil
    }

    var body: some View {
        VStack(spacing: 16) {
            if hasBaseline {
                Text("Baseline set. Ready to start your event?")
                    .font(.title3)
                    .multilineTextAlignment(.center)

                TextField("Event name", text: $eventName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                Button(appState.isLoading ? "Starting..." : "Start my night") {
                    Task { await appState.startEvent(name: eventName) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isLoading)

                if let error = appState.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            } else {
                Text("Set your sober baseline before starting a check-in.")
                    .font(.title3)
                    .multilineTextAlignment(.center)

                Text("The examiner compares your test results against your own baseline -- without one, it has nothing to compare to.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Baseline setup lives on the Baseline tab underneath this
                // full-screen check-in flow, not as a nested page here --
                // pushing a second BaselineView instance inside this modal
                // just duplicates that one true page and confuses navigation.
                Button("Go to the Baseline tab") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

#Preview {
    StartEventView().environmentObject(AppState())
}
