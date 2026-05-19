import Foundation

enum APIError: Error, LocalizedError {
    case badURL
    case badResponse(status: Int, body: String)
    case decoding(underlying: Error)
    case transport(underlying: Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .badURL: "Bad URL"
        case .badResponse(let status, let body): "HTTP \(status): \(body)"
        case .decoding(let e): "Decode error: \(e.localizedDescription)"
        case .transport(let e): "Network error: \(e.localizedDescription)"
        case .unauthorized: "Unauthorized — please sign in again"
        }
    }
}

/// Minimal HTTP client. Attaches a bearer token when provided.
///
/// Base URL resolution order:
///   1. `DRIP_API_BASE` env var (lets a build target override at run time)
///   2. `Info.plist` key `DRIP_API_BASE` (per-configuration xcconfig override)
///   3. Compiled default: DEBUG → http://localhost:8080, RELEASE → prod
struct APIClient: Sendable {
    let baseURL: URL
    let session: URLSession
    let tokenProvider: @Sendable () -> String?

    /// Default session: longer timeouts than `.shared` because /v1/tryon waits
    /// up to ~90s for Gemini Nano Banana Pro to return a composite.
    private static let defaultSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 180
        return URLSession(configuration: cfg)
    }()

    static var defaultBaseURL: URL {
        if let env = ProcessInfo.processInfo.environment["DRIP_API_BASE"],
           let url = URL(string: env) { return url }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "DRIP_API_BASE") as? String,
           let url = URL(string: plist) { return url }
        #if DEBUG
        return URL(string: "http://localhost:8080")!
        #else
        return URL(string: "https://api.5-78-141-236.sslip.io")!
        #endif
    }

    init(
        baseURL: URL = APIClient.defaultBaseURL,
        session: URLSession? = nil,
        tokenProvider: @escaping @Sendable () -> String? = { nil }
    ) {
        self.baseURL = baseURL
        self.session = session ?? Self.defaultSession
        self.tokenProvider = tokenProvider
    }

    func get<Response: Decodable>(_ path: String, as _: Response.Type = Response.self) async throws -> Response {
        try await request(path: path, method: "GET", body: Optional<Empty>.none)
    }

    func post<Request: Encodable, Response: Decodable>(
        _ path: String, body: Request, as _: Response.Type = Response.self
    ) async throws -> Response {
        try await request(path: path, method: "POST", body: body)
    }

    func delete(_ path: String) async throws {
        let _: Empty = try await request(path: path, method: "DELETE", body: Optional<Empty>.none)
    }

    private func request<Request: Encodable, Response: Decodable>(
        path: String, method: String, body: Request?
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let tok = tokenProvider() {
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder.api.encode(body)
        }

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw APIError.transport(underlying: error)
        }

        guard let http = resp as? HTTPURLResponse else {
            throw APIError.badResponse(status: -1, body: "")
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        if data.isEmpty, Response.self == Empty.self {
            // 204 No Content / empty DELETE
            return Empty() as! Response
        }
        do {
            return try JSONDecoder.api.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(underlying: error)
        }
    }
}

/// Marker type used for GET requests that have no body and endpoints that return nothing.
struct Empty: Codable, Sendable {}

extension JSONEncoder {
    static let api: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let api: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
