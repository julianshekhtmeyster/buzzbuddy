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
    var updateBaselineResult: Result<UserOut, Error> = .success(UserOut(id: "user-1", name: "Test"))
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
    private(set) var createUserCalled = false
    private(set) var updateBaselineCalledWith: (userId: String, payload: BaselineUpdate)?

    func createUser(_ payload: UserCreate) async throws -> UserOut {
        createUserCalled = true
        return try createUserResult.get()
    }
    func updateBaseline(userId: String, _ payload: BaselineUpdate) async throws -> UserOut {
        updateBaselineCalledWith = (userId, payload)
        return try updateBaselineResult.get()
    }
    func createEvent(_ payload: EventCreate) async throws -> EventOut { try createEventResult.get() }
    func startSession(eventId: String) async throws -> SessionOut { try startSessionResult.get() }
    func submitTestResult(sessionId: String, _ payload: TestResultIn) async throws -> SessionOut {
        try submitTestResultResult.get()
    }
    func getSession(sessionId: String) async throws -> SessionOut {
        getSessionCalledWith = sessionId
        return try getSessionResult.get()
    }
    var ddChatResult: Result<DDChatResponse, Error> = .success(DDChatResponse(answer: "Test answer"))
    func sendDDChatMessage(sessionId: String, question: String) async throws -> DDChatResponse {
        try ddChatResult.get()
    }
}

private final class InMemoryPersistenceStore: PersistenceStore {
    var userId: String?
    var eventId: String?
    var sessionId: String?
    var hasCompletedOnboarding: Bool = false
    var reactionBaselineMs: Double?
    var gyroBaselineScore: Double?
    var memoryBaselinePercent: Double?
}

/// A fully-onboarded user with all three baselines already on file --
/// the common starting point for tests that aren't about onboarding or
/// baseline migration themselves.
private func fullyOnboardedPersistence(sessionId: String? = nil) -> InMemoryPersistenceStore {
    let store = InMemoryPersistenceStore()
    store.hasCompletedOnboarding = true
    store.userId = "user-1"
    store.reactionBaselineMs = 250
    store.gyroBaselineScore = 0.9
    store.memoryBaselinePercent = 80
    store.sessionId = sessionId
    return store
}

/// Never touches real CoreLocation -- a live CLLocationManager can block a
/// headless test run on a permission prompt that never resolves.
private struct NoOpLocationProvider: LocationProviding {
    func currentLocation() async -> CLLocationCoordinate2D? { nil }
}

// MARK: - AppState phase tests

@MainActor
struct AppStatePhaseTests {

    @Test func newUserWithNoStateEntersOnboarding() {
        let appState = AppState(
            api: MockBuzzBuddyAPI(),
            persistence: InMemoryPersistenceStore(),
            locationProvider: NoOpLocationProvider()
        )
        #expect(appState.phase == .onboarding)
    }

    @Test func existingUserWithAllBaselinesEntersReadyToStartEvent() {
        let appState = AppState(
            api: MockBuzzBuddyAPI(),
            persistence: fullyOnboardedPersistence(),
            locationProvider: NoOpLocationProvider()
        )
        #expect(appState.phase == .readyToStartEvent)
    }

    @Test func existingUserMissingBaselinesStillEntersReadyToStartEvent() {
        // Missing baselines no longer gate navigation -- they're managed
        // from the Baseline tab, not blocked behind a dedicated phase.
        let persistence = fullyOnboardedPersistence()
        persistence.memoryBaselinePercent = nil
        persistence.reactionBaselineMs = nil
        let appState = AppState(api: MockBuzzBuddyAPI(), persistence: persistence, locationProvider: NoOpLocationProvider())
        #expect(appState.phase == .readyToStartEvent)
    }

    @Test func existingUserWithActiveSessionEntersRestoring() {
        let persistence = fullyOnboardedPersistence(sessionId: "session-1")
        let appState = AppState(api: MockBuzzBuddyAPI(), persistence: persistence, locationProvider: NoOpLocationProvider())
        #expect(appState.phase == .restoring)
    }
}

