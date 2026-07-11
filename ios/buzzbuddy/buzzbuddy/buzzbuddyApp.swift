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

class GameSessionEngine: ObservableObject {

    @Published var selectedGames: [Game] = []

    @Published var currentIndex = 0

    var currentGame: Game? {
        guard currentIndex < selectedGames.count else {
            return nil
        }
        return selectedGames[currentIndex]
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
        !selectedGames.isEmpty && currentIndex >= selectedGames.count
    }
}



@main
struct BuzzBuddyApp: App {
    @UIApplicationDelegateAdaptor(BuzzBuddyAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var trustedContacts = TrustedContactStore()
    @StateObject private var pushNotifications = PushNotificationManager.shared
    @StateObject private var engine = GameSessionEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(trustedContacts)
                .environmentObject(pushNotifications)
                .environmentObject(engine)
                .task {
                    await pushNotifications.prepare()
                    await appState.refreshContacts()
                    await trustedContacts.refreshNotifications()
                    if let token = pushNotifications.deviceToken {
                        await trustedContacts.registerDevices(
                            deviceToken: token,
                            environment: pushNotifications.environment
                        )
                    }
                }
                .onChange(of: pushNotifications.deviceToken) { _, token in
                    guard let token else { return }
                    Task {
                        await trustedContacts.registerDevices(
                            deviceToken: token,
                            environment: pushNotifications.environment
                        )
                    }
                }
                .task(id: pushNotifications.pendingResponseAction?.id) {
                    guard let action = pushNotifications.pendingResponseAction else { return }
                    while !Task.isCancelled,
                          pushNotifications.pendingResponseAction == action {
                        let acknowledged = await trustedContacts.acknowledge(
                            attemptId: action.attemptId,
                            contactId: action.contactId,
                            response: action.response
                        )
                        if acknowledged {
                            pushNotifications.clearPendingResponse(action)
                            return
                        }
                        try? await Task.sleep(nanoseconds: 10_000_000_000)
                    }
                }
        }
    }
}
