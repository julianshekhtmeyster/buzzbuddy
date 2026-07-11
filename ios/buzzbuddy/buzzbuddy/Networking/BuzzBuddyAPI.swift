import Foundation

enum APIError: LocalizedError {
    case invalidConfiguration(String)
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): return message
        case .invalidResponse: return "Invalid response from server"
        case .server(let message): return message
        }
    }
}

protocol BuzzBuddyAPIProtocol {
    func createUser(_ payload: UserCreate) async throws -> UserOut
    func updateBaseline(userId: String, _ payload: BaselineUpdate, bearerToken: String) async throws -> UserOut
    func getContacts(userId: String, bearerToken: String) async throws -> [DDContactOut]
    func createEvent(_ payload: EventCreate, bearerToken: String) async throws -> EventOut
    func startSession(eventId: String, bearerToken: String) async throws -> SessionOut
    func submitTestResult(sessionId: String, _ payload: TestResultIn, bearerToken: String) async throws -> SessionOut
    func getSession(sessionId: String, bearerToken: String) async throws -> SessionOut
    func reissueInvite(contactId: String, bearerToken: String) async throws -> DDContactOut
    func requestSMSFallback(sessionId: String, bearerToken: String) async throws -> SessionOut
}

enum APIConfiguration {
    static let environmentKey = "BUZZBUDDY_API_BASE_URL"
    static let infoPlistKey = "BuzzBuddyAPIBaseURL"

    static func resolveBaseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> Result<URL, APIError> {
        if let value = environment[environmentKey], !value.isEmpty {
            return validate(value)
        }
        if let value = infoDictionary?[infoPlistKey] as? String,
           !value.isEmpty,
           !value.contains("$(") {
            return validate(value)
        }
#if DEBUG
        return validate("http://127.0.0.1:8000")
#else
        return .failure(.invalidConfiguration(
            "Set BUZZBUDDY_API_BASE_URL to the deployed HTTPS API URL."
        ))
#endif
    }

    private static func validate(_ value: String) -> Result<URL, APIError> {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return .failure(.invalidConfiguration(
                "Invalid backend URL; it must begin with http:// or https://."
            ))
        }
#if !DEBUG
        guard scheme == "https" else {
            return .failure(.invalidConfiguration("Production BuzzBuddy API URLs must use HTTPS."))
        }
#endif
        return .success(url)
    }
}

final class BuzzBuddyAPI: BuzzBuddyAPIProtocol {
    private let baseURLResult: Result<URL, APIError>

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) {
        baseURLResult = APIConfiguration.resolveBaseURL(
            environment: environment,
            infoDictionary: infoDictionary
        )
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private func requestURL(for path: String) throws -> URL {
        try baseURLResult.get().appendingPathComponent(
            path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        )
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(Self.serverMessage(from: data, statusCode: http.statusCode))
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.server("The server returned an unexpected response. \(error.localizedDescription)")
        }
    }

    private static func serverMessage(from data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = json["detail"] as? String { return detail }
            if let message = json["message"] as? String { return message }
        }
        return String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
    }

    private func send<Response: Decodable>(
        _ path: String,
        method: String,
        bearerToken: String? = nil
    ) async throws -> Response {
        var request = URLRequest(url: try requestURL(for: path))
        request.httpMethod = method
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        return try await perform(request)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ path: String,
        method: String = "POST",
        body: Body,
        bearerToken: String? = nil
    ) async throws -> Response {
        var request = URLRequest(url: try requestURL(for: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func createUser(_ payload: UserCreate) async throws -> UserOut {
        try await send("/users", body: payload)
    }

    func updateBaseline(
        userId: String,
        _ payload: BaselineUpdate,
        bearerToken: String
    ) async throws -> UserOut {
        try await send(
            "/users/\(userId)/baseline",
            method: "PATCH",
            body: payload,
            bearerToken: bearerToken
        )
    }

    func getContacts(userId: String, bearerToken: String) async throws -> [DDContactOut] {
        try await send("/users/\(userId)/contacts", method: "GET", bearerToken: bearerToken)
    }

    func createEvent(_ payload: EventCreate, bearerToken: String) async throws -> EventOut {
        try await send("/events", body: payload, bearerToken: bearerToken)
    }

    func startSession(eventId: String, bearerToken: String) async throws -> SessionOut {
        try await send("/events/\(eventId)/sessions", method: "POST", bearerToken: bearerToken)
    }

    func submitTestResult(
        sessionId: String,
        _ payload: TestResultIn,
        bearerToken: String
    ) async throws -> SessionOut {
        try await send(
            "/sessions/\(sessionId)/test-results",
            body: payload,
            bearerToken: bearerToken
        )
    }

    func getSession(sessionId: String, bearerToken: String) async throws -> SessionOut {
        try await send("/sessions/\(sessionId)", method: "GET", bearerToken: bearerToken)
    }

    func reissueInvite(contactId: String, bearerToken: String) async throws -> DDContactOut {
        try await send("/contacts/\(contactId)/invite", method: "POST", bearerToken: bearerToken)
    }

    func requestSMSFallback(sessionId: String, bearerToken: String) async throws -> SessionOut {
        try await send(
            "/sessions/\(sessionId)/notifications/fallback",
            method: "POST",
            bearerToken: bearerToken
        )
    }

    func acceptContactInvite(_ payload: AcceptInviteIn) async throws -> ContactAcceptanceOut {
        try await send("/contacts/accept", body: payload)
    }

    func registerDevice(
        contactId: String,
        payload: ContactDeviceIn,
        bearerToken: String
    ) async throws -> ContactDeviceOut {
        try await send(
            "/contacts/\(contactId)/devices",
            body: payload,
            bearerToken: bearerToken
        )
    }

    func getNotifications(
        contactId: String,
        bearerToken: String
    ) async throws -> [NotificationAttemptOut] {
        try await send(
            "/contacts/\(contactId)/notifications",
            method: "GET",
            bearerToken: bearerToken
        )
    }

    func acknowledgeNotification(
        attemptId: String,
        response: String,
        bearerToken: String
    ) async throws -> NotificationAttemptOut {
        try await send(
            "/notifications/\(attemptId)/acknowledge",
            body: NotificationAcknowledgementIn(response: response),
            bearerToken: bearerToken
        )
    }
}
