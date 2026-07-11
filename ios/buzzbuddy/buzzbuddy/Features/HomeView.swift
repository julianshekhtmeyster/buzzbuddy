//
//  HomeView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct HomeView: View {
    
    @ObservedObject var engine:TestEngine
    @State private var showingTest = false

    
    var body: some View {
        
        NavigationStack {
            VStack {
                Button("Start Game"){
                    engine.startTest()
                    showingTest = true
                }
            }
            .navigationTitle("Home")
        }.fullScreenCover(isPresented: $showingTest) {
            TestSessionView()
                .environmentObject(engine)
        }
    }
}


