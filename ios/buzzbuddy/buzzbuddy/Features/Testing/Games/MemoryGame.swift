//
//  MemoryGame.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct MemoryGame: View {

    @EnvironmentObject var engine: GameSessionEngine

    var body: some View {
        NavigationStack {

            Text("Memory")
            Button("Next Game"){
                engine.nextGame()
            }
        }
    }
}
