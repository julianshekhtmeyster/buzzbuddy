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
    var memoryRecallScore: Double
}

struct UserCreate: Codable {
    var name: String
    var weightKg: Double
    var heightCm: Double
    var bmi: Double
    var baseline: BaselineIn
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
}

struct SessionOut: Codable {
    var id: String
    var eventId: String
    var status: String
    var confidence: Double
    var pendingTest: String?
    var reasoningLog: [String]
    var notified: Bool
}
