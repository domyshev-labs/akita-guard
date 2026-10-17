import Foundation

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public final class APIClient {
    private let base: URL
    private let token: String
    private let session: URLSession

    public init(base: URL, token: String, configuration: URLSessionConfiguration = .ephemeral) {
        self.base = base
        self.token = token
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    private func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let pieces = path.split(separator: "?", maxSplits: 1)
        var components = URLComponents(url: base.appendingPathComponent("v1").appendingPathComponent(String(pieces[0])), resolvingAgainstBaseURL: false)!
        if pieces.count == 2 { components.percentEncodedQuery = String(pieces[1]) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw AccessError.transport }
        guard let response = response as? HTTPURLResponse else { throw AccessError.unexpectedResponse }
        switch response.statusCode {
        case 200, 202: break
        case 400: throw AccessError.invalidRequest
        case 401, 403: throw AccessError.unauthorized
        case 404: throw AccessError.missingEntry
        case 500...599: throw AccessError.serverUnavailable
        default: throw AccessError.unexpectedResponse
        }
        do { return try APICoding.decoder().decode(T.self, from: data) }
        catch { throw AccessError.unexpectedResponse }
    }

    public func entries(includeExpired: Bool = false) async throws -> EntriesResponse {
        try await request(includeExpired ? "entries?include_expired=1" : "entries")
    }
    public func attempts() async throws -> AttemptsResponse { try await request("attempts") }
    public func rename(id: String, label: String) async throws -> MutationResponse {
        guard !id.isEmpty, id.count <= 64, id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }), label.count <= 120 else { throw AccessError.invalidRequest }
        let body = try JSONEncoder().encode(["label": label])
        return try await request("entries/" + id, method: "PATCH", body: body)
    }
    public func setBlocked(id: String, blocked: Bool) async throws -> MutationResponse {
        guard !id.isEmpty, id.count <= 64, id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { throw AccessError.invalidRequest }
        return try await request("entries/" + id, method: "PATCH", body: JSONEncoder().encode(["blocked": blocked]))
    }
    public func status() async throws -> WorkerStatus { try await request("status") }

    public func snapshot() async throws -> Snapshot {
        async let entries = entries(includeExpired: true)
        async let status = status()
        return try await Snapshot(entries: entries, status: status)
    }

    public func add(address: String, label: String, ttl: Int) async throws -> MutationResponse {
        struct Body: Encodable { let address: String; let label: String; let ttl_seconds: Int }
        let normalized = try InputValidation.address(address)
        guard (60...2592000).contains(ttl), label.count <= 120 else { throw AccessError.invalidRequest }
        let body = try JSONEncoder().encode(Body(address: normalized, label: label, ttl_seconds: ttl))
        return try await request("entries", method: "POST", body: body)
    }

    public func remove(id: String) async throws -> MutationResponse {
        guard !id.isEmpty, id.count <= 64,
              id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else {
            throw AccessError.invalidRequest
        }
        return try await request("entries/" + id, method: "DELETE")
    }

    public func confirm(_ revision: String, attempts: Int = 20, interval: UInt64 = 1_000_000_000) async throws -> Confirmation {
        for _ in 0..<attempts {
            try Task.checkCancellation()
            let state = try await status()
            if state.state == "disabled" { return .disabled }
            if state.state == "error" { return .failed }
            if state.state == "applied", state.revision == revision, state.isFresh() { return .applied }
            let desired = try await entries()
            if desired.revision != revision { return .superseded }
            if interval > 0 { try await Task.sleep(nanoseconds: interval) }
        }
        return .pending
    }
}
