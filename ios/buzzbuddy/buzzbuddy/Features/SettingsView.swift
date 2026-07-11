import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var trustedContacts: TrustedContactStore
    @EnvironmentObject private var pushNotifications: PushNotificationManager

    @State private var inviteCode = ""
    @State private var smsConsent = false
    @State private var confirmedPhoneNumber = ""
    @State private var contactToReissue: DDContactOut?

    var body: some View {
        NavigationStack {
            Form {
                ownerContactsSection
                trustedContactSection
                alertInboxSection

                if let error = appState.errorMessage
                    ?? trustedContacts.errorMessage
                    ?? pushNotifications.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Safety Contacts")
            .refreshable {
                async let ownerRefresh: Void = appState.refreshContacts()
                async let inboxRefresh: Void = trustedContacts.refreshNotifications()
                _ = await (ownerRefresh, inboxRefresh)
            }
            .task {
                await trustedContacts.refreshNotifications()
            }
            .confirmationDialog(
                "Replace this trusted-contact invite?",
                isPresented: Binding(
                    get: { contactToReissue != nil },
                    set: { if !$0 { contactToReissue = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Replace invite and revoke old access", role: .destructive) {
                    guard let contact = contactToReissue else { return }
                    Task { await appState.reissueInvite(contactId: contact.id) }
                    contactToReissue = nil
                }
                Button("Cancel", role: .cancel) { contactToReissue = nil }
            } message: {
                Text("The old invite, contact credential, and registered push devices will stop working.")
            }
        }
    }

    @ViewBuilder
    private var ownerContactsSection: some View {
        if appState.ownerUserId != nil {
            Section("Who BuzzBuddy alerts for you") {
                if appState.contacts.isEmpty {
                    Text("No safety contact is available yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(appState.contacts) { contact in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name).font(.headline)
                                if let phone = contact.phoneNumber {
                                    Text(phone).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            ContactReadinessLabel(contact: contact)
                        }

                        if let code = contact.inviteCode {
                            HStack {
                                Text("Invite code")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(code)
                                    .font(.system(.body, design: .monospaced).bold())
                                    .textSelection(.enabled)
                            }
                            ShareLink(item: inviteMessage(contact: contact, code: code)) {
                                Label("Share trusted-contact invite", systemImage: "square.and.arrow.up")
                            }
                        }

                        Button(contact.isAccepted ? "Replace invite and revoke access" : "Generate a new invite") {
                            contactToReissue = contact
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var trustedContactSection: some View {
        Section("Receive alerts for a friend") {
            HStack {
                Label("Push alerts", systemImage: "bell.badge")
                Spacer()
                Text(pushStatusTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if pushNotifications.authorizationStatus != "authorized"
                && pushNotifications.authorizationStatus != "provisional" {
                Button("Enable safety alerts") {
                    Task { await pushNotifications.requestAuthorizationAndRegister() }
                }
            }

            TextField("Invite code", text: $inviteCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Text("By accepting, you agree to receive urgent BuzzBuddy safety alerts by push notification.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Allow SMS fallback", isOn: $smsConsent)
            if smsConsent {
                TextField("Confirm your phone number", text: $confirmedPhoneNumber)
                    .keyboardType(.phonePad)
                Text("BuzzBuddy will use this number only if push definitively fails or you explicitly request fallback. Message and data rates may apply; reply STOP to opt out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(trustedContacts.isLoading ? "Accepting…" : "Accept invite") {
                Task {
                    await pushNotifications.requestAuthorizationAndRegister()
                    await trustedContacts.acceptInvite(
                        code: inviteCode,
                        deviceToken: pushNotifications.deviceToken,
                        environment: pushNotifications.environment,
                        smsConsent: smsConsent,
                        confirmedPhoneNumber: smsConsent ? confirmedPhoneNumber : nil
                    )
                    if trustedContacts.errorMessage == nil {
                        inviteCode = ""
                        smsConsent = false
                        confirmedPhoneNumber = ""
                    }
                }
            }
            .disabled(
                inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || trustedContacts.isLoading
                    || (smsConsent
                        && confirmedPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )

            ForEach(trustedContacts.acceptedContacts) { contact in
                Label {
                    VStack(alignment: .leading) {
                        Text(contact.name)
                        Text(contact.hasRegisteredDevice ? "This device is registered" : "Waiting for push registration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if contact.smsFallbackEnabled {
                            Text("SMS fallback enabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: contact.hasRegisteredDevice ? "checkmark.shield.fill" : "shield")
                        .foregroundStyle(contact.hasRegisteredDevice ? .green : .secondary)
                }
            }
        }
    }

    private var alertInboxSection: some View {
        Section("Safety alerts") {
            if trustedContacts.allNotifications.isEmpty {
                Text("Alerts you receive will appear here. Opening one does not tell your friend you are responding.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(trustedContacts.allNotifications) { attempt in
                NavigationLink {
                    TrustedAlertDetailView(attempt: attempt)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(attempt.message)
                            .lineLimit(2)
                        Text(attempt.isAcknowledged ? "Response sent" : "Response needed")
                            .font(.caption)
                            .foregroundStyle(attempt.isAcknowledged ? .green : .orange)
                    }
                }
            }
        }
    }

    private var pushStatusTitle: String {
        switch pushNotifications.authorizationStatus {
        case "authorized": return "Enabled"
        case "provisional": return "Quietly enabled"
        case "denied": return "Disabled"
        default: return "Not enabled"
        }
    }

    private func inviteMessage(contact: DDContactOut, code: String) -> String {
        let owner = appState.ownerName ?? "A friend"
        return "\(owner) invited you to be their BuzzBuddy trusted contact. Install BuzzBuddy, open Safety Contacts, and enter invite code \(code)."
    }
}

private struct ContactReadinessLabel: View {
    var contact: DDContactOut

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Label(contact.isAccepted ? "Accepted" : "Invite pending", systemImage: contact.isAccepted ? "checkmark.circle.fill" : "clock")
            if contact.isAccepted {
                Text(contact.hasRegisteredDevice ? "Push ready" : "No device yet")
                if contact.smsFallbackEnabled {
                    Text("SMS allowed")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(contact.hasRegisteredDevice ? .green : .secondary)
    }
}

struct TrustedAlertDetailView: View {
    @EnvironmentObject private var trustedContacts: TrustedContactStore
    let attempt: NotificationAttemptOut

    @State private var isResponding = false

    private var currentAttempt: NotificationAttemptOut {
        trustedContacts.allNotifications.first(where: { $0.id == attempt.id }) ?? attempt
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("BuzzBuddy safety alert", systemImage: "exclamationmark.shield.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)

                Text(currentAttempt.message)
                    .font(.body)

                if let location = currentAttempt.locationUrl,
                   let url = URL(string: location) {
                    Link(destination: url) {
                        Label("Open shared location", systemImage: "map")
                    }
                    .buttonStyle(.bordered)
                }

                if currentAttempt.isAcknowledged {
                    Label("You told them: \(responseTitle(currentAttempt.acknowledgementResponse))", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Opening this alert does not send a response. Choose an action only if you intend to help.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    responseButton("I'm responding", response: "responding", systemImage: "figure.wave")
                    responseButton("I'll call them now", response: "calling", systemImage: "phone.fill")
                }

                if let error = trustedContacts.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Safety Alert")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func responseButton(_ title: String, response: String, systemImage: String) -> some View {
        Button {
            isResponding = true
            Task {
                _ = await trustedContacts.acknowledge(
                    attemptId: currentAttempt.id,
                    contactId: currentAttempt.contactId,
                    response: response
                )
                isResponding = false
            }
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isResponding)
    }

    private func responseTitle(_ response: String?) -> String {
        switch response {
        case "responding": return "I'm responding"
        case "calling": return "I'll call now"
        default: return response ?? "Acknowledged"
        }
    }
}

struct IncomingSafetyAlertView: View {
    @EnvironmentObject private var trustedContacts: TrustedContactStore
    @Environment(\.dismiss) private var dismiss
    let alert: IncomingPushAlert

    @State private var isResponding = false
    @State private var responseSent = false

    private var inboxAttempt: NotificationAttemptOut? {
        trustedContacts.allNotifications.first(where: { $0.id == alert.attemptId })
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Label(alert.title, systemImage: "exclamationmark.shield.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
                Text(inboxAttempt?.message ?? alert.message)
                if let location = inboxAttempt?.locationUrl,
                   let url = URL(string: location) {
                    Link(destination: url) {
                        Label("Open shared location", systemImage: "map")
                    }
                    .buttonStyle(.bordered)
                }
                Text("Opening this alert did not notify your friend. Tap below only if you are responding.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if responseSent {
                    Label("Your response was recorded.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        isResponding = true
                        Task {
                            responseSent = await trustedContacts.acknowledge(
                                attemptId: alert.attemptId,
                                contactId: alert.contactId,
                                response: "responding"
                            )
                            isResponding = false
                        }
                    } label: {
                        Label("I'm responding", systemImage: "figure.wave")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isResponding)
                }

                if let error = trustedContacts.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Safety Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(responseSent ? "Done" : "Not now") { dismiss() }
                }
            }
        }
        .task {
            await trustedContacts.refreshNotifications()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(TrustedContactStore())
        .environmentObject(PushNotificationManager.shared)
}