// MARK: - Onboarding / baseline AppState tests

@MainActor
struct AppStateOnboardingTests {

    @Test func onboardingSuccessPersistsUserId() async {
        let api = MockBuzzBuddyAPI()
        let persistence = InMemoryPersistenceStore()
        let appState = AppState(api: api, persistence: persistence, locationProvider: NoOpLocationProvider())

        await appState.completeOnboarding(
            name: "Justin", weightKg: 70, heightCm: 175, bmi: 22.9,
            ddName: "DD", ddPhone: "555-0100"
        )

        #expect(persistence.userId == "user-1")
        #expect(persistence.hasCompletedOnboarding == true)
        #expect(appState.phase == .readyToStartEvent)
    }

    @Test func updateBaselineUpdatesExistingUserNotCreateUser() async {
        let api = MockBuzzBuddyAPI()
        let persistence = fullyOnboardedPersistence()
        persistence.memoryBaselinePercent = nil
        let appState = AppState(api: api, persistence: persistence, locationProvider: NoOpLocationProvider())
        #expect(appState.phase == .readyToStartEvent)

        await appState.updateBaseline(memoryBaselinePercent: 80)

        #expect(api.createUserCalled == false)
        #expect(api.updateBaselineCalledWith?.userId == "user-1")
        #expect(api.updateBaselineCalledWith?.payload.memoryRecallPercent == 80)
        #expect(api.updateBaselineCalledWith?.payload.reactionTimeMs == nil)
        #expect(persistence.memoryBaselinePercent == 80)
        #expect(appState.phase == .readyToStartEvent)
    }

    @Test func updateBaselineFailurePreservesState() async {
        let api = MockBuzzBuddyAPI()
        api.updateBaselineResult = .failure(MockError())
        let persistence = fullyOnboardedPersistence()
        persistence.memoryBaselinePercent = nil
        let appState = AppState(api: api, persistence: persistence, locationProvider: NoOpLocationProvider())

        await appState.updateBaseline(memoryBaselinePercent: 80)

        #expect(appState.phase == .readyToStartEvent)
        #expect(appState.baselineErrorMessage != nil)
        // Nothing was persisted since the backend call failed.
        #expect(persistence.memoryBaselinePercent == nil)
    }
}

// MARK: - Session-flow AppState tests

@MainActor
struct AppStateSessionTests {

    @Test func startingSessionWithReactionOpensReaction() async {
        let api = MockBuzzBuddyAPI()
        api.startSessionResult = .success(
            SessionOut(id: "session-1", eventId: "event-1", status: "CLEAR", confidence: 0,
                       pendingTest: "reaction", reasoningLog: [], notified: false)
        )
        let appState = AppState(api: api, persistence: fullyOnboardedPersistence(), locationProvider: NoOpLocationProvider())

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
        let appState = AppState(api: api, persistence: fullyOnboardedPersistence(), locationProvider: NoOpLocationProvider())

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
        let appState = AppState(api: api, persistence: fullyOnboardedPersistence(), locationProvider: NoOpLocationProvider())

        await appState.startEvent(name: "Tonight")

        #expect(appState.phase == .verdict)
    }

    @Test func notifiedAdvancesToVerdict() async {
        let api = MockBuzzBuddyAPI()
        api.startSessionResult = .success(
            SessionOut(id: "session-1", eventId: "event-1", status: "SEVERELY_IMPAIRED", confidence: 0.95,
                       pendingTest: "reaction", reasoningLog: [], notified: true)
        )
        let appState = AppState(api: api, persistence: fullyOnboardedPersistence(), locationProvider: NoOpLocationProvider())

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
        let appState = AppState(api: api, persistence: fullyOnboardedPersistence(), locationProvider: NoOpLocationProvider())

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
        let persistence = fullyOnboardedPersistence(sessionId: "session-1")
        persistence.eventId = "event-1"

        let appState = AppState(api: api, persistence: persistence, locationProvider: NoOpLocationProvider())
        #expect(appState.phase == .restoring)

        await appState.bootstrap()

        #expect(api.getSessionCalledWith == "session-1")
        #expect(appState.phase == .takingTest(pendingTest: "gyro"))
    }
}

