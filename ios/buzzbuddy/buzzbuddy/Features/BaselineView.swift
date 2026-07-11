//
//  BaselineView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/11/26.
//


import SwiftUI

struct BaselineView: View {
    var body: some View {
        NavigationStack {
            Text("baseline")
                .font(.largeTitle)
                .navigationTitle("baseline")
        }
    }
}

#Preview {
    BaselineView()
}
