import SwiftUI

struct VerdictView: View {
    @EnvironmentObject var appState: AppState
    @State private var showMessageComposer = false
    @State private var composeOutcome: MessageComposeOutcome?

    var body: some View {
        VStack(spacing: 16) {
            if let session = appState.session {
                Text(title(for: session.status))
                    .font(.largeTitle.bold())

                Text("Confidence: \(Int(session.confidence * 100))%")
                    .font(.headline)

                if session.notificationStatus != nil || session.notified {
                    notificationStatus(session)

                    if shouldPollNotificationStatus(session) {
                        Button("Refresh alert status") {
                            Task { await appState.refreshSession() }
                        }
                        .font(.caption)
                    }
                }

                if session.status == "SEVERELY_IMPAIRED",
                   let contact = session.selectedContact ?? appState.selectedContact {
                    VStack(spacing: 10) {
                        Text("Contact \(contact.name) now")
                            .font(.headline)

                        Text("BuzzBuddy prepared a safety message. You will review it and press Send from Messages or another app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if contact.smsFallbackEnabled,
                           canRequestServerFallback(session) {
                            Button {
                                Task { await appState.requestServerSMSFallback() }
                            } label: {
                                Label("Send consented SMS fallback", systemImage: "message.badge")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.isLoading)
                        }

                        if contact.phoneNumber != nil,
                           MessageComposerView.canSendText {
                            Button {
                                showMessageComposer = true
                            } label: {
                                Label("Text \(contact.name) yourself", systemImage: "message.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        ShareLink(item: fallbackMessage) {
                            Label(
                                contact.phoneNumber != nil && MessageComposerView.canSendText
                                    ? "Share another way"
                                    : "Share safety alert",
                                systemImage: "square.and.arrow.up"
                            )
                        }

                        if let composeOutcome {
                            Text(composeOutcome.message)
                                .font(.caption)
                                .foregroundStyle(composeOutcome == .failed ? .red : .secondary)
                        }
                    }
                    .sheet(isPresented: $showMessageComposer) {
                        if let phone = contact.phoneNumber {
                            MessageComposerView(recipients: [phone], body: fallbackMessage) { outcome in
                                composeOutcome = outcome
                                showMessageComposer = false
                            }
                        }
                    }
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
        .task(id: appState.session?.notificationStatus) {
            while let session = appState.session,
                  shouldPollNotificationStatus(session),
                  !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                await appState.refreshSession()
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

    @ViewBuilder
    private func notificationStatus(_ session: SessionOut) -> some View {
        let status = session.notificationStatus?.lowercased()
            ?? (session.notified ? "accepted" : "not_requested")

        switch status {
        case "acknowledged":
            Label("Your contact confirmed they are responding.", systemImage: "checkmark.message.fill")
                .foregroundStyle(.green)
        case "delivered":
            Label("The provider reports delivery. Your contact has not responded yet.", systemImage: "checkmark.circle")
                .foregroundStyle(.orange)
        case "accepted", "queued", "sent", "sending", "pending":
            Label("The alert was accepted for sending. Delivery is not confirmed.", systemImage: "paperplane.circle")
                .foregroundStyle(.orange)
        case "ambiguous":
            Label("Push delivery is unknown. You can request the consented SMS fallback below.", systemImage: "questionmark.circle.fill")
                .foregroundStyle(.orange)
        case "failed", "undelivered", "not_configured", "invalid_contact", "consent_required", "contact_required":
            Label("Automatic delivery is unavailable. Send the prepared message below.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case "threshold_not_met":
            Label("No automatic alert was sent because the escalation threshold was not met.", systemImage: "bell.slash")
                .foregroundStyle(.secondary)
        default:
            Label("Automatic alert status: \(status.replacingOccurrences(of: "_", with: " "))", systemImage: "bell")
                .foregroundStyle(.secondary)
        }
    }

    private var fallbackMessage: String {
        SafetyFallbackMessage.make(
            ownerName: appState.ownerName,
            locationURL: appState.latestLocationURL
        )
    }

    private func shouldPollNotificationStatus(_ session: SessionOut) -> Bool {
        guard session.notificationAttemptId != nil || session.notified else { return false }
        switch session.notificationStatus?.lowercased() ?? "accepted" {
        case "accepted", "queued", "sent", "sending", "pending", "delivered":
            return true
        default:
            return false
        }
    }

    private func canRequestServerFallback(_ session: SessionOut) -> Bool {
        switch session.notificationStatus?.lowercased() {
        case "ambiguous", "failed", "undelivered": return true
        default: return false
        }
    }
}

#Preview {
    VerdictView().environmentObject(AppState())
}
