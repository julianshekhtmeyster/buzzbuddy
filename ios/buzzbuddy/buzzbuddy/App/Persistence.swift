import Foundation

/// What AppState needs to survive relaunch: identifiers for the in-progress
/// event/session and the onboarding/baseline values the UI reads back. Never
/// stores API secrets -- those live in the backend only.
protocol PersistenceStore: AnyObject {
    var userId: String? { get set }
    var eventId: String? { get set }
    var sessionId: String? { get set }
    var hasCompletedOnboarding: Bool { get set }
    var reactionBaselineMs: Double? { get set }
    var gyroBaselineScore: Double? { get set }
}

final class UserDefaultsPersistenceStore: PersistenceStore {
    private enum Key {
        static let userId = "buzzbuddy.userId"
        static let eventId = "buzzbuddy.eventId"
        static let sessionId = "buzzbuddy.sessionId"
        static let hasCompletedOnboarding = "buzzbuddy.hasCompletedOnboarding"
        static let reactionBaselineMs = "buzzbuddy.reactionBaselineMs"
        static let gyroBaselineScore = "buzzbuddy.gyroBaselineScore"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var userId: String? {
        get { defaults.string(forKey: Key.userId) }
        set { defaults.set(newValue, forKey: Key.userId) }
    }

    var eventId: String? {
        get { defaults.string(forKey: Key.eventId) }
        set { defaults.set(newValue, forKey: Key.eventId) }
    }

    var sessionId: String? {
        get { defaults.string(forKey: Key.sessionId) }
        set { defaults.set(newValue, forKey: Key.sessionId) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    var reactionBaselineMs: Double? {
        get { defaults.object(forKey: Key.reactionBaselineMs) as? Double }
        set { defaults.set(newValue, forKey: Key.reactionBaselineMs) }
    }

    var gyroBaselineScore: Double? {
        get { defaults.object(forKey: Key.gyroBaselineScore) as? Double }
        set { defaults.set(newValue, forKey: Key.gyroBaselineScore) }
    }
}
