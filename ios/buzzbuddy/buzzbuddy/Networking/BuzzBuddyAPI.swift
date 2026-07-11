import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .server(let message): return message
        }
    }
}

final class BuzzBuddyAPI {
    // iOS Simulator can reach the Mac's own localhost directly. For a
    // physical device, or once the backend is deployed to App Platform,
    // replace this with the LAN IP or the deployed HTTPS URL.
    static let baseURL = URL(string: "http://127.0.0.1:8000")!

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
            throw APIError.server(message)
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func send<Response: Decodable>(_ path: String, method: String) async throws -> Response {
        var request = URLRequest(url: BuzzBuddyAPI.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        return try await perform(request)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ path: String, method: String = "POST", body: Body
    ) async throws -> Response {
        var request = URLRequest(url: BuzzBuddyAPI.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func createUser(_ payload: UserCreate) async throws -> UserOut {
        try await send("/users", body: payload)
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
}
