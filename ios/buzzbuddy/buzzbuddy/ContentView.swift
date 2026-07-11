//
//  ContentView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.phase == .onboarding {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .task { await appState.bootstrap() }
    }
}

#Preview {
    ContentView().environmentObject(AppState())
}
