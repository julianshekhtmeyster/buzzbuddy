//
//  HomeView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct HomeView: View {
    @State private var showingTest = false
    
    @EnvironmentObject var engine: TestEngine
    @State private var showingResults = false

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
                Button("Start Game"){
                    engine.startTest()
                    showingResults = true
                }
            }
            .navigationTitle("Home")
        }.fullScreenCover(isPresented: $showingResults) {
            TestSessionView()
        }
        }.onChange(of: engine.finished){
            if (engine.finished ){
                showingResults = false
            }
        }
    
}

#Preview {
    HomeView()
}
