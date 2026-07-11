//
//  HomeView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct HomeView: View {

    
    @EnvironmentObject var engine: TestEngine
    @State var showingTest = false

    var body: some View {
        NavigationStack {
            VStack {
                Button("Start Test") {
                    showingTest = true
                    engine.startTest()
                }
            }
            .fullScreenCover(isPresented: $showingTest) {
                TestSessionView()
                    
            }
            .onChange(of: engine.finished){
                print("yahdsgrefh")

                if (engine.finished){
                    showingTest = false
                    print("yahdsgrefh")
                }
            }
            
        }
        .navigationTitle("Home")
    }
}


