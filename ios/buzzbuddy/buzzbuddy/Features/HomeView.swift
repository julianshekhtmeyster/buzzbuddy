//
//  HomeView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct HomeView: View {

    
    @EnvironmentObject var engine: TestEngine

    var body: some View {
        NavigationStack {
            VStack {
                Button("Start Test") {
                    engine.startTest()
                }
            }

            
        }
        .navigationTitle("Home")
    }
}


