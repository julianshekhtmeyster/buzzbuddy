//
//  MainTabView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

// MARK: - Tab bar height plumbing

private struct TabBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TabBarHeightEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// The custom tab bar's measured height (not the safe-area inset,
    /// just the visible bar row). Any screen can read this to pad
    /// bottom-pinned content so it clears the bar, without guessing.
    var tabBarHeight: CGFloat {
        get { self[TabBarHeightEnvironmentKey.self] }
        set { self[TabBarHeightEnvironmentKey.self] = newValue }
    }
}

struct MainTabView: View {

    enum Tab {
        case events, contacts, quiz, baseline, settings
    }

    @State private var selectedTab: Tab = .events
    @State private var tabBarHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .events:
                    EventsView()
                case .contacts:
                    ContactsView()
                case .quiz:
                    HomeView()
                case .baseline:
                    BaselineView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.tabBarHeight, tabBarHeight)

            CustomTabBar(selectedTab: $selectedTab)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: TabBarHeightPreferenceKey.self, value: geo.size.height)
                    }
                )
        }
        .onPreferenceChange(TabBarHeightPreferenceKey.self) { height in
            tabBarHeight = height
        }.ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

// MARK: - Custom Tab Bar

private struct CustomTabBar: View {
    @Binding var selectedTab: MainTabView.Tab

    /// Total height of the bar's content row (excludes safe area inset).
    /// Everything else (middle button size, etc.) derives from this
    /// so nothing is a hand-picked magic number.
    private let barContentHeight: CGFloat = 64

    var body: some View {
        HStack(spacing: 0) {

            TabBarButton(
                icon: "party.popper.fill",
                title: "Events",
                isSelected: selectedTab == .events
            ) {
                selectedTab = .events
            }

            TabBarButton(
                icon: "person.fill",
                title: "Contacts",
                isSelected: selectedTab == .contacts
            ) {
                selectedTab = .contacts
            }

            MiddleTabButton(
                icon: "bolt.fill",
                isSelected: selectedTab == .quiz,
                containerHeight: barContentHeight
            ) {
                selectedTab = .quiz
            }

            TabBarButton(
                icon: "waveform.path.ecg",
                title: "Baseline",
                isSelected: selectedTab == .baseline
            ) {
                selectedTab = .baseline
            }

            TabBarButton(
                icon: "gearshape.fill",
                title: "Settings",
                isSelected: selectedTab == .settings
            ) {
                selectedTab = .settings
            }
        }
        .frame(height: barContentHeight)
        .background(.bar, ignoresSafeAreaEdges: .bottom)
    }
}

// MARK: - Standard Tab Button

private struct TabBarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Prominent Middle Tab Button

private struct MiddleTabButton: View {
    let icon: String
    let isSelected: Bool
    /// Height of the tab bar's content row. The circle and icon are sized
    /// as fractions of this, so the button stays proportionate and fully
    /// contained inside the bar rather than relying on a fixed size/offset.
    let containerHeight: CGFloat
    let action: () -> Void

    private var circleDiameter: CGFloat { containerHeight * 0.72 }
    private var ringPadding: CGFloat { circleDiameter * 0.07 }
    private var iconSize: CGFloat { circleDiameter * 0.44 }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: ringPadding)
                    .frame(width: circleDiameter + ringPadding * 2,
                           height: circleDiameter + ringPadding * 2)

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: circleDiameter, height: circleDiameter)

                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainTabView()
}
