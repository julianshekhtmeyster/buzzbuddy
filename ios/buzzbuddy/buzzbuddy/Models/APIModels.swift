import Foundation

// Mirrors backend/app/schemas.py. Swift camelCase properties map to the
// backend's snake_case JSON via BuzzBuddyAPI's convertToSnakeCase /
// convertFromSnakeCase coding strategies, so no CodingKeys are needed here.

struct DDContactIn: Codable {
    var name: String
    var phoneNumber: String?
    var email: String?
}

struct BaselineIn: Codable {
    var reactionTimeMs: Double
    var gyroStabilityScore: Double
    /// 0...100 percentage, not a 0...1 proportion.
    var memoryRecallPercent: Double
}

/// Partial baseline update for PATCH /users/{id}/baseline -- only set the
/// field(s) actually being (re)captured, e.g. a missing-baseline migration
/// for an existing user only sends `memoryRecallPercent`.
struct BaselineUpdate: Codable {
    var reactionTimeMs: Double?
    var gyroStabilityScore: Double?
    var memoryRecallPercent: Double?
    var gaitStabilityScore: Double?
}

struct UserCreate: Codable {
    var name: String
    var weightKg: Double
    var heightCm: Double
    var bmi: Double
    var baseline: BaselineIn?
    var ddContacts: [DDContactIn]
}

struct UserOut: Codable {
    var id: String
    var name: String
}

struct EventCreate: Codable {
    var userId: String
    var name: String
}

struct EventOut: Codable {
    var id: String
    var userId: String
    var name: String
    var status: String
}

struct TestResultIn: Codable {
    var testType: String
    var rawValue: Double
    var latitude: Double?
    var longitude: Double?
}

struct SessionOut: Codable {
    var id: String
    var eventId: String
    var status: String
    var confidence: Double
    var pendingTest: String?
    var reasoningLog: [String]
    /// The AI's concluding plain-language summary -- one compressed takeaway,
    /// distinct from `reasoningLog`'s per-round trace. Featured on the
    /// verdict screen; nil until the session actually concludes.
    var finalSummary: String?
    var notified: Bool
}

/// Backed by a separate DO agent from the examiner loop -- read-only Q&A
/// about an already-computed session, for the designated driver.
struct DDChatRequest: Codable {
    var question: String
}

struct DDChatResponse: Codable {
    var answer: String
}
