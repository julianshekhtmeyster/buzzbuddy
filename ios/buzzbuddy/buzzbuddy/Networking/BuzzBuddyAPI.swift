import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case server(status: Int, message: String)
    case configuration(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .server(_, let message): return message
        case .configuration(let message): return message
        }
    }

    /// True for any "this ID doesn't exist on the server" response --
    /// user/event/session all 404 the same way. A backend whose database
    /// got reset out from under an already-onboarded client (e.g. a
    /// redeploy with no persistent storage) surfaces here, since every ID
    /// that client has cached locally stops existing at once.
    var isNotFound: Bool {
        if case .server(404, _) = self { return true }
        return false
    }
}

protocol BuzzBuddyAPIProtocol {
    func createUser(_ payload: UserCreate) async throws -> UserOut
    func updateBaseline(userId: String, _ payload: BaselineUpdate) async throws -> UserOut
    func createEvent(_ payload: EventCreate) async throws -> EventOut
    func startSession(eventId: String) async throws -> SessionOut
    func submitTestResult(sessionId: String, _ payload: TestResultIn) async throws -> SessionOut
    func getSession(sessionId: String) async throws -> SessionOut
    func sendDDChatMessage(sessionId: String, question: String) async throws -> DDChatResponse
}

/// Resolves the backend base URL, in order: the `BUZZBUDDY_API_BASE_URL`
/// scheme environment variable, then the `BuzzBuddyAPIBaseURL` Info.plist
/// key, then (Debug builds only) localhost. A Release build with neither an
/// env var nor a plist value fails with a configuration error rather than
/// silently pointing at a developer's machine.
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
        if let value = infoDictionary?[infoPlistKey] as? String, !value.isEmpty {
            return validate(value)
        }
        #if DEBUG
        return validate("http://127.0.0.1:8000")
        #else
        return .failure(.configuration(
            "No backend URL configured. Set \(infoPlistKey) in Info.plist or the \(environmentKey) scheme environment variable."
        ))
        #endif
    }

    private static func validate(_ string: String) -> Result<URL, APIError> {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return .failure(.configuration("Invalid backend URL \"\(string)\" -- must be http:// or https://"))
        }
        return .success(url)
    }
}

final class BuzzBuddyAPI: BuzzBuddyAPIProtocol {
    private let baseURLResult: Result<URL, APIError>

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) {
        self.baseURLResult = APIConfiguration.resolveBaseURL(environment: environment, infoDictionary: infoDictionary)
    }

    private func baseURL() throws -> URL {
        try baseURLResult.get()
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

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw APIError.server(status: http.statusCode, message: message)
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func send<Response: Decodable>(_ path: String, method: String) async throws -> Response {
        var request = URLRequest(url: try baseURL().appendingPathComponent(path))
        request.httpMethod = method
        return try await perform(request)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ path: String, method: String = "POST", body: Body
    ) async throws -> Response {
        var request = URLRequest(url: try baseURL().appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func createUser(_ payload: UserCreate) async throws -> UserOut {
        try await send("/users", body: payload)
    }

    func updateBaseline(userId: String, _ payload: BaselineUpdate) async throws -> UserOut {
        try await send("/users/\(userId)/baseline", method: "PATCH", body: payload)
    }

    func createEvent(_ payload: EventCreate) async throws -> EventOut {
        try await send("/events", body: payload)
    }

    func startSession(eventId: String) async throws -> SessionOut {
        try await send("/events/\(eventId)/sessions", method: "POST")
    }

    func submitTestResult(sessionId: String, _ payload: TestResultIn) async throws -> SessionOut {
        try await send("/sessions/\(sessionId)/test-results", body: payload)
    }

    func getSession(sessionId: String) async throws -> SessionOut {
        try await send("/sessions/\(sessionId)", method: "GET")
    }

    func sendDDChatMessage(sessionId: String, question: String) async throws -> DDChatResponse {
        try await send("/sessions/\(sessionId)/dd-chat", body: DDChatRequest(question: question))
    }
}
