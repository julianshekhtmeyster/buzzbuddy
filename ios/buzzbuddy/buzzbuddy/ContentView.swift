//
//  ContentView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct ContentView: View {
    
    @ObservedObject var gameEngine:TestEngine
    
    var body: some View {
        MainTabView(gameEngine: gameEngine)
    }
}


