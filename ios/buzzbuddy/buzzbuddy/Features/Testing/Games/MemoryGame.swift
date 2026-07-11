//
//  MemoryGame.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct MemoryGame: View {
    @EnvironmentObject var engine: TestEngine
    
    @State private var gridSize = 3
    
    @State private var pattern: Set<Int> = []
    @State private var selected: Set<Int> = []
    
    @State private var showingPattern = false
    @State private var gameStarted = false
    
    @State private var message = "Press Start"
    
    @State private var completedLevels = 0
    
    
    var body: some View {
        VStack {
            
            Text("Memory")
                .font(.largeTitle)
                .bold()
            
            
            Text(message)
                .font(.title2)
                .padding()
            
            
            Spacer()
            
            
            gridView
            
            
            Spacer()
            
            
            if gameStarted {
                Text("Round \(gridSize - 2)/3")
                    .font(.headline)
            }
            
            
            Button(gameStarted ? "Submit" : "Start") {
                if !gameStarted {
                    startGame()
                } else if !showingPattern {
                    checkAnswer()
                }
            }
            .padding()
            .disabled(showingPattern)
        }
        .padding()
    }
    
    
    var gridView: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: gridSize
        )
        
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<(gridSize * gridSize), id: \.self) { index in
                
                Rectangle()
                    .fill(squareColor(index))
                    .aspectRatio(1, contentMode: .fit)
                    .cornerRadius(8)
                    .onTapGesture {
                        squareTapped(index)
                    }
            }
        }
        .padding()
    }
    
    
    func squareColor(_ index: Int) -> Color {
        
        if showingPattern && pattern.contains(index) {
            return .blue
        }
        
        if selected.contains(index) {
            return .green
        }
        
        return .gray
    }
    
    
    func startGame() {
        gameStarted = true
        
        gridSize = 3
        completedLevels = 0
        
        showNewPattern()
    }
    
    
    func showNewPattern() {
        
        selected.removeAll()
        
        let totalSquares = gridSize * gridSize
        
        let amount = gridSize
        
        pattern = Set(
            (0..<totalSquares)
                .shuffled()
                .prefix(amount)
        )
        
        
        showingPattern = true
        message = "Memorize!"
        
// TIME TO MEMORIZE
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            showingPattern = false
            message = "Recreate the pattern"
        }
    }
    
    
    func squareTapped(_ index: Int) {
        guard gameStarted && !showingPattern else {
            return
        }
        
        if selected.contains(index) {
            selected.remove(index)
        } else {
            selected.insert(index)
        }
    }
    
    
    func checkAnswer() {
        
        if selected == pattern {
            
            completedLevels += 1
            
            selected.removeAll()
            
            
            if gridSize == 5 {
                finishGame()
                
            } else {
                
                gridSize += 1
                message = "Correct!"
                
// TIME BETWEEN ROUNDS
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showNewPattern()
                }
            }
            
            
        } else {
            finishGame()
        }
    }
    
    
    func finishGame() {
        
        let score = completedLevels
        
        engine.completeGame(
            gameType: "Memory",
            gameScore: score
        )
        
        message = "Finished! Score: \(score)"
        
        gameStarted = false
        showingPattern = false
    }
}
