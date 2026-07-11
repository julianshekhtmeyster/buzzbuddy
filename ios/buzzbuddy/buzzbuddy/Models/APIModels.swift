import Foundation

// Mirrors backend/app/schemas.py. Swift camelCase properties map to the
// backend's snake_case JSON through BuzzBuddyAPI's coding strategies.

struct DDContactIn: Codable {
    var name: String
    var phoneNumber: String?
    var email: String?
}

struct DDContactOut: Codable, Identifiable, Hashable {
    var id: String
    var userId: String
    var name: String
    var phoneNumber: String?
    var email: String?
    var inviteCode: String?
    var inviteStatus: String
    var acceptedAt: String?
    var hasRegisteredDevice: Bool
    var smsFallbackEnabled: Bool

    var isAccepted: Bool {
        inviteStatus.lowercased() == "accepted" || acceptedAt != nil
    }

    init(
        id: String,
        userId: String,
        name: String,
        phoneNumber: String? = nil,
        email: String? = nil,
        inviteCode: String? = nil,
        inviteStatus: String = "pending",
        acceptedAt: String? = nil,
        hasRegisteredDevice: Bool = false,
        smsFallbackEnabled: Bool = false
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.phoneNumber = phoneNumber
        self.email = email
        self.inviteCode = inviteCode
        self.inviteStatus = inviteStatus
        self.acceptedAt = acceptedAt
        self.hasRegisteredDevice = hasRegisteredDevice
        self.smsFallbackEnabled = smsFallbackEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, userId, name, phoneNumber, email, inviteCode, inviteStatus
        case acceptedAt, hasRegisteredDevice, smsFallbackEnabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        userId = try values.decodeIfPresent(String.self, forKey: .userId) ?? ""
        name = try values.decode(String.self, forKey: .name)
        phoneNumber = try values.decodeIfPresent(String.self, forKey: .phoneNumber)
        email = try values.decodeIfPresent(String.self, forKey: .email)
        inviteCode = try values.decodeIfPresent(String.self, forKey: .inviteCode)
        inviteStatus = try values.decodeIfPresent(String.self, forKey: .inviteStatus) ?? "pending"
        acceptedAt = try values.decodeIfPresent(String.self, forKey: .acceptedAt)
        hasRegisteredDevice = try values.decodeIfPresent(Bool.self, forKey: .hasRegisteredDevice) ?? false
        smsFallbackEnabled = try values.decodeIfPresent(Bool.self, forKey: .smsFallbackEnabled) ?? false
    }
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
    var ddContacts: [DDContactOut]
    var accessToken: String?

    init(id: String, name: String, ddContacts: [DDContactOut] = [], accessToken: String? = nil) {
        self.id = id
        self.name = name
        self.ddContacts = ddContacts
        self.accessToken = accessToken
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, ddContacts, accessToken
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        ddContacts = try values.decodeIfPresent([DDContactOut].self, forKey: .ddContacts) ?? []
        accessToken = try values.decodeIfPresent(String.self, forKey: .accessToken)
    }
}

struct EventCreate: Codable {
    var userId: String
    var name: String
    var selectedContactId: String?
}

struct EventOut: Codable {
    var id: String
    var userId: String
    var name: String
    var status: String
    var selectedContactId: String?
    var selectedContact: DDContactOut?
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
    var notified: Bool
    var notificationStatus: String?
    var notificationAttemptId: String?
    var selectedContact: DDContactOut?

    init(
        id: String,
        eventId: String,
        status: String,
        confidence: Double,
        pendingTest: String?,
        reasoningLog: [String],
        notified: Bool,
        notificationStatus: String? = nil,
        notificationAttemptId: String? = nil,
        selectedContact: DDContactOut? = nil
    ) {
        self.id = id
        self.eventId = eventId
        self.status = status
        self.confidence = confidence
        self.pendingTest = pendingTest
        self.reasoningLog = reasoningLog
        self.notified = notified
        self.notificationStatus = notificationStatus
        self.notificationAttemptId = notificationAttemptId
        self.selectedContact = selectedContact
    }

    private enum CodingKeys: String, CodingKey {
        case id, eventId, status, confidence, pendingTest, reasoningLog, notified
        case notificationStatus, notificationAttemptId, selectedContact
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        eventId = try values.decode(String.self, forKey: .eventId)
        status = try values.decode(String.self, forKey: .status)
        confidence = try values.decode(Double.self, forKey: .confidence)
        pendingTest = try values.decodeIfPresent(String.self, forKey: .pendingTest)
        reasoningLog = try values.decodeIfPresent([String].self, forKey: .reasoningLog) ?? []
        notified = try values.decodeIfPresent(Bool.self, forKey: .notified) ?? false
        notificationStatus = try values.decodeIfPresent(String.self, forKey: .notificationStatus)
        notificationAttemptId = try values.decodeIfPresent(String.self, forKey: .notificationAttemptId)
        selectedContact = try values.decodeIfPresent(DDContactOut.self, forKey: .selectedContact)
    }
}

struct AcceptInviteIn: Codable {
    var inviteCode: String
    var deviceToken: String?
    var environment: String
    var smsConsent: Bool
    var confirmedPhoneNumber: String?
}

struct ContactAcceptanceOut: Decodable {
    var contact: DDContactOut
    var accessToken: String?

    private enum CodingKeys: String, CodingKey {
        case contact, accessToken
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try values.decodeIfPresent(String.self, forKey: .accessToken)
        if let nested = try values.decodeIfPresent(DDContactOut.self, forKey: .contact) {
            contact = nested
        } else {
            // Tolerate early servers that returned the contact fields at the top level.
            contact = try DDContactOut(from: decoder)
        }
    }
}

struct ContactDeviceIn: Codable {
    var deviceToken: String
    var environment: String
}

struct ContactDeviceOut: Codable, Identifiable {
    var id: String
    var contactId: String
    var environment: String
    var active: Bool
    var createdAt: String?
    var updatedAt: String?
}

struct NotificationAcknowledgementIn: Codable {
    var response: String
}

struct NotificationAttemptOut: Codable, Identifiable, Hashable {
    var id: String
    var sessionId: String
    var contactId: String
    var channel: String
    var status: String
    var providerStatus: String?
    var providerMessageId: String?
    var errorCode: String?
    var errorMessage: String?
    var message: String
    var locationUrl: String?
    var createdAt: String?
    var sentAt: String?
    var deliveredAt: String?
    var acknowledgedAt: String?
    var acknowledgementResponse: String?

    var isAcknowledged: Bool {
        acknowledgedAt != nil || status.lowercased() == "acknowledged"
    }
}
