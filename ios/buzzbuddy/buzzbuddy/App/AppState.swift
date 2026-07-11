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

    private let api = BuzzBuddyAPI()
    private var userId: String?
    private var eventId: String?

    func completeOnboarding(
        name: String,
        weightKg: Double,
        heightCm: Double,
        bmi: Double,
        reactionBaselineMs: Double,
        gyroBaselineScore: Double,
        ddName: String,
        ddPhone: String
    ) async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Memory baseline is a placeholder until a memory-recall test is
            // built — reaction and gyro/balance are both real now.
            let baseline = BaselineIn(
                reactionTimeMs: reactionBaselineMs,
                gyroStabilityScore: gyroBaselineScore,
                memoryRecallScore: 1.0
            )
            let contact = DDContactIn(name: ddName, phoneNumber: ddPhone, email: nil)
            let payload = UserCreate(
                name: name, weightKg: weightKg, heightCm: heightCm, bmi: bmi,
                baseline: baseline, ddContacts: [contact]
            )
            let user = try await api.createUser(payload)
            userId = user.id
            errorMessage = nil
            phase = .readyToStartEvent
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startEvent(name: String) async {
        guard let userId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let event = try await api.createEvent(EventCreate(userId: userId, name: name))
            eventId = event.id
            let session = try await api.startSession(eventId: event.id)
            self.session = session
            errorMessage = nil
            advance(from: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitTestResult(testType: String, rawValue: Double) async {
        guard let session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let updated = try await api.submitTestResult(
                sessionId: session.id,
                TestResultIn(testType: testType, rawValue: rawValue)
            )
            self.session = updated
            errorMessage = nil
            advance(from: updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func advance(from session: SessionOut) {
        if session.status != "in_progress" {
            phase = .verdict
        } else {
            phase = .takingTest(pendingTest: session.pendingTest ?? "reaction")
        }
    }
}
