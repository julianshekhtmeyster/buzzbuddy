//
//  RideView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct RideView: View {
    var body: some View {
        NavigationStack {
            Text("Ride Home")
                .font(.largeTitle)
                .navigationTitle("Ride Home")
        }
    }
}

#Preview {
    RideView()
}
