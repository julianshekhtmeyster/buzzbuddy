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

            if appState.contacts.isEmpty {
                Text("Add a safety contact before starting an event.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else {
                Picker("Alert this contact", selection: $appState.selectedContactId) {
                    ForEach(appState.contacts) { contact in
                        Text(contact.name).tag(Optional(contact.id))
                    }
                }
                .pickerStyle(.menu)

                if let contact = appState.selectedContact {
                    Label(
                        readinessText(contact),
                        systemImage: contact.hasRegisteredDevice
                            ? "bell.badge.fill"
                            : (contact.smsFallbackEnabled ? "message" : "clock")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Button(appState.isLoading ? "Starting..." : "Start Event") {
                Task { await appState.startEvent(name: eventName.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isLoading || appState.selectedContactId == nil || eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let error = appState.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .task { await appState.refreshContacts() }
    }

    private func readinessText(_ contact: DDContactOut) -> String {
        if contact.hasRegisteredDevice { return "Automatic push alerts ready" }
        if contact.smsFallbackEnabled { return "Consented SMS fallback available" }
        if contact.isAccepted { return "Accepted; waiting for push registration" }
        return "Invite acceptance required before automatic alerts"
    }
}

#Preview {
    StartEventView().environmentObject(AppState())
}
