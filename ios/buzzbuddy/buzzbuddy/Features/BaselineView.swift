//
//  BaselineView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/11/26.
//


import SwiftUI

struct BaselineView: View {
    
    @EnvironmentObject var engine: TestEngine

    
    var body: some View {
        NavigationStack {
            VStack {
                Button("Update Baseline") {
                    engine.startTest()
                }
            }

        }
    }
}

#Preview {
    BaselineView()
}
