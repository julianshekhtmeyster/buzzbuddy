//
//  ReactionGame.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct ReactionGame: View {
    
    @EnvironmentObject var engine:TestEngine

    
    var body: some View {
        NavigationStack {
            
            Text("Reaction")
            Button("Next Game"){
                engine.nextGame()

            }
        }
    }
}


