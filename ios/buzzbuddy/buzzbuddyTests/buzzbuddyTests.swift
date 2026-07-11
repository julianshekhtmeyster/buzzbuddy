//
//  buzzbuddyTests.swift
//  buzzbuddyTests
//
//  Created by Max DeWeese on 7/10/26.
//

import Foundation
import Testing
@testable import buzzbuddy

struct buzzbuddyTests {

    @Test func reactionMeanDiscardsWarmup() {
        let result = TestEngine.Reaction.meanMilliseconds(from: [999, 200, 300, 400])
        #expect(result == 300)
    }

    @Test func gyroReturnsPopulationVariance() {
        let result = TestEngine.Gyro.rotationRateVariance(from: [1, 2, 3])
        #expect(abs((result ?? 0) - (2.0 / 3.0)) < 0.000_001)
    }

    @Test func memoryScoresDigitsByPosition() {
        let result = TestEngine.Memory.accuracyPercentage(
            expected: ["1234", "567890"],
            entered: ["1239", "567000"]
        )
        #expect(result == 70)
    }

    @Test func phoneNumberNormalizationKeepsE164Format() {
        #expect(PhoneNumberNormalizer.normalized("+1 (415) 555-0123") == "+14155550123")
        #expect(PhoneNumberNormalizer.isValid("+44 20 7946 0958"))
        #expect(!PhoneNumberNormalizer.isValid("555-0123"))
    }

    @Test func inviteAcceptanceDecodesCredentialAndContact() throws {
        let json = #"""
        {
          "contact": {
            "id": "contact-1",
            "user_id": "user-1",
            "name": "Taylor",
            "phone_number": "+14155550123",
            "invite_status": "accepted",
            "has_registered_device": true,
            "sms_fallback_enabled": true
          },
          "access_token": "opaque-contact-token"
        }
        """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ContactAcceptanceOut.self, from: Data(json.utf8))

        #expect(response.contact.id == "contact-1")
        #expect(response.contact.isAccepted)
        #expect(response.contact.smsFallbackEnabled)
        #expect(response.accessToken == "opaque-contact-token")
    }

    @Test func userCreationDecodesOwnerCredential() throws {
        let json = #"{"id":"user-1","name":"Alex","dd_contacts":[],"access_token":"owner-secret"}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let user = try decoder.decode(UserOut.self, from: Data(json.utf8))
        #expect(user.accessToken == "owner-secret")
    }

    @Test func manualSafetyMessageIncludesOwnerAndOptionalLocation() {
        let message = SafetyFallbackMessage.make(
            ownerName: " Justin ",
            locationURL: "https://maps.apple.com/?ll=37.87,-122.26"
        )
        #expect(message.contains("Justin may need help"))
        #expect(message.contains("Last shared location:"))

        let privateMessage = SafetyFallbackMessage.make(ownerName: nil, locationURL: nil)
        #expect(privateMessage.contains("Your BuzzBuddy friend"))
        #expect(!privateMessage.contains("Last shared location:"))
    }

    @Test func sessionDecodesExplicitNotificationStatus() throws {
        let json = #"""
        {
          "id": "session-1",
          "event_id": "event-1",
          "status": "SEVERELY_IMPAIRED",
          "confidence": 0.91,
          "pending_test": null,
          "reasoning_log": [],
          "notified": false,
          "notification_status": "accepted",
          "notification_attempt_id": "attempt-1"
        }
        """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let session = try decoder.decode(SessionOut.self, from: Data(json.utf8))

        #expect(session.notificationStatus == "accepted")
        #expect(session.notificationAttemptId == "attempt-1")
        #expect(session.selectedContact == nil)
    }

}
