//
//  ReactionGame.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct ReactionGame: View {
    @EnvironmentObject var engine: TestEngine
    
    @State private var boxColor: Color = .gray
    @State private var boxText = "Press Start"
    
    @State private var isPlaying = false
    @State private var waiting = false
    @State private var measuring = false
    
    @State private var startTime = Date()
    
    @State private var round = 0
    @State private var reactionTimes: [Int] = []
    
    let totalRounds = 2
    
    
    var body: some View {
        VStack {
            
            Text("Reaction Time")
                .font(.largeTitle)
                .bold()
            
            
            Spacer()
            
            
            Button {
                boxTapped()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 30)
                        .fill(boxColor)
                        .frame(width: 320, height: 320)
                    
                    Text(boxText)
                        .font(.title)
                        .bold()
                        .foregroundColor(.white)
                }
            }
            .disabled(isPlaying && !waiting && !measuring)
            
            
            Spacer()
            
            
            if isPlaying {
                Text("Round \(round)/\(totalRounds)")
                    .font(.headline)
            }
        }
        .padding()
    }
    
    
    func boxTapped() {
        
        // First tap starts the test
        if !isPlaying {
            startGame()
            return
        }
        
        
        // Tap too early
        if waiting {
            waiting = false
            
            boxColor = .gray
            boxText = "Too Early!"
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                nextRound()
            }
            
            return
        }
        
        
        // Correct reaction
        if measuring {
            
            let reactionTime = Int(
                Date().timeIntervalSince(startTime) * 1000
            )
            
            reactionTimes.append(reactionTime)
            
            measuring = false
            
            boxColor = .blue
            boxText = "\(reactionTime) ms"
            
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                nextRound()
            }
        }
    }
    
    
    func startGame() {
        round = 0
        reactionTimes.removeAll()
        isPlaying = true
        
        nextRound()
    }
    
    
    func nextRound() {
        
        if round >= totalRounds {
            finishGame()
            return
        }
        
        
        round += 1
        
        waiting = true
        measuring = false
        
        boxColor = .red
        boxText = "Wait..."
        
        
        let delay = Double.random(in: 1.5...4)
        
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            
            guard waiting else {
                return
            }
            
            waiting = false
            measuring = true
            
            boxColor = .green
            boxText = "TAP!"
            
            startTime = Date()
        }
    }
    
    
    func finishGame() {
        
        isPlaying = false
        waiting = false
        measuring = false
        
        let average = reactionTimes.reduce(0, +) / max(reactionTimes.count, 1)
        
        
        engine.completeGame(
            gameType: "ReactionTime",
            gameScore: average
        )
        
        
        boxColor = .blue
        boxText = "\(average) ms"
    }
}
