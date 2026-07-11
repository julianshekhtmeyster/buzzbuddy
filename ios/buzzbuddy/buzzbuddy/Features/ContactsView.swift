//
//  ContactsView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI
import Contacts

// MARK: - Model

struct Contact: Identifiable, Hashable {
    let id: String
    let name: String
    let phoneNumber: String?   // stored for later use, never displayed
    let imageData: Data?
}

// MARK: - View Model

@MainActor
final class ContactsViewModel: ObservableObject {
    @Published private(set) var activeContacts: [Contact] = []
    @Published private(set) var availableContacts: [Contact] = []
    @Published private(set) var authorizationStatus: CNAuthorizationStatus =
        CNContactStore.authorizationStatus(for: .contacts)
    @Published private(set) var isLoading = false

    private let store = CNContactStore()
    private var hasLoaded = false

    /// Call on appear. Requests access if needed, then syncs contacts.
    func syncIfNeeded() async {
        guard !hasLoaded else { return }

        switch authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await store.requestAccess(for: .contacts)
                authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
                if granted {
                    await fetchContacts()
                }
            } catch {
                authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
            }
        case .authorized, .limited:
            await fetchContacts()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    private func fetchContacts() async {
        hasLoaded = true
        isLoading = true
        defer { isLoading = false }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]

        let store = self.store
        let fetched: [Contact] = await Task.detached(priority: .userInitiated) {
            var result: [Contact] = []
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .givenName

            try? store.enumerateContacts(with: request) { cnContact, _ in
                let name = [cnContact.givenName, cnContact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let displayName = name.isEmpty ? "Unknown" : name
                let phone = cnContact.phoneNumbers.first?.value.stringValue

                result.append(
                    Contact(
                        id: cnContact.identifier,
                        name: displayName,
                        phoneNumber: phone,
                        imageData: cnContact.thumbnailImageData
                    )
                )
            }
            return result
        }.value

        availableContacts = fetched
    }
}

// MARK: - View

struct ContactsView: View {
    @StateObject private var viewModel = ContactsViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Contacts")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 14)

                ScrollView {
                    content
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await viewModel.syncIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.authorizationStatus {
        case .authorized, .limited:
            VStack(alignment: .leading, spacing: 28) {
                sectionCard(
                    title: "Active",
                    contacts: viewModel.activeContacts,
                    isActive: true,
                    emptyText: "No active contacts yet"
                )
                sectionCard(
                    title: "Available",
                    contacts: viewModel.availableContacts,
                    isActive: false,
                    emptyText: "No contacts found"
                )
            }
        case .notDetermined:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
        case .denied, .restricted:
            permissionDeniedView
        @unknown default:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
        }
    }

    private func sectionCard(
        title: String,
        contacts: [Contact],
        isActive: Bool,
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            if contacts.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(contacts) { contact in
                        ContactRow(contact: contact, isActive: isActive)
                    }
                }
            }
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("Contacts Access Needed")
                .font(.headline)

            Text("Enable contacts access in Settings to sync your contacts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
}

// MARK: - Row

private struct ContactRow: View {
    let contact: Contact
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            avatar
            Text(contact.name)
                .font(.system(size: 16, weight: .medium))
            Spacer()
        }
        .foregroundStyle(isActive ? Color.primary : Color.secondary)
        .opacity(isActive ? 1 : 0.5)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var avatar: some View {
        if let data = contact.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(initials)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                )
        }
    }

    private var initials: String {
        let parts = contact.name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

#Preview {
    ContactsView()
}
