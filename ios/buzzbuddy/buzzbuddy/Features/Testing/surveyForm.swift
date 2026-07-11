//
//  surveryForm.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct surveyForm: View {

    @State private var drankAlcohol = false
    @State private var hoursSlept = 8

    var body: some View {
        NavigationStack {
            Form {
                Section("About Today") {

                    Toggle(
                        "Did you drink today?",
                        isOn: $drankAlcohol
                    )

                    Stepper(
                        "Hours slept: \(hoursSlept)",
                        value: $hoursSlept,
                        in: 0...24
                    )
                }
            }
            .navigationTitle("Quick Survey")
        }
    }
}

#Preview {
    surveyForm()
}
