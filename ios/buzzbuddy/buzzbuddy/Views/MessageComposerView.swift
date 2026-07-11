import MessageUI
import SwiftUI

enum SafetyFallbackMessage {
    static func make(ownerName: String?, locationURL: String?) -> String {
        let owner = ownerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = owner.flatMap { $0.isEmpty ? nil : $0 } ?? "Your BuzzBuddy friend"
        var message = "BuzzBuddy safety alert: \(displayName) may need help arranging a safe ride. Please contact them now."
        if let locationURL, !locationURL.isEmpty {
            message += " Last shared location: \(locationURL)"
        }
        return message
    }
}

enum MessageComposeOutcome: Equatable {
    case sent
    case cancelled
    case failed

    var message: String {
        switch self {
        case .sent:
            return "The message was sent from this device. Delivery is not confirmed."
        case .cancelled:
            return "Message cancelled."
        case .failed:
            return "Messages could not send the alert. Try sharing it another way."
        }
    }
}

struct MessageComposerView: UIViewControllerRepresentable {
    var recipients: [String]
    var body: String
    var onFinish: (MessageComposeOutcome) -> Void

    static var canSendText: Bool {
        MFMessageComposeViewController.canSendText()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = context.coordinator
        composer.recipients = recipients
        composer.body = body
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let parent: MessageComposerView

        init(parent: MessageComposerView) {
            self.parent = parent
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            let outcome: MessageComposeOutcome
            switch result {
            case .sent: outcome = .sent
            case .cancelled: outcome = .cancelled
            case .failed: outcome = .failed
            @unknown default: outcome = .failed
            }
            controller.dismiss(animated: true)
            parent.onFinish(outcome)
        }
    }
}
