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
                Section("TITLE") {

                    Toggle(
                        "QUESTION TOGGLE TEMPLATE",
                        isOn: $drankAlcohol
                    )

                    Stepper(
                        "STEPPER TEMPLATE: \(hoursSlept)",
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