// MARK: - Memory-recall scoring tests

struct MemoryRecallScoringTests {

    @Test func inputCannotExceedSequenceLength() {
        #expect(MemoryRecallScoring.canAppendDigit(currentInputCount: 4, sequenceLength: 5) == true)
        #expect(MemoryRecallScoring.canAppendDigit(currentInputCount: 5, sequenceLength: 5) == false)
    }

    @Test func submitRequiresExactlyExpectedDigitCount() {
        #expect(MemoryRecallScoring.canSubmit(inputCount: 4, sequenceLength: 5) == false)
        #expect(MemoryRecallScoring.canSubmit(inputCount: 5, sequenceLength: 5) == true)
        #expect(MemoryRecallScoring.canSubmit(inputCount: 6, sequenceLength: 5) == false)
    }

    @Test func extraOrMismatchedDigitsCannotScore100Percent() {
        // A same-length, all-wrong entry scores 0, not a truncated match.
        #expect(MemoryRecallScoring.accuracy(sequence: [1, 2, 3, 4, 5], input: [9, 9, 9, 9, 9]) == 0)
        // A length mismatch (the original `zip`-truncation bug) must never
        // score 100% by silently dropping the extra/incorrect entries.
        let mismatched = MemoryRecallScoring.accuracy(sequence: [1, 2, 3, 4, 5], input: [1, 2, 3, 4, 5, 9])
        #expect(mismatched != 100)
        #expect(mismatched == 0)
    }

    @Test func exactMatchScores100Percent() {
        #expect(MemoryRecallScoring.accuracy(sequence: [1, 2, 3, 4, 5], input: [1, 2, 3, 4, 5]) == 100)
    }

    @Test func threeRoundBaselineReturnsCorrectAverage() {
        #expect(MemoryBaselineScoring.average(of: [100, 80, 60]) == 80)
        #expect(MemoryBaselineScoring.average(of: [100, 100, 100]) == 100)
    }
}

// MARK: - Onboarding validation tests

struct OnboardingValidationTests {

    @Test func invalidWeightDisablesSubmission() {
        #expect(OnboardingValidation.isValidWeightLbs("0") == false)
        #expect(OnboardingValidation.isValidWeightLbs("-10") == false)
        #expect(OnboardingValidation.isValidWeightLbs("69") == false)
        #expect(OnboardingValidation.isValidWeightLbs("701") == false)
        #expect(OnboardingValidation.isValidWeightLbs("abc") == false)
        #expect(OnboardingValidation.isValidWeightLbs("150") == true)
    }

    @Test func invalidHeightDisablesSubmission() {
        // 0 ft 0 in -- below range.
        #expect(OnboardingValidation.isValidHeight(feet: "0", inches: "0") == false)
        // Negative feet is nonsensical.
        #expect(OnboardingValidation.isValidHeight(feet: "-5", inches: "0") == false)
        // 2 ft 11 in = 35 in -- just under range.
        #expect(OnboardingValidation.isValidHeight(feet: "2", inches: "11") == false)
        // 8 ft 1 in = 97 in -- just over range.
        #expect(OnboardingValidation.isValidHeight(feet: "8", inches: "1") == false)
        // A raw value like "510" typed into the inches field (a classic
        // 5'10" typo) must be rejected -- inches must be 0..<12.
        #expect(OnboardingValidation.isValidHeight(feet: "", inches: "510") == false)
        // 5 ft 10 in = 70 in -- comfortably in range.
        #expect(OnboardingValidation.isValidHeight(feet: "5", inches: "10") == true)
        // Blank inches defaults to 0.
        #expect(OnboardingValidation.isValidHeight(feet: "6", inches: "") == true)
    }

    @Test func emptyOrWhitespaceDisablesSubmission() {
        #expect(OnboardingValidation.isNonEmpty("") == false)
        #expect(OnboardingValidation.isNonEmpty("   ") == false)
        #expect(OnboardingValidation.isNonEmpty("555-0100") == true)
    }
}
