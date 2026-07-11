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
        // Onboarding is handled inside SafetyCheckFlowView (reached via the
        // Check-In tab's Start Test button), not as a full-app gate here --
        // every tab should stay reachable regardless of onboarding status.
        MainTabView()
            .task { await appState.bootstrap() }
    }
}

#Preview {
    ContentView().environmentObject(AppState())
}
