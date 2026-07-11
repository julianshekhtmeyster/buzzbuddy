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
    @State private var missedBlocks = 0
    @State private var correctBlocks = 0
    @State private var totalBlocks = 0
    
    
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
        missedBlocks = 0
        correctBlocks = 0
        totalBlocks = 0
        
        showNewPattern()
    }
    
    
    func showNewPattern() {
        
        selected.removeAll()
        
        let totalSquares = gridSize * gridSize
        
        let amount = gridSize
        
        totalBlocks += amount
        
        pattern = Set(
            (0..<totalSquares)
                .shuffled()
                .prefix(amount)
        )
        
        
        showingPattern = true
        message = "Memorize!"
        
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
        
        let correct = pattern.intersection(selected).count
        correctBlocks += correct
        
        completedLevels += 1
        
        selected.removeAll()
        
        if gridSize == 5 {
            finishGame()
        } else {
            gridSize += 1
            message = "Next Round!"
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showNewPattern()
            }
        }
    }
    
    func finishGame() {
        
        let accuracy = totalBlocks > 0
            ? (Double(correctBlocks) / Double(totalBlocks)) * 100
            : 0
        
        let accuracyScore = Int(accuracy.rounded())
        
        engine.completeGame(
            gameType: "Memory",
            gameScore: accuracyScore
        )
        
        message = "Finished! Accuracy: \(accuracyScore)%"
        
        gameStarted = false
        showingPattern = false
    }
}
