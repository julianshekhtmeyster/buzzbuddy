//
//  BalanceGame.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct BalanceGame: View {

    @EnvironmentObject var engine: GameSessionEngine


    var body: some View {
        NavigationStack {

            Text("Balance")
            Button("Next Game"){
                engine.nextGame()

            }
        }
    }
}
