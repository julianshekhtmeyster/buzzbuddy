//
//  HomeView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var engine: TestEngine

    @State private var isBreathing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                startButton

                Text("Tap to begin your safety check")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 32)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var startButton: some View {
        Button {
            engine.startTest()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.yellow, Color(red: 0.95, green: 0.72, blue: 0.05)],
                            center: UnitPoint(x: 0.35, y: 0.3),
                            startRadius: 10,
                            endRadius: 150
                        )
                    )
                    .frame(width: 220, height: 220)

                VStack(spacing: 2) {
                    Text("START")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                    Text("TEST")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .tracking(1.2)
            }
            .scaleEffect(isBreathing ? 1.06 : 1.0)
        }
        .buttonStyle(PressableStyle())
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}

// MARK: - Pressable Button Style

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

#Preview {
    HomeView()
        .environmentObject(TestEngine())
}
