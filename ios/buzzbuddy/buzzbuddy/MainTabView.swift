//
//  MainTabView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//


import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {

            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            EventsView()
                .tabItem {
                    Label("Events", systemImage: "calendar")
                }

            RideView()
                .tabItem {
                    Label("Ride", systemImage: "car.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}



