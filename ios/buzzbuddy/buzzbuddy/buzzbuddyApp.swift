//
//  buzzbuddyApp.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

@main
struct BuzzBuddyApp: App {
    @UIApplicationDelegateAdaptor(BuzzBuddyAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var trustedContacts = TrustedContactStore()
    @StateObject private var pushNotifications = PushNotificationManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(trustedContacts)
                .environmentObject(pushNotifications)
                .task {
                    await pushNotifications.prepare()
                    await appState.refreshContacts()
                    await trustedContacts.refreshNotifications()
                    if let token = pushNotifications.deviceToken {
                        await trustedContacts.registerDevices(
                            deviceToken: token,
                            environment: pushNotifications.environment
                        )
                    }
                }
                .onChange(of: pushNotifications.deviceToken) { _, token in
                    guard let token else { return }
                    Task {
                        await trustedContacts.registerDevices(
                            deviceToken: token,
                            environment: pushNotifications.environment
                        )
                    }
                }
                .task(id: pushNotifications.pendingResponseAction?.id) {
                    guard let action = pushNotifications.pendingResponseAction else { return }
                    while !Task.isCancelled,
                          pushNotifications.pendingResponseAction == action {
                        let acknowledged = await trustedContacts.acknowledge(
                            attemptId: action.attemptId,
                            contactId: action.contactId,
                            response: action.response
                        )
                        if acknowledged {
                            pushNotifications.clearPendingResponse(action)
                            return
                        }
                        try? await Task.sleep(nanoseconds: 10_000_000_000)
                    }
                }
        }
    }
}
