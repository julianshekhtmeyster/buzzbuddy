//
//  TestFormView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/11/26.
//


import SwiftUI

struct TestFormView: View {

    @EnvironmentObject var engine: TestEngine
    
    @State private var mood = 3
    @State private var energy = 3
    @State private var notes = ""
    
    
    var body: some View {
        
        VStack(spacing: 25) {
            
            Text("Quick Check-In")
                .font(.largeTitle)
                .bold()
            
            
            Text("How are you feeling right now?")
                .font(.headline)
            
            
            Stepper(
                "Mood: \(mood)/5",
                value: $mood,
                in: 1...5
            )
            
            
            Stepper(
                "Energy: \(energy)/5",
                value: $energy,
                in: 1...5
            )
            
            
            TextField(
                "Additional notes (optional)",
                text: $notes
            )
            .textFieldStyle(.roundedBorder)
            
            
            Spacer()
            
            
            Button {
                submitForm()
            } label: {
                Text("Finish")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 150, height: 50)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
            }
            
        }
        .padding()
    }
    
    
    func submitForm() {
        
        // Save form data here later
        
        engine.currentIndex = 100000
    }
}
