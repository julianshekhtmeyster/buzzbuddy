//
//  SettingsView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Text("Settings")
                .font(.largeTitle)
                .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
