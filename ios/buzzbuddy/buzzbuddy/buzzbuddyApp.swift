//
//  buzzbuddyApp.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI


final class AppSettings: ObservableObject {
    
    //  General
    
    @Published var enableAutoCallContact = true
    @Published var soundEffects = true
    
    //  Biometrics
    
    //kg and cms
    
    @Published var weight = 77
    @Published var height = 185
    
}



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
            name: "GoNoGo",
            view: AnyView(
                GoNoGoGame()
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

    @Published var doForm = false
    @Published var isBaseline = false
    @Published var showingTest = false

    var currentGame: Game? {
        guard currentIndex < selectedGames.count else {
            return nil
        }

        return selectedGames[currentIndex]
    }

    func startTest(
        numberOfGames: Int = 3,
        isBaselineA: Bool = false,
        doFormA: Bool = false
    ) {

        showingTest = true

        selectedGames = Array(
            GameLibrary.games
                .shuffled()
                .prefix(numberOfGames)
        )

        currentIndex = 0
        isBaseline = isBaselineA
        doForm = doFormA
    }

    func completeGame(gameType: String, gameScore: Int) {

        print(gameType)
        print(gameScore)

        currentIndex += 1
    }

    func finishForm() {
        finishTest()
    }

    func finishTest() {
        showingTest = false
        isBaseline = false
        doForm = false
        currentIndex = 0
    }

    var showingForm: Bool {
        finished && doForm
    }

    var finished: Bool {
        currentIndex >= selectedGames.count
    }
}



@main
struct BuzzBuddyApp: App {
    @StateObject var engine = TestEngine()
    @StateObject var settings = AppSettings()
    @StateObject var appState = AppState()
    var body: some Scene {



        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .environmentObject(settings)
                .environmentObject(appState)


        }

    }
}
