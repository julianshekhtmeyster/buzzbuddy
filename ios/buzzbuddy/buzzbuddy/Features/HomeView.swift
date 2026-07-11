//
//  HomeView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct HomeView: View {
    @State private var showingTest = false

    var body: some View {
        NavigationStack {
            VStack {
                Button("Start Check-In") {
                    showingTest = true
                }
            }
            .navigationTitle("Home")
        }
        .fullScreenCover(isPresented: $showingTest) {
            SafetyCheckFlowView()
        }
    }
}

#Preview {
    HomeView()
}
