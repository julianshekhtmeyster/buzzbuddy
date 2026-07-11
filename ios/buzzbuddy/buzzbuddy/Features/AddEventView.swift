//
//  AddEventView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI
import MapKit
import Contacts

// MARK: - Location Model

struct EventLocation: Hashable, Codable {
    var name: String
    var address: String
    var coordinate: CLLocationCoordinate2D

    static func == (lhs: EventLocation, rhs: EventLocation) -> Bool {
        lhs.name == rhs.name &&
        lhs.address == rhs.address &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude
    }

    // CLLocationCoordinate2D doesn't conform to Hashable, so this can't be
    // synthesized -- hash the same fields == compares on.
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(address)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }

    private enum CodingKeys: String, CodingKey {
        case name, address, latitude, longitude
    }

    init(name: String, address: String, coordinate: CLLocationCoordinate2D) {
        self.name = name
        self.address = address
        self.coordinate = coordinate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
    }
}

// MARK: - Location Search View Model

@MainActor
final class LocationSearchViewModel: NSObject, ObservableObject {
    @Published var query: String = "" {
        didSet { completer.queryFragment = query }
    }
    @Published private(set) var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func clearResults() {
        results = []
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> EventLocation? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(),
              let item = response.mapItems.first else {
            return nil
        }

        let address = formattedAddress(from: item.placemark)
        return EventLocation(
            name: item.name ?? completion.title,
            address: address,
            coordinate: item.placemark.coordinate
        )
    }

    private func formattedAddress(from placemark: MKPlacemark) -> String {
        var parts: [String] = []
        if let subThoroughfare = placemark.subThoroughfare, let thoroughfare = placemark.thoroughfare {
            parts.append("\(subThoroughfare) \(thoroughfare)")
        } else if let thoroughfare = placemark.thoroughfare {
            parts.append(thoroughfare)
        }
        if let locality = placemark.locality {
            parts.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            parts.append(administrativeArea)
        }
        return parts.joined(separator: ", ")
    }
}

extension LocationSearchViewModel: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.results = completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.results = []
        }
    }
}

// MARK: - Add Event View

struct AddEventView: View {
    @Environment(\.dismiss) private var dismiss

    let eventStore: EventStore

    @StateObject private var contactsVM = ContactsViewModel()

    @State private var name: String = ""
    @State private var selectedLocation: EventLocation?
    @State private var selectedContact: Contact?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Add Event")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }

                    Spacer()
                }
                .padding(.leading, 12)
            }
            .padding(.top, 24)
            .padding(.bottom, 14)

            ScrollView {
                content
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await contactsVM.syncIfNeeded()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            formField(title: "Name", text: $name, placeholder: "Event name")
            LocationField(selectedLocation: $selectedLocation)
            ContactField(selectedContact: $selectedContact, contacts: contactsVM.availableContacts)
            saveButton
        }
    }

    private var isFormComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        selectedLocation != nil &&
        selectedContact != nil
    }

    private var saveButton: some View {
        HStack {
            Spacer()
            Button {
                saveEvent()
            } label: {
                Text("Save")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isFormComplete ? .white : Color.gray)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(isFormComplete ? Color.yellow : Color.yellow.opacity(0.35))
                    )
            }
            .disabled(!isFormComplete)
        }
        .padding(.top, 12)
    }

    private func saveEvent() {
        guard let location = selectedLocation, let contact = selectedContact else { return }
        let event = Event(name: name, location: location, contact: contact)
        eventStore.add(event)
        dismiss()
    }

    private func formField(
        title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            HStack(spacing: 10) {
                Image(systemName: "pencil")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                TextField(placeholder, text: text)
                    .font(.system(size: 16))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
    }
}

// MARK: - Location Field

private struct LocationField: View {
    @Binding var selectedLocation: EventLocation?
    @StateObject private var searchVM = LocationSearchViewModel()
    @State private var isSearching = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LOCATION")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            if let location = selectedLocation {
                selectedLocationCard(location)
            } else {
                searchField
                if !searchVM.results.isEmpty {
                    suggestionsList
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            TextField("Search for an address or place", text: $searchVM.query)
                .font(.system(size: 16))
                .focused($isFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }

    private var suggestionsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(searchVM.results.enumerated()), id: \.offset) { index, result in
                Button {
                    Task { await select(result) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if index < searchVM.results.count - 1 {
                    Divider()
                        .padding(.leading, 14)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func selectedLocationCard(_ location: EventLocation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Map(initialPosition: .region(
                MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )) {
                Marker(location.name, coordinate: location.coordinate)
            }
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .allowsHitTesting(false)
            .padding(.bottom, 10)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name)
                        .font(.system(size: 15, weight: .semibold))
                    if !location.address.isEmpty {
                        Text(location.address)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    clearSelection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func select(_ completion: MKLocalSearchCompletion) async {
        guard let location = await searchVM.resolve(completion) else { return }
        selectedLocation = location
        isFocused = false
        searchVM.clearResults()
    }

    private func clearSelection() {
        selectedLocation = nil
        searchVM.query = ""
        searchVM.clearResults()
    }
}

// MARK: - Contact Field

private struct ContactField: View {
    @Binding var selectedContact: Contact?
    let contacts: [Contact]

    @State private var query: String = ""
    @FocusState private var isFocused: Bool

    private var matches: [Contact] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return contacts.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONTACT")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            if let contact = selectedContact {
                selectedContactCard(contact)
            } else {
                searchField
                if !matches.isEmpty {
                    suggestionsList
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            TextField("Search your contacts", text: $query)
                .font(.system(size: 16))
                .focused($isFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }

    private var suggestionsList: some View {
        VStack(spacing: 0) {
            ForEach(matches) { contact in
                Button {
                    select(contact)
                } label: {
                    HStack(spacing: 12) {
                        avatar(for: contact)
                        Text(contact.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                if contact.id != matches.last?.id {
                    Divider()
                        .padding(.leading, 50)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func selectedContactCard(_ contact: Contact) -> some View {
        HStack(spacing: 12) {
            avatar(for: contact)

            Text(contact.name)
                .font(.system(size: 15, weight: .semibold))

            Spacer()

            Button {
                clearSelection()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private func avatar(for contact: Contact) -> some View {
        if let data = contact.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(initials(for: contact.name))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                )
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    private func select(_ contact: Contact) {
        selectedContact = contact
        query = ""
        isFocused = false
    }

    private func clearSelection() {
        selectedContact = nil
        query = ""
    }
}

#Preview {
    NavigationStack {
        AddEventView(eventStore: EventStore())
    }
}
