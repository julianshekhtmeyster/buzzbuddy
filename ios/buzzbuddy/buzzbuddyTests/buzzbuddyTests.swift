//
//  buzzbuddyTests.swift
//  buzzbuddyTests
//
//  Created by Max DeWeese on 7/10/26.
//

import CoreLocation
import Testing
@testable import buzzbuddy

struct buzzbuddyTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

// MARK: - Test doubles

private struct MockError: Error {}

private final class MockBuzzBuddyAPI: BuzzBuddyAPIProtocol {
    var createUserResult: Result<UserOut, Error> = .success(UserOut(id: "user-1", name: "Test"))
    var createEventResult: Result<EventOut, Error> = .success(
        EventOut(id: "event-1", userId: "user-1", name: "Tonight", status: "active")
    )
    var startSessionResult: Result<SessionOut, Error> = .success(
        SessionOut(id: "session-1", eventId: "event-1", status: "CLEAR", confidence: 0,
                   pendingTest: "reaction", reasoningLog: [], notified: false)
    )
    var submitTestResultResult: Result<SessionOut, Error> = .success(
        SessionOut(id: "session-1", eventId: "event-1", status: "CLEAR", confidence: 0,
                   pendingTest: nil, reasoningLog: [], notified: false)
    )
    var getSessionResult: Result<SessionOut, Error> = .success(
        SessionOut(id: "session-1", eventId: "event-1", status: "CLEAR", confidence: 0,
                   pendingTest: "gyro", reasoningLog: [], notified: false)
    )
    private(set) var getSessionCalledWith: String?

    func createUser(_ payload: UserCreate) async throws -> UserOut { try createUserResult.get() }
    func createEvent(_ payload: EventCreate) async throws -> EventOut { try createEventResult.get() }
    func startSession(eventId: String) async throws -> SessionOut { try startSessionResult.get() }
    func submitTestResult(sessionId: String, _ payload: TestResultIn) async throws -> SessionOut {
        try submitTestResultResult.get()
    }
    func getSession(sessionId: String) async throws -> SessionOut {
        getSessionCalledWith = sessionId
        return try getSessionResult.get()
    }
}

private final class InMemoryPersistenceStore: PersistenceStore {
    var userId: String?
    var eventId: String?
    var sessionId: String?
    var hasCompletedOnboarding: Bool = false
    var reactionBaselineMs: Double?
    var gyroBaselineScore: Double?
}

/// Never touches real CoreLocation -- a live CLLocationManager can block a
/// headless test run on a permission prompt that never resolves.
private struct NoOpLocationProvider: LocationProviding {
    func currentLocation() async -> CLLocationCoordinate2D? { nil }
}

// MARK: - AppState tests

@MainActor
struct AppStateTests {

    @Test func onboardingSuccessPersistsUserId() async {
        let api = MockBuzzBuddyAPI()
        let persistence = InMemoryPersistenceStore()
        let appState = AppState(api: api, persistence: persistence, locationProvider: NoOpLocationProvider())

        await appState.completeOnboarding(
            name: "Justin", weightKg: 70, heightCm: 175, bmi: 22.9,
            reactionBaselineMs: 250, gyroBaselineScore: 0.9,
            ddName: "DD", ddPhone: "555-0100"
        )

        #expect(persistence.userId == "user-1")
        #expect(persistence.hasCompletedOnboarding == true)
        #expect(appState.phase == .readyToStartEvent)
    }

    @Test func startingSessionWithReactionOpensReaction() async {
        let api = MockBuzzBuddyAPI()
        api.startSessionResult = .success(
            SessionOut(id: "session-1", eventId: "event-1", status: "CLEAR", confidence: 0,
                       pendingTest: "reaction", reasoningLog: [], notified: false)
        )
        let persistence = InMemoryPersistenceStore()
        persistence.hasCompletedOnboarding = true
        persistence.userId = "user-1"
        let appState = AppState(api: api, persistence: persistence, locationProvider: NoOpLocationProvider())

        await appState.startEvent(name: "Tonight")

        #expect(appState.phase == .takingTest(pendingTest: "reaction"))
    }

