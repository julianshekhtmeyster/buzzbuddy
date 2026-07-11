//
//  buzzbuddyApp.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI


struct Game: Identifiable {
    let id = UUID()

    let name: String

    let view: AnyView
}

struct GameLibrary {

    
   // LIST OF GAMES
    static let games: [Game] = [
        
        Game(
            name: "Reaction",
            view: AnyView(
                ReactionGame()
            )
        ),

        Game(
            name: "Balance",
            view: AnyView(
                BalanceGame()
            )
        ),
        Game(
            name: "Memory",
            view: AnyView(
                MemoryGame()
            )
        )

    ]
// LIST OF GAMES
}

class TestEngine: ObservableObject {

    @Published var selectedGames: [Game] = []

    @Published var currentIndex = 0
    
    var currentGame: Game? {

        guard currentIndex < GameLibrary.games.count else {
               return nil
           }

        return GameLibrary.games[currentIndex]
    }


    func startTest(numberOfGames: Int = 3) {

        selectedGames = Array(
        GameLibrary.games.shuffled()
                .prefix(numberOfGames)
        )

        currentIndex = 0
    }


    func nextGame() {

        currentIndex += 1

    }


    var finished: Bool {

        currentIndex >= selectedGames.count

    }
    


}



@main
struct BuzzBuddyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
