//
//  HomeView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            SafetyCheckFlowView()
                .navigationTitle("BuzzBuddy")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    HomeView().environmentObject(AppState())
}