    @Test func memoryResponseAdvancesToMemory() async {
        let api = MockBuzzBuddyAPI()
        api.startSessionResult = .success(
            SessionOut(id: "session-1", eventId: "event-1", status: "CLEAR", confidence: 0,
                       pendingTest: "reaction", reasoningLog: [], notified: false)
        )
        api.submitTestResultResult = .success(
            SessionOut(id: "session-1", eventId: "event-1", status: "MILDLY_IMPAIRED", confidence: 0.4,
                       pendingTest: "memory", reasoningLog: [], notified: false)
        )
        let persistence = InMemoryPersistenceStore()
        persistence.hasCompletedOnboarding = true
        persistence.userId = "user-1"
        let appState = AppState(api: api, persistence: persistence, locationProvider: NoOpLocationProvider())

        await appState.startEvent(name: "Tonight")
        await appState.submitTestResult(testType: "reaction", rawValue: 240)

        #expect(appState.phase == .takingTest(pendingTest: "memory"))
    }

    @Test("gyro and balance both route to the balance test kind", arguments: ["gyro", "balance"])
    func gyroAndBalanceRouteToBalance(pendingTest: String) {
        #expect(TestKind(pendingTest: pendingTest) == .balance)
    }

    @Test func nilPendingTestAdvancesToVerdict() async {
        let api = MockBuzzBuddyAPI()
        api.startSessionResult = .success(
            SessionOut(id: "session-1", eventId: "event-1", status: "CLEAR", confidence: 0.9,
                       pendingTest: nil, reasoningLog: [], notified: false)
        )
        let persistence = InMemoryPersistenceStore()
        persistence.hasCompletedOnboarding = true
        persistence.userId = "user-1"
        let appState = AppState(api: api, persistence: persistence, locationProvider: NoOpLocationProvider())

        await appState.startEvent(name: "Tonight")

        #expect(appState.phase == .verdict)
    }

    @Test func notifiedAdvancesToVerdict() async {
        let api = MockBuzzBuddyAPI()
        api.startSessionResult = .success(
            SessionOut(id: "session-1", eventId: "event-1", status: "SEVERELY_IMPAIRED", confidence: 0.95,
                       pendingTest: "reaction", reasoningLog: [], notified: true)
        )
        let persistence = InMemoryPersistenceStore()
        persistence.hasCompletedOnboarding = true
        persistence.userId = "user-1"
        let appState = AppState(api: api, persistence: persistence, locationProvider: NoOpLocationProvider())

        await appState.startEvent(name: "Tonight")

        #expect(appState.phase == .verdict)
    }

    @Test func failedSubmissionPreservesPendingTestAndExposesRetry() async {
        let api = MockBuzzBuddyAPI()
        api.startSessionResult = .success(
            SessionOut(id: "session-1", eventId: "event-1", status: "CLEAR", confidence: 0,
                       pendingTest: "reaction", reasoningLog: [], notified: false)
        )
        api.submitTestResultResult = .failure(MockError())
        let persistence = InMemoryPersistenceStore()
        persistence.hasCompletedOnboarding = true
        persistence.userId = "user-1"
        let appState = AppState(api: api, persistence: persistence, locationProvider: NoOpLocationProvider())

        await appState.startEvent(name: "Tonight")
        await appState.submitTestResult(testType: "reaction", rawValue: 240)

        #expect(appState.phase == .submissionFailed(pendingTest: "reaction", testType: "reaction", rawValue: 240))
        #expect(appState.errorMessage != nil)

        // Retry should re-attempt without needing the test re-run.
        api.submitTestResultResult = .success(
            SessionOut(id: "session-1", eventId: "event-1", status: "CLEAR", confidence: 0,
                       pendingTest: nil, reasoningLog: [], notified: false)
        )
        await appState.retrySubmission()

        #expect(appState.phase == .verdict)
    }

    @Test func restoredSessionCallsGetSessionAndReconstructsPhase() async {
        let api = MockBuzzBuddyAPI()
        api.getSessionResult = .success(
            SessionOut(id: "session-1", eventId: "event-1", status: "CLEAR", confidence: 0.2,
                       pendingTest: "gyro", reasoningLog: [], notified: false)
        )
        let persistence = InMemoryPersistenceStore()
        persistence.hasCompletedOnboarding = true
        persistence.userId = "user-1"
        persistence.eventId = "event-1"
        persistence.sessionId = "session-1"

        let appState = AppState(api: api, persistence: persistence, locationProvider: NoOpLocationProvider())
        #expect(appState.phase == .restoring)

        await appState.bootstrap()

        #expect(api.getSessionCalledWith == "session-1")
        #expect(appState.phase == .takingTest(pendingTest: "gyro"))
    }
}
