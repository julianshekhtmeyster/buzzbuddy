import Combine
import Foundation

enum TestKind: Equatable {
    case reaction
    case balance
    case memory
    case unknown

    init(pendingTest: String) {
        switch pendingTest {
        case "reaction": self = .reaction
        case "gyro", "balance": self = .balance
        case "memory": self = .memory
        default: self = .unknown
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case onboarding
        case baselineUpgrade
        case readyToStartEvent
        case startingEvent
        case takingTest(pendingTest: String)
        case reviewingTest(pendingTest: String)
        case submissionFailed(pendingTest: String, testType: String, rawValue: Double)
        case unsupportedTest(pendingTest: String)
        case verdict
        case restoring
        case restoreFailed(sessionId: String)
    }

    @Published var phase: Phase
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var session: SessionOut?
    @Published private(set) var contacts: [DDContactOut] = []
    @Published private(set) var ownerName: String?
    @Published private(set) var latestLocationURL: String?
    @Published private(set) var reactionBaselineMs: Double?
    @Published private(set) var gyroBaselineScore: Double?
    @Published private(set) var memoryBaselinePercent: Double?
    @Published var selectedContactId: String? {
        didSet { defaults.set(selectedContactId, forKey: Keys.selectedContactId) }
    }

    private let api: BuzzBuddyAPIProtocol
    private let persistence: PersistenceStore
    private let locationProvider: LocationProviding
    private let ownerCredentials: OwnerCredentialStoring
    private let defaults: UserDefaults
    private var userId: String?
    private var eventId: String?

    private enum Keys {
        static let legacyUserId = "buzzbuddy.ownerUserId"
        static let ownerName = "buzzbuddy.ownerName"
        static let selectedContactId = "buzzbuddy.selectedContactId"
        static let contacts = "buzzbuddy.ownerContacts"
    }

    init(
        api: BuzzBuddyAPIProtocol = BuzzBuddyAPI(),
        persistence: PersistenceStore = UserDefaultsPersistenceStore(),
        locationProvider: LocationProviding = LocationProvider(),
        ownerCredentials: OwnerCredentialStoring = OwnerCredentialStore(),
        defaults: UserDefaults = .standard
    ) {
        self.api = api
        self.persistence = persistence
        self.locationProvider = locationProvider
        self.ownerCredentials = ownerCredentials
        self.defaults = defaults

        let persistedUserId = persistence.userId ?? defaults.string(forKey: Keys.legacyUserId)
        self.userId = persistedUserId
        if persistence.userId == nil, let persistedUserId {
            persistence.userId = persistedUserId
        }
        self.eventId = persistence.eventId
        self.ownerName = defaults.string(forKey: Keys.ownerName)
        self.selectedContactId = defaults.string(forKey: Keys.selectedContactId)
        self.reactionBaselineMs = persistence.reactionBaselineMs
        self.gyroBaselineScore = persistence.gyroBaselineScore
        self.memoryBaselinePercent = persistence.memoryBaselinePercent
        if let data = defaults.data(forKey: Keys.contacts),
           let savedContacts = try? JSONDecoder().decode([DDContactOut].self, from: data) {
            self.contacts = savedContacts
        }

        if !persistence.hasCompletedOnboarding || persistedUserId == nil {
            self.phase = .onboarding
        } else if ownerCredentials.token(for: persistedUserId!) == nil {
            self.phase = .onboarding
            self.errorMessage = "BuzzBuddy security was upgraded. Please set up your profile again to create a private owner credential."
        } else if persistence.reactionBaselineMs == nil
                    || persistence.gyroBaselineScore == nil
                    || persistence.memoryBaselinePercent == nil {
            self.phase = .baselineUpgrade
        } else if persistence.sessionId != nil {
            self.phase = .restoring
        } else {
            self.phase = .readyToStartEvent
        }
    }

    var ownerUserId: String? { userId }

    var selectedContact: DDContactOut? {
        session?.selectedContact
            ?? contacts.first(where: { $0.id == selectedContactId })
    }

    func bootstrap() async {
        guard case .restoring = phase, let sessionId = persistence.sessionId else { return }
        await restoreSession(sessionId: sessionId)
    }

    func completeOnboarding(
        name: String,
        weightKg: Double,
        heightCm: Double,
        bmi: Double,
        reactionBaselineMs: Double,
        gyroBaselineScore: Double,
        memoryBaselinePercent: Double,
        ddName: String,
        ddPhone: String
    ) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let payload = UserCreate(
                name: name,
                weightKg: weightKg,
                heightCm: heightCm,
                bmi: bmi,
                baseline: BaselineIn(
                    reactionTimeMs: reactionBaselineMs,
                    gyroStabilityScore: gyroBaselineScore,
                    memoryRecallPercent: memoryBaselinePercent
                ),
                ddContacts: [DDContactIn(name: ddName, phoneNumber: ddPhone, email: nil)]
            )
            let user = try await api.createUser(payload)
            guard let accessToken = user.accessToken, !accessToken.isEmpty else {
                throw APIError.invalidResponse
            }
            try ownerCredentials.save(accessToken, for: user.id)

            userId = user.id
            ownerName = user.name
            contacts = user.ddContacts
            persistence.userId = user.id
            persistence.hasCompletedOnboarding = true
            persistence.reactionBaselineMs = reactionBaselineMs
            persistence.gyroBaselineScore = gyroBaselineScore
            persistence.memoryBaselinePercent = memoryBaselinePercent
            self.reactionBaselineMs = reactionBaselineMs
            self.gyroBaselineScore = gyroBaselineScore
            self.memoryBaselinePercent = memoryBaselinePercent
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

    func completeBaselineUpgrade(
        reactionBaselineMs: Double?,
        gyroBaselineScore: Double?,
        memoryBaselinePercent: Double?
    ) async {
        guard let userId, let ownerToken = ownerCredentials.token(for: userId) else {
            errorMessage = "Your owner credential is missing. Please set up your profile again."
            phase = .onboarding
            return
        }
        guard case .baselineUpgrade = phase, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let payload = BaselineUpdate(
                reactionTimeMs: reactionBaselineMs,
                gyroStabilityScore: gyroBaselineScore,
                memoryRecallPercent: memoryBaselinePercent
            )
            _ = try await api.updateBaseline(
                userId: userId,
                payload,
                bearerToken: ownerToken
            )
            if let reactionBaselineMs {
                persistence.reactionBaselineMs = reactionBaselineMs
                self.reactionBaselineMs = reactionBaselineMs
            }
            if let gyroBaselineScore {
                persistence.gyroBaselineScore = gyroBaselineScore
                self.gyroBaselineScore = gyroBaselineScore
            }
            if let memoryBaselinePercent {
                persistence.memoryBaselinePercent = memoryBaselinePercent
                self.memoryBaselinePercent = memoryBaselinePercent
            }
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
            if contacts.isEmpty { errorMessage = error.localizedDescription }
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
        guard case .readyToStartEvent = phase, !isLoading else { return }
        latestLocationURL = nil
        phase = .startingEvent
        isLoading = true
        defer { isLoading = false }
        do {
            let event = try await api.createEvent(
                EventCreate(userId: userId, name: name, selectedContactId: selectedContactId),
                bearerToken: ownerToken
            )
            eventId = event.id
            persistence.eventId = event.id
            let session = try await api.startSession(eventId: event.id, bearerToken: ownerToken)
            self.session = session
            persistence.sessionId = session.id
            errorMessage = nil
            advance(from: session)
        } catch {
            errorMessage = error.localizedDescription
            phase = .readyToStartEvent
        }
    }

    func submitTestResult(testType: String, rawValue: Double) async {
        guard case .takingTest(let pendingTest) = phase, !isLoading else { return }
        await performSubmit(pendingTest: pendingTest, testType: testType, rawValue: rawValue)
    }

    func retrySubmission() async {
        guard case .submissionFailed(let pendingTest, let testType, let rawValue) = phase,
              !isLoading else { return }
        await performSubmit(pendingTest: pendingTest, testType: testType, rawValue: rawValue)
    }

    private func performSubmit(pendingTest: String, testType: String, rawValue: Double) async {
        guard let session,
              let userId,
              let ownerToken = ownerCredentials.token(for: userId) else {
            errorMessage = "Your owner credential is missing. Please set up your profile again."
            return
        }
        phase = .reviewingTest(pendingTest: pendingTest)
        isLoading = true
        defer { isLoading = false }
        do {
            let coordinate = await locationProvider.currentLocation()
            if let coordinate {
                var components = URLComponents(string: "https://maps.apple.com/")
                components?.queryItems = [
                    URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)")
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
            persistence.sessionId = updated.id
            errorMessage = nil
            advance(from: updated)
        } catch {
            errorMessage = error.localizedDescription
            phase = .submissionFailed(
                pendingTest: pendingTest,
                testType: testType,
                rawValue: rawValue
            )
        }
    }

    func retryRestore() async {
        guard case .restoreFailed(let sessionId) = phase, !isLoading else { return }
        phase = .restoring
        await restoreSession(sessionId: sessionId)
    }

    func discardSession() {
        persistence.sessionId = nil
        session = nil
        errorMessage = nil
        phase = .readyToStartEvent
    }

    private func restoreSession(sessionId: String) async {
        guard let userId, let ownerToken = ownerCredentials.token(for: userId) else {
            phase = .onboarding
            errorMessage = "Your owner credential is missing. Please set up your profile again."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let session = try await api.getSession(sessionId: sessionId, bearerToken: ownerToken)
            self.session = session
            errorMessage = nil
            advance(from: session)
        } catch {
            errorMessage = error.localizedDescription
            phase = .restoreFailed(sessionId: sessionId)
        }
    }

    func refreshSession() async {
        guard let session,
              let userId,
              let ownerToken = ownerCredentials.token(for: userId) else { return }
        do {
            let updated = try await api.getSession(sessionId: session.id, bearerToken: ownerToken)
            self.session = updated
            errorMessage = nil
            advance(from: updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reissueInvite(contactId: String) async {
        guard let userId,
              let ownerToken = ownerCredentials.token(for: userId) else {
            errorMessage = "Your owner credential is missing. Please set up your profile again."
            return
        }
        do {
            let updated = try await api.reissueInvite(contactId: contactId, bearerToken: ownerToken)
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
        guard let session,
              let userId,
              let ownerToken = ownerCredentials.token(for: userId) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            self.session = try await api.requestSMSFallback(
                sessionId: session.id,
                bearerToken: ownerToken
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
        reactionBaselineMs = nil
        gyroBaselineScore = nil
        memoryBaselinePercent = nil
        persistence.userId = nil
        persistence.eventId = nil
        persistence.sessionId = nil
        persistence.hasCompletedOnboarding = false
        persistence.reactionBaselineMs = nil
        persistence.gyroBaselineScore = nil
        persistence.memoryBaselinePercent = nil
        defaults.removeObject(forKey: Keys.legacyUserId)
        defaults.removeObject(forKey: Keys.ownerName)
        defaults.removeObject(forKey: Keys.selectedContactId)
        defaults.removeObject(forKey: Keys.contacts)
        errorMessage = nil
        phase = .onboarding
    }

    private func advance(from session: SessionOut) {
        guard !session.notified, let pendingTest = session.pendingTest else {
            persistence.sessionId = nil
            phase = .verdict
            return
        }
        if TestKind(pendingTest: pendingTest) == .unknown {
            phase = .unsupportedTest(pendingTest: pendingTest)
        } else {
            phase = .takingTest(pendingTest: pendingTest)
        }
    }

    private func persistContacts() {
        if let data = try? JSONEncoder().encode(contacts) {
            defaults.set(data, forKey: Keys.contacts)
        }
    }
}
