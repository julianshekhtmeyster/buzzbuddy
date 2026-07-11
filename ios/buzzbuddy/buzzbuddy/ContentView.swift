//
//  ContentView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var pushNotifications: PushNotificationManager

    var body: some View {
        MainTabView()
            .sheet(item: $pushNotifications.activeAlert) { alert in
                IncomingSafetyAlertView(alert: alert)
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(TrustedContactStore())
        .environmentObject(PushNotificationManager.shared)
}
