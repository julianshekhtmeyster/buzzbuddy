//
//  EventsView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

// MARK: - Event Model

struct Event: Identifiable, Codable {
    let id: UUID
    var name: String
    var location: EventLocation?
    var contact: Contact?

    init(id: UUID = UUID(), name: String, location: EventLocation?, contact: Contact?) {
        self.id = id
        self.name = name
        self.location = location
        self.contact = contact
    }
}

// MARK: - Event Store

@MainActor
final class EventStore: ObservableObject {
    static let shared = EventStore()

    @Published private(set) var events: [Event] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("events.json")
    }()

    init() {
        load()
    }

    func add(_ event: Event) {
        events.append(event)
        save()
    }

    func remove(_ event: Event) {
        events.removeAll { $0.id == event.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([Event].self, from: data) else { return }
        events = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Events View

struct EventsView: View {
    @Environment(\.tabBarHeight) private var tabBarHeight
    @StateObject private var eventStore = EventStore.shared
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
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Color.clear.frame(height: tabBarHeight)
                    }
                }

                Button {
                    showingAddEvent = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 68)
                        .background(Circle().fill(Color.yellow))
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                }
                .padding(.trailing, 20)
                .padding(.bottom, tabBarHeight + 28)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingAddEvent) {
                AddEventView(eventStore: eventStore)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if eventStore.events.isEmpty {
            Text("No events yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 40)
        } else {
            VStack(spacing: 14) {
                ForEach(eventStore.events) { event in
                    EventCard(event: event) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            eventStore.remove(event)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}

// MARK: - Event Card

private struct EventCard: View {
    let event: Event
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.name)
                        .font(.system(size: 20, weight: .bold))

                    if let location = event.location {
                        Text(location.name)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            if let contact = event.contact {
                Divider()
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 6) {
                    Text("CONTACT")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .tracking(0.8)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        avatar(for: contact)
                        Text(contact.name)
                            .font(.system(size: 15, weight: .medium))
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func avatar(for contact: Contact) -> some View {
        if let data = contact.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(initials(for: contact.name))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                )
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

#Preview {
    EventsView()
}
