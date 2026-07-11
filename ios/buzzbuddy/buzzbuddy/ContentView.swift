//
//  ContentView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var pushNotifications: PushNotificationManager

    var body: some View {
        Group {
            switch appState.phase {
            case .onboarding:
                OnboardingView()
            case .baselineUpgrade:
                BaselineUpgradeView()
            default:
                MainTabView()
            }
        }
            .task { await appState.bootstrap() }
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
