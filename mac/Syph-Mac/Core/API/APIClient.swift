import Foundation

struct APIError: LocalizedError {
    let message: String
    var statusCode: Int?
    var errorDescription: String? { message }
}

/// HTTP client for the Syph API. The session cookie lives in the shared
/// cookie store, exactly like the web console and the iPhone app.
final class APIClient: @unchecked Sendable {
    static let defaultServer = "https://srv1982864.hstgr.cloud"
    private static let serverKey = "syph.server.url"

    let session: URLSession
    private let lock = NSLock()
    private var _server: String

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 40
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
        _server = UserDefaults.standard.string(forKey: Self.serverKey) ?? Self.defaultServer
    }

    var server: String {
        get { lock.lock(); defer { lock.unlock() }; return _server }
        set {
            lock.lock()
            _server = newValue.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            lock.unlock()
            UserDefaults.standard.set(server, forKey: Self.serverKey)
        }
    }

    func baseURL() throws -> URL {
        guard let url = URL(string: server), let host = url.host?.lowercased(), !host.isEmpty,
              let scheme = url.scheme?.lowercased() else {
            throw APIError(message: "The server address isn’t valid. Use an https:// address.")
        }
        // Plain HTTP only for local development or a private Tailscale tailnet.
        let privateHost = ["localhost", "127.0.0.1"].contains(host) || host.hasSuffix(".ts.net") || host.hasPrefix("100.")
        guard scheme == "https" || (scheme == "http" && privateHost) else {
            throw APIError(message: "The server address isn’t valid. Use an https:// address.")
        }
        return url
    }

    func resolve(_ path: String) -> URL? {
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
        guard let base = try? baseURL() else { return nil }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    @discardableResult
    func send<T: Decodable>(
        _ type: T.Type,
        _ path: String,
        method: String = "GET",
        body: Any? = nil,
        idempotent: Bool = false,
        timeout: TimeInterval = 30
    ) async throws -> T {
        let base = try baseURL()
        guard let url = URL(string: path, relativeTo: base) else {
            throw APIError(message: "Could not form the request URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if idempotent { request.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError(message: Self.describe(error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "Syph returned an invalid response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(ErrorDetail.self, from: data))?.detail
            throw APIError(message: detail ?? "Syph returned HTTP \(http.statusCode).", statusCode: http.statusCode)
        }
        if T.self == EmptyResponse.self, let empty = EmptyResponse() as? T { return empty }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError(message: "Syph sent data this version can’t read (\(path)).")
        }
    }

    static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: return "This Mac is offline."
        case .timedOut: return "Syph didn’t respond in time."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "Syph couldn’t be reached. Check your connection."
        case .secureConnectionFailed, .serverCertificateUntrusted: return "A secure connection to Syph couldn’t be established."
        case .cancelled: return "Cancelled."
        default: return error.localizedDescription
        }
    }
}

private struct ErrorDetail: Decodable {
    let detail: String?
}

struct EmptyResponse: Decodable {
    init() {}
}
