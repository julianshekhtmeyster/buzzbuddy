//
//  EventsView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct EventsView: View {
    var body: some View {
        NavigationStack {
            
            
            Text("Events")
                .font(.largeTitle)
                .navigationTitle("Events")
        }
    }
}

#Preview {
    EventsView()
}
