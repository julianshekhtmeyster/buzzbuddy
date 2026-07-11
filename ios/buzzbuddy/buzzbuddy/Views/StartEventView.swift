import SwiftUI

struct StartEventView: View {
    @EnvironmentObject var appState: AppState
    @State private var eventName = "Tonight"

    var body: some View {
        VStack(spacing: 16) {
            Text("Baseline set. Ready to start your event?")
                .font(.title3)
                .multilineTextAlignment(.center)

            TextField("Event name", text: $eventName)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            Button(appState.isLoading ? "Starting..." : "Start Event") {
                Task { await appState.startEvent(name: eventName) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isLoading)

            if let error = appState.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
    }
}

#Preview {
    StartEventView().environmentObject(AppState())
}
