//
//  SettingsView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var settings: AppSettings

    var body: some View {
        NavigationStack {
            Form {

                Section("Safety") {
                    Toggle(
                        "Automatically Call Emergency Contact",
                        isOn: $settings.enableAutoCallContact
                    )

                    Toggle(
                        "Sound Effects",
                        isOn: $settings.soundEffects
                    )
                }

                Section("Biometrics") {
                    Stepper(
                        "Weight: \(settings.weight) kg",
                        value: $settings.weight,
                        in: 30...250
                    )

                    Stepper(
                        "Height: \(settings.height) cm",
                        value: $settings.height,
                        in: 100...250
                    )
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
}
