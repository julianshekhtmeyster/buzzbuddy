import Foundation

/// How a backend `pendingTest`/`test_type` string maps to an iOS test view.
/// `.unknown` exists so an unrecognized value gets a controlled error screen
/// instead of silently falling through to the reaction test.
enum TestKind: Equatable {
    case reaction
    case balance
    case memory
    case gait
    case unknown

    init(pendingTest: String) {
        switch pendingTest {
        case "reaction": self = .reaction
        case "gyro", "balance": self = .balance
        case "memory": self = .memory
        case "gait": self = .gait
        default: self = .unknown
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case onboarding
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
    /// Separate from `errorMessage` because the Baseline tab is reachable
    /// alongside every other phase -- if it read the shared `errorMessage`,
    /// an unrelated failure (e.g. a failed session restore) would bleed
    /// onto the Baseline screen as a confusing, unrelated error.
    @Published var baselineErrorMessage: String?
    @Published var isLoading = false
    @Published var session: SessionOut?
    @Published private(set) var reactionBaselineMs: Double?
    @Published private(set) var gyroBaselineScore: Double?
    @Published private(set) var memoryBaselinePercent: Double?
    @Published private(set) var gaitBaselineScore: Double?

    private let api: BuzzBuddyAPIProtocol
    private let persistence: PersistenceStore
    private let locationProvider: LocationProviding
    private var userId: String?
    private var eventId: String?

    init(
        api: BuzzBuddyAPIProtocol = BuzzBuddyAPI(),
        persistence: PersistenceStore = UserDefaultsPersistenceStore(),
        locationProvider: LocationProviding = LocationProvider()
    ) {
        self.api = api
        self.persistence = persistence
        self.locationProvider = locationProvider
        self.userId = persistence.userId
        self.eventId = persistence.eventId
        self.reactionBaselineMs = persistence.reactionBaselineMs
        self.gyroBaselineScore = persistence.gyroBaselineScore
        self.memoryBaselinePercent = persistence.memoryBaselinePercent
        self.gaitBaselineScore = persistence.gaitBaselineScore

        if !persistence.hasCompletedOnboarding {
            self.phase = .onboarding
        } else if persistence.sessionId != nil {
            self.phase = .restoring
        } else {
            self.phase = .readyToStartEvent
        }
    }

    /// Call once at app launch (after the view hierarchy has read the
    /// synchronous initial `phase`). Only does work if a session needs
    /// restoring; otherwise it's a no-op.
    func bootstrap() async {
        guard case .restoring = phase, let sessionId = persistence.sessionId else { return }
        await restoreSession(sessionId: sessionId)
    }

    func completeOnboarding(
        name: String,
        weightKg: Double,
        heightCm: Double,
        bmi: Double,
        ddName: String,
        ddPhone: String
    ) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let contact = DDContactIn(name: ddName, phoneNumber: ddPhone, email: nil)
            let payload = UserCreate(
                name: name, weightKg: weightKg, heightCm: heightCm, bmi: bmi,
                baseline: nil, ddContacts: [contact]
            )
            let user = try await api.createUser(payload)
            userId = user.id
            persistence.userId = user.id
            persistence.hasCompletedOnboarding = true
            errorMessage = nil
            phase = .readyToStartEvent
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Captures or overwrites any of the user's sober baselines from the
    /// Baseline tab, independent of app phase -- unlike onboarding, this
    /// never gates navigation to the rest of the app. Only pass the
    /// baseline(s) actually being (re)captured; omitted ones are left
    /// untouched both locally and on the backend.
    func updateBaseline(
        reactionBaselineMs: Double? = nil,
        gyroBaselineScore: Double? = nil,
        memoryBaselinePercent: Double? = nil,
        gaitBaselineScore: Double? = nil
    ) async {
        guard let userId else { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let payload = BaselineUpdate(
                reactionTimeMs: reactionBaselineMs,
                gyroStabilityScore: gyroBaselineScore,
                memoryRecallPercent: memoryBaselinePercent,
                gaitStabilityScore: gaitBaselineScore
            )
            _ = try await api.updateBaseline(userId: userId, payload)
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
            if let gaitBaselineScore {
                persistence.gaitBaselineScore = gaitBaselineScore
                self.gaitBaselineScore = gaitBaselineScore
            }
            baselineErrorMessage = nil
        } catch {
            baselineErrorMessage = error.localizedDescription
        }
    }

    func startEvent(name: String) async {
        guard let userId else { return }
        guard case .readyToStartEvent = phase, !isLoading else { return }
        phase = .startingEvent
        isLoading = true
        defer { isLoading = false }
        do {
            let event = try await api.createEvent(EventCreate(userId: userId, name: name))
            eventId = event.id
            persistence.eventId = event.id
            let session = try await api.startSession(eventId: event.id)
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

    /// Resubmits the same result that failed, without re-running the test.
    func retrySubmission() async {
        guard case .submissionFailed(let pendingTest, let testType, let rawValue) = phase, !isLoading else { return }
        await performSubmit(pendingTest: pendingTest, testType: testType, rawValue: rawValue)
    }

    private func performSubmit(pendingTest: String, testType: String, rawValue: Double) async {
        guard let session else { return }
        phase = .reviewingTest(pendingTest: pendingTest)
        isLoading = true
        defer { isLoading = false }
        do {
            // Best-effort: a denied/unavailable location just means the DD
            // alert (if the AI escalates) won't include one.
            let coordinate = await locationProvider.currentLocation()
            let updated = try await api.submitTestResult(
                sessionId: session.id,
                TestResultIn(
                    testType: testType,
                    rawValue: rawValue,
                    latitude: coordinate?.latitude,
                    longitude: coordinate?.longitude
                )
            )
            self.session = updated
            persistence.sessionId = updated.id
            errorMessage = nil
            // Deliberately stay on .reviewingTest here rather than advancing --
            // the view reveals the AI's reasoning for this round and waits for
            // the user to tap Continue (see continueAfterReview()) instead of
            // auto-advancing out from under them.
        } catch {
            errorMessage = error.localizedDescription
            phase = .submissionFailed(pendingTest: pendingTest, testType: testType, rawValue: rawValue)
        }
    }

    /// Called once the user has read this round's AI reasoning and taps
    /// Continue on the .reviewingTest screen -- moves on to whatever
    /// `advance(from:)` decides (next test, or verdict).
    func continueAfterReview() {
        guard case .reviewingTest = phase, let session else { return }
        advance(from: session)
    }

    func retryRestore() async {
        guard case .restoreFailed(let sessionId) = phase, !isLoading else { return }
        phase = .restoring
        await restoreSession(sessionId: sessionId)
    }

    /// Explicit, user-initiated abandonment of an unrestorable session --
    /// restoration failures never clear persisted state on their own.
    func discardSession() {
        persistence.sessionId = nil
        session = nil
        errorMessage = nil
        phase = .readyToStartEvent
    }

    private func restoreSession(sessionId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let session = try await api.getSession(sessionId: sessionId)
            self.session = session
            errorMessage = nil
            advance(from: session)
        } catch {
            errorMessage = error.localizedDescription
            phase = .restoreFailed(sessionId: sessionId)
        }
    }

    private func advance(from session: SessionOut) {
        // `status` (clear/mild/severe) is the AI's evolving confidence label,
        // not a lifecycle flag -- it can say "severe" while still wanting a
        // cross-check test before concluding. The session is actually over
        // only once the DD has been notified, or the AI stopped requesting
        // further tests.
        guard !session.notified, let pendingTest = session.pendingTest else {
            phase = .verdict
            return
        }
        if TestKind(pendingTest: pendingTest) == .unknown {
            phase = .unsupportedTest(pendingTest: pendingTest)
        } else {
            phase = .takingTest(pendingTest: pendingTest)
        }
    }
}
