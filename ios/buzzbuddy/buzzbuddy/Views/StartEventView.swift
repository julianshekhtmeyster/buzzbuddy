import SwiftUI

struct StartEventView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var eventStore = EventStore.shared
    @State private var selectedEvent: Event?

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
                Text("What event are you at right now?")
                    .font(.title3)
                    .multilineTextAlignment(.center)

                if eventStore.events.isEmpty {
                    Text("Add an event on the Events tab first.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Go to the Events tab") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Picker("Event", selection: $selectedEvent) {
                        Text("Select an event").tag(Event?.none)
                        ForEach(eventStore.events) { event in
                            Text(event.name).tag(Optional(event))
                        }
                    }
                    .pickerStyle(.menu)
                    .buttonStyle(.bordered)

                    Button(appState.isLoading ? "Starting..." : "Go") {
                        guard let selectedEvent else { return }
                        Task { await appState.startEvent(name: selectedEvent.name) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(appState.isLoading || selectedEvent == nil)

                    if let error = appState.errorMessage {
                        Text(error).foregroundStyle(.red)
                    }
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
