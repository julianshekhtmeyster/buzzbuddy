import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case onboarding
        case readyToStartEvent
        case takingTest(pendingTest: String)
        case verdict
    }

    @Published var phase: Phase = .onboarding
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var session: SessionOut?
    @Published private(set) var contacts: [DDContactOut] = []
    @Published private(set) var ownerName: String?
    @Published private(set) var latestLocationURL: String?
    @Published var selectedContactId: String? {
        didSet { defaults.set(selectedContactId, forKey: Keys.selectedContactId) }
    }

    private let api = BuzzBuddyAPI()
    private let locationProvider = LocationProvider()
    private let ownerCredentials = OwnerCredentialStore()
    private let defaults = UserDefaults.standard
    private var userId: String?
    private var eventId: String?

    private enum Keys {
        static let userId = "buzzbuddy.ownerUserId"
        static let ownerName = "buzzbuddy.ownerName"
        static let selectedContactId = "buzzbuddy.selectedContactId"
        static let contacts = "buzzbuddy.ownerContacts"
    }

    init() {
        userId = defaults.string(forKey: Keys.userId)
        ownerName = defaults.string(forKey: Keys.ownerName)
        selectedContactId = defaults.string(forKey: Keys.selectedContactId)
        if let data = defaults.data(forKey: Keys.contacts),
           let savedContacts = try? JSONDecoder().decode([DDContactOut].self, from: data) {
            contacts = savedContacts
        }
        if let userId {
            if ownerCredentials.token(for: userId) != nil {
                phase = .readyToStartEvent
            } else {
                errorMessage = "BuzzBuddy security was upgraded. Please set up your profile again to create a private owner credential."
                phase = .onboarding
            }
        }
    }

    var ownerUserId: String? { userId }

    var selectedContact: DDContactOut? {
        session?.selectedContact
            ?? contacts.first(where: { $0.id == selectedContactId })
    }

    func completeOnboarding(
        name: String,
        weightKg: Double,
        heightCm: Double,
        bmi: Double,
        reactionBaselineMs: Double,
        gyroBaselineScore: Double,
        memoryBaselineScore: Double,
        ddName: String,
        ddPhone: String
    ) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let baseline = BaselineIn(
                reactionTimeMs: reactionBaselineMs,
                gyroStabilityScore: gyroBaselineScore,
                memoryRecallScore: memoryBaselineScore
            )
            let contact = DDContactIn(name: ddName, phoneNumber: ddPhone, email: nil)
            let payload = UserCreate(
                name: name, weightKg: weightKg, heightCm: heightCm, bmi: bmi,
                baseline: baseline, ddContacts: [contact]
            )
            let user = try await api.createUser(payload)
            guard let accessToken = user.accessToken, !accessToken.isEmpty else {
                throw APIError.invalidResponse
            }
            try ownerCredentials.save(accessToken, for: user.id)
            userId = user.id
            ownerName = user.name
            contacts = user.ddContacts
            defaults.set(user.id, forKey: Keys.userId)
            defaults.set(user.name, forKey: Keys.ownerName)
            if contacts.isEmpty {
                contacts = try await api.getContacts(userId: user.id, bearerToken: accessToken)
            }
            selectedContactId = contacts.first?.id
            persistContacts()
            errorMessage = nil
            phase = .readyToStartEvent
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshContacts() async {
        guard let userId, let ownerToken = ownerCredentials.token(for: userId) else { return }
        do {
            contacts = try await api.getContacts(userId: userId, bearerToken: ownerToken)
            if selectedContactId == nil || !contacts.contains(where: { $0.id == selectedContactId }) {
                selectedContactId = contacts.first?.id
            }
            persistContacts()
            errorMessage = nil
        } catch {
            // Keep the cached invite and selected contact available offline.
            if contacts.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    func startEvent(name: String) async {
        guard let userId, let ownerToken = ownerCredentials.token(for: userId) else {
            errorMessage = "Your owner credential is missing. Please set up your profile again."
            phase = .onboarding
            return
        }
        guard let selectedContactId else {
            errorMessage = "Choose a trusted contact before starting the event."
            return
        }
        // Never carry a previous event's location into this event's manual
        // fallback message if fresh location access is denied or unavailable.
        latestLocationURL = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let event = try await api.createEvent(
                EventCreate(
                    userId: userId,
                    name: name,
                    selectedContactId: selectedContactId
                ),
                bearerToken: ownerToken
            )
            eventId = event.id
            let session = try await api.startSession(eventId: event.id, bearerToken: ownerToken)
            self.session = session
            errorMessage = nil
            advance(from: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitTestResult(testType: String, rawValue: Double) async {
        guard let session, let userId, let ownerToken = ownerCredentials.token(for: userId) else {
            errorMessage = "Your owner credential is missing. Please set up your profile again."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            // Best-effort: a denied/unavailable location just means the DD
            // alert (if the AI escalates) won't include one.
            let coordinate = await locationProvider.currentLocation()
            if let coordinate {
                var components = URLComponents(string: "https://maps.apple.com/")
                components?.queryItems = [
                    URLQueryItem(
                        name: "ll",
                        value: "\(coordinate.latitude),\(coordinate.longitude)"
                    )
                ]
                latestLocationURL = components?.url?.absoluteString
            }
            let updated = try await api.submitTestResult(
                sessionId: session.id,
                TestResultIn(
                    testType: testType,
                    rawValue: rawValue,
                    latitude: coordinate?.latitude,
                    longitude: coordinate?.longitude
                ),
                bearerToken: ownerToken
            )
            self.session = updated
            errorMessage = nil
            advance(from: updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshSession() async {
        guard let session, let userId, let ownerToken = ownerCredentials.token(for: userId) else {
            return
        }
        do {
            let updated = try await api.getSession(
                sessionId: session.id, bearerToken: ownerToken
            )
            self.session = updated
            errorMessage = nil
            advance(from: updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reissueInvite(contactId: String) async {
        guard let userId, let ownerToken = ownerCredentials.token(for: userId) else {
            errorMessage = "Your owner credential is missing. Please set up your profile again."
            return
        }
        do {
            let updated = try await api.reissueInvite(
                contactId: contactId, bearerToken: ownerToken
            )
            if let index = contacts.firstIndex(where: { $0.id == contactId }) {
                contacts[index] = updated
            }
            persistContacts()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestServerSMSFallback() async {
        guard let session, let userId,
              let ownerToken = ownerCredentials.token(for: userId) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            self.session = try await api.requestSMSFallback(
                sessionId: session.id, bearerToken: ownerToken
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetLocalProfile() {
        if let userId { ownerCredentials.delete(for: userId) }
        userId = nil
        eventId = nil
        ownerName = nil
        contacts = []
        selectedContactId = nil
        session = nil
        latestLocationURL = nil
        defaults.removeObject(forKey: Keys.userId)
        defaults.removeObject(forKey: Keys.ownerName)
        defaults.removeObject(forKey: Keys.selectedContactId)
        defaults.removeObject(forKey: Keys.contacts)
        errorMessage = nil
        phase = .onboarding
    }

    private func advance(from session: SessionOut) {
        // `status` (clear/mild/severe) is the AI's evolving confidence label,
        // not a lifecycle flag — it can say "severe" while still wanting a
        // cross-check test before concluding. The session is actually over
        // only once the DD has been notified, or the AI stopped requesting
        // further tests.
        if session.notified || session.pendingTest == nil {
            phase = .verdict
        } else {
            phase = .takingTest(pendingTest: session.pendingTest!)
        }
    }

    private func persistContacts() {
        if let data = try? JSONEncoder().encode(contacts) {
            defaults.set(data, forKey: Keys.contacts)
        }
    }
}
