//
//  EventsView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct EventsView: View {
    @Environment(\.tabBarHeight) private var tabBarHeight
    @State private var showingAddEvent = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    Text("Events")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                        .padding(.bottom, 14)

                    ScrollView {
                        content
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                    }
                }

                Button {
                    showingAddEvent = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 68)
                        .background(Circle().fill(Color.accentColor))
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                }
                .padding(.trailing, 20)
                .padding(.bottom, tabBarHeight + 28)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingAddEvent) {
                AddEventView()
            }
        }
    }

    private var content: some View {
        Text("No events yet")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 40)
    }
}

#Preview {
    EventsView()
}
