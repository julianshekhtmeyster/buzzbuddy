import Foundation
import Security

enum TrustedContactError: LocalizedError {
    case invalidInviteCode
    case missingAccessToken
    case missingCredential
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidInviteCode:
            return "Enter the invite code your friend shared with you."
        case .missingAccessToken:
            return "The invite was accepted, but the server did not return a contact credential."
        case .missingCredential:
            return "This trusted-contact invite needs to be accepted again on this device."
        case .keychain(let status):
            return "The trusted-contact credential could not be saved (\(status))."
        }
    }
}

final class ContactCredentialStore {
    private let service = "mjj.buzzbuddy.trusted-contact"

    func save(_ token: String, for contactId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: contactId
        ]
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw TrustedContactError.keychain(status) }
    }

    func token(for contactId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: contactId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

protocol OwnerCredentialStoring {
    func save(_ token: String, for userId: String) throws
    func token(for userId: String) -> String?
    func delete(for userId: String)
}

final class OwnerCredentialStore: OwnerCredentialStoring {
    private let service = "mjj.buzzbuddy.owner"

    func save(_ token: String, for userId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userId
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw TrustedContactError.keychain(status) }
    }

    func token(for userId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(for userId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userId
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class TrustedContactStore: ObservableObject {
    @Published private(set) var acceptedContacts: [DDContactOut] = []
    @Published private(set) var notificationsByContact: [String: [NotificationAttemptOut]] = [:]
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false

    private let api: BuzzBuddyAPI
    private let credentials: ContactCredentialStore
    private let defaults: UserDefaults
    private let acceptedContactsKey = "buzzbuddy.acceptedTrustedContacts"

    init(
        api: BuzzBuddyAPI = BuzzBuddyAPI(),
        credentials: ContactCredentialStore = ContactCredentialStore(),
        defaults: UserDefaults = .standard
    ) {
        self.api = api
        self.credentials = credentials
        self.defaults = defaults
        if let data = defaults.data(forKey: acceptedContactsKey),
           let contacts = try? JSONDecoder().decode([DDContactOut].self, from: data) {
            acceptedContacts = contacts
        }
    }

    var allNotifications: [NotificationAttemptOut] {
        notificationsByContact.values
            .flatMap { $0 }
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
    }

    func acceptInvite(
        code: String,
        deviceToken: String?,
        environment: String,
        smsConsent: Bool = false,
        confirmedPhoneNumber: String? = nil
    ) async {
        // Invite codes are opaque and case-sensitive; never normalize case.
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCode.isEmpty else {
            errorMessage = TrustedContactError.invalidInviteCode.localizedDescription
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let acceptance = try await api.acceptContactInvite(
                AcceptInviteIn(
                    inviteCode: cleanCode,
                    deviceToken: deviceToken,
                    environment: environment,
                    smsConsent: smsConsent,
                    confirmedPhoneNumber: confirmedPhoneNumber
                )
            )
            guard let accessToken = acceptance.accessToken, !accessToken.isEmpty else {
                throw TrustedContactError.missingAccessToken
            }
            try credentials.save(accessToken, for: acceptance.contact.id)
            upsert(contact: acceptance.contact)
            errorMessage = nil

            // The accept endpoint can register the token atomically. Calling the
            // device endpoint too makes a late/reissued APNs token converge.
            if let deviceToken {
                await registerDevice(
                    for: acceptance.contact.id,
                    deviceToken: deviceToken,
                    environment: environment
                )
            }
            await refreshNotifications()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func registerDevices(deviceToken: String, environment: String) async {
        for contact in acceptedContacts {
            await registerDevice(for: contact.id, deviceToken: deviceToken, environment: environment)
        }
    }

    func refreshNotifications() async {
        guard !acceptedContacts.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        var lastError: Error?
        for contact in acceptedContacts {
            guard let token = credentials.token(for: contact.id) else {
                lastError = TrustedContactError.missingCredential
                continue
            }
            do {
                notificationsByContact[contact.id] = try await api.getNotifications(
                    contactId: contact.id,
                    bearerToken: token
                )
            } catch {
                lastError = error
            }
        }
        errorMessage = lastError?.localizedDescription
    }

    @discardableResult
    func acknowledge(
        attemptId: String,
        contactId: String?,
        response: String
    ) async -> Bool {
        let candidateIds: [String]
        if let contactId, credentials.token(for: contactId) != nil {
            candidateIds = [contactId]
        } else if let knownId = notificationsByContact.first(where: { _, attempts in
            attempts.contains(where: { $0.id == attemptId })
        })?.key {
            candidateIds = [knownId]
        } else {
            candidateIds = acceptedContacts.map(\.id)
        }

        var lastError: Error = TrustedContactError.missingCredential
        for candidateId in candidateIds {
            guard let token = credentials.token(for: candidateId) else { continue }
            do {
                let updated = try await api.acknowledgeNotification(
                    attemptId: attemptId,
                    response: response,
                    bearerToken: token
                )
                update(notification: updated)
                errorMessage = nil
                return true
            } catch {
                lastError = error
            }
        }

        errorMessage = lastError.localizedDescription
        return false
    }

    private func registerDevice(for contactId: String, deviceToken: String, environment: String) async {
        guard let token = credentials.token(for: contactId) else {
            errorMessage = TrustedContactError.missingCredential.localizedDescription
            return
        }
        do {
            _ = try await api.registerDevice(
                contactId: contactId,
                payload: ContactDeviceIn(deviceToken: deviceToken, environment: environment),
                bearerToken: token
            )
            if let index = acceptedContacts.firstIndex(where: { $0.id == contactId }) {
                acceptedContacts[index].hasRegisteredDevice = true
                persistContacts()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func upsert(contact: DDContactOut) {
        if let index = acceptedContacts.firstIndex(where: { $0.id == contact.id }) {
            acceptedContacts[index] = contact
        } else {
            acceptedContacts.append(contact)
        }
        persistContacts()
    }

    private func update(notification: NotificationAttemptOut) {
        var attempts = notificationsByContact[notification.contactId] ?? []
        if let index = attempts.firstIndex(where: { $0.id == notification.id }) {
            attempts[index] = notification
        } else {
            attempts.insert(notification, at: 0)
        }
        notificationsByContact[notification.contactId] = attempts
    }

    private func persistContacts() {
        if let data = try? JSONEncoder().encode(acceptedContacts) {
            defaults.set(data, forKey: acceptedContactsKey)
        }
    }
}
