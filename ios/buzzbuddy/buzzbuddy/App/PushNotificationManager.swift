import Combine
import Foundation
import UIKit
import UserNotifications

struct IncomingPushAlert: Identifiable, Equatable {
    var id: String { attemptId }
    var attemptId: String
    var contactId: String?
    var title: String
    var message: String
}

struct PushResponseAction: Identifiable, Equatable, Codable {
    var id: String { "\(attemptId):\(response)" }
    var attemptId: String
    var contactId: String?
    var response: String
}

@MainActor
final class PushNotificationManager: ObservableObject {
    static let shared = PushNotificationManager()
    static let categoryIdentifier = "BUZZBUDDY_SAFETY_ALERT"
    static let respondingActionIdentifier = "BUZZBUDDY_RESPONDING"

    @Published private(set) var deviceToken: String?
    @Published private(set) var authorizationStatus = "not_requested"
    @Published var activeAlert: IncomingPushAlert?
    @Published var pendingResponseAction: PushResponseAction?
    @Published var errorMessage: String?
    private let pendingResponseKey = "buzzbuddy.pendingPushResponseAction"

    var environment: String {
#if DEBUG
        return "sandbox"
#else
        return "production"
#endif
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: pendingResponseKey) {
            pendingResponseAction = try? JSONDecoder().decode(PushResponseAction.self, from: data)
        }
    }

    func prepare() async {
        registerNotificationCategories()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        updateAuthorizationStatus(settings.authorizationStatus)
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func requestAuthorizationAndRegister() async {
        registerNotificationCategories()
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            authorizationStatus = granted ? "authorized" : "denied"
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
                errorMessage = nil
            } else {
                errorMessage = "Notifications are off. Enable them in Settings so safety alerts can reach you."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func didRegister(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        errorMessage = nil
    }

    func didFailToRegister(error: Error) {
        errorMessage = "Push registration failed: \(error.localizedDescription)"
    }

    func receive(userInfo: [AnyHashable: Any], openedByUser: Bool) {
        guard let alert = Self.alert(from: userInfo) else { return }
        if openedByUser {
            // Opening a notification is intentionally not an acknowledgement.
            activeAlert = alert
        }
    }

    func receiveExplicitResponse(userInfo: [AnyHashable: Any]) {
        guard let alert = Self.alert(from: userInfo) else { return }
        pendingResponseAction = PushResponseAction(
            attemptId: alert.attemptId,
            contactId: alert.contactId,
            response: "responding"
        )
        persistPendingResponse()
    }

    func clearPendingResponse(_ action: PushResponseAction) {
        if pendingResponseAction == action {
            pendingResponseAction = nil
            UserDefaults.standard.removeObject(forKey: pendingResponseKey)
        }
    }

    private func persistPendingResponse() {
        guard let pendingResponseAction,
              let data = try? JSONEncoder().encode(pendingResponseAction) else { return }
        UserDefaults.standard.set(data, forKey: pendingResponseKey)
    }

    private func registerNotificationCategories() {
        let responding = UNNotificationAction(
            identifier: Self.respondingActionIdentifier,
            title: "I'm responding",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [responding],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func updateAuthorizationStatus(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: authorizationStatus = "not_requested"
        case .denied: authorizationStatus = "denied"
        case .authorized: authorizationStatus = "authorized"
        case .provisional: authorizationStatus = "provisional"
        case .ephemeral: authorizationStatus = "ephemeral"
        @unknown default: authorizationStatus = "unknown"
        }
    }

    private static func alert(from userInfo: [AnyHashable: Any]) -> IncomingPushAlert? {
        let attemptId = (userInfo["attempt_id"] ?? userInfo["notification_attempt_id"]) as? String
        guard let attemptId, !attemptId.isEmpty else { return nil }

        let contactId = userInfo["contact_id"] as? String
        var title = "BuzzBuddy safety alert"
        var message = userInfo["message"] as? String ?? "Your friend may need help getting home safely."
        if let aps = userInfo["aps"] as? [String: Any] {
            if let alert = aps["alert"] as? String {
                message = alert
            } else if let alert = aps["alert"] as? [String: Any] {
                title = alert["title"] as? String ?? title
                message = alert["body"] as? String ?? message
            }
        }

        return IncomingPushAlert(
            attemptId: attemptId,
            contactId: contactId,
            title: title,
            message: message
        )
    }
}

final class BuzzBuddyAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushNotificationManager.shared.didRegister(deviceToken: deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            PushNotificationManager.shared.didFailToRegister(error: error)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.receive(userInfo: userInfo, openedByUser: false)
            completionHandler(.newData)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.receive(
                userInfo: notification.request.content.userInfo,
                openedByUser: false
            )
            completionHandler([.banner, .sound, .badge])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            let manager = PushNotificationManager.shared
            if response.actionIdentifier == PushNotificationManager.respondingActionIdentifier {
                manager.receiveExplicitResponse(userInfo: response.notification.request.content.userInfo)
            } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                manager.receive(
                    userInfo: response.notification.request.content.userInfo,
                    openedByUser: true
                )
            }
            completionHandler()
        }
    }
}
