//
//  GoNoGoGame.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/11/26.
//

import SwiftUI

struct GoNoGoGame: View {
    @EnvironmentObject var engine: TestEngine
    
    enum ButtonColor {
        case red
        case green
    }
    
    @State private var instruction = "Press Start"
    @State private var instructionColor: Color = .primary
    
    @State private var activeTarget: ButtonColor?
    
    @State private var canPress = false
    @State private var isPlaying = false
    
    @State private var round = 0
    @State private var score = 0
    
    @State private var startTime = Date()
    
    let totalRounds = 3
    
    
    var body: some View {
        VStack(spacing: 40) {
            
            Text("Commands")
                .font(.largeTitle)
                .bold()
            
            
            Text(instruction)
                .font(.title)
                .bold()
                .foregroundColor(instructionColor)
            
            
            Spacer()
            
            
            HStack(spacing: 30) {
                
                Button {
                    pressed(.green)
                } label: {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.green)
                        .frame(width: 140, height: 180)
                }
                .disabled(!canPress)
                
                
                Button {
                    pressed(.red)
                } label: {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.red)
                        .frame(width: 140, height: 180)
                }
                .disabled(!canPress)
            }
            
            
            Spacer()
            
            
            if isPlaying {
                Text("Round \(round)/\(totalRounds)")
            }
            
            
            Button("Start") {
                startGame()
            }
            .disabled(isPlaying)
        }
        .padding()
    }
    
    
    func startGame() {
        score = 0
        round = 0
        isPlaying = true
        
        nextRound()
    }
    
    
    func nextRound() {
        
        if round >= totalRounds {
            finishGame()
            return
        }
        
        round += 1
        
        canPress = false
        activeTarget = nil
        
        instruction = "Get Ready..."
        instructionColor = .gray
        
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            
            activeTarget = Bool.random() ? .green : .red
            
            switch activeTarget! {
            case .green:
                instruction = "PRESS GREEN"
                instructionColor = .green
                
            case .red:
                instruction = "PRESS RED"
                instructionColor = .red
            }
            
            startTime = Date()
            canPress = true
        }
    }
    
    
    func pressed(_ button: ButtonColor) {
        guard canPress,
              let target = activeTarget
        else {
            return
        }
        
        canPress = false
        
        let _ = Int(
            Date().timeIntervalSince(startTime) * 1000
        )
        
        
        if button == target {
            score += 1
        }
        
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            nextRound()
        }
    }
    
    
    func finishGame() {
        isPlaying = false
        canPress = false
        
        let accuracy = Double(score) / Double(totalRounds)
        let accuracyPercentage = Int(accuracy * 100)
        
        engine.completeGame(
            gameType: "GoNoGoGame",
            gameScore: accuracyPercentage
        )
        
        instruction = "Accuracy: \(accuracyPercentage)%"
        instructionColor = .blue
    }
}
