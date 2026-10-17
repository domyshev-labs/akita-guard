import XCTest
@testable import AkitaGuardCore

private final class StubProtocol: URLProtocol {
    static let lock = NSLock()
    static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        guard let handler else { fatalError("Test handler missing") }
        let (code, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

final class APIClientTests: XCTestCase {
    private func makeClient(_ handler: @escaping (URLRequest) -> (Int, Data)) -> APIClient {
        StubProtocol.lock.lock(); StubProtocol.handler = handler; StubProtocol.lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return APIClient(base: URL(string: "http://192.168.1.10:9120")!, token: String(repeating: "x", count: 48), configuration: config)
    }

    private func data(_ text: String) -> Data { Data(text.utf8) }
    private func status(state: String = "applied", revision: String = "r1", date: Date = Date()) -> Data {
        data("{\"state\":\"\(state)\",\"revision\":\"\(revision)\",\"checked_at\":\"\(ISO8601DateFormatter().string(from: date))\"}")
    }
    private func entries(_ revision: String) -> Data {
        data("{\"version\":1,\"revision\":\"\(revision)\",\"entries\":[]}")
    }
    private func body(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            output.append(buffer, count: count)
        }
        return output
    }

    func testDecodesPythonFractionalAndWholeTimestamps() throws {
        let document = data("""
        {"version":1,"revision":"r1","entries":[
        {"id":"a","address":"8.8.8.8","label":"Работа","expires_at":"2026-10-17T18:12:30.123456+00:00"},
        {"id":"b","address":"2606:4700:4700::1111","expires_at":"2026-10-17T18:12:30Z"}
        ]}
        """)
        let result = try APICoding.decoder().decode(EntriesResponse.self, from: document)
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.entries[0].expiresAt.timeIntervalSince(result.entries[1].expiresAt), 0.123, accuracy: 0.01)
    }

    func testPostUsesBearerHeaderAndExactAPIContract() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/v1/entries")
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + String(repeating: "x", count: 48))
            let payload = try! JSONSerialization.jsonObject(with: self.body(request)) as! [String: Any]
            XCTAssertEqual(payload["address"] as? String, "8.8.8.8")
            XCTAssertEqual(payload["ttl_seconds"] as? Int, 28800)
            XCTAssertEqual(payload["label"] as? String, "Работа")
            return (202, self.data("{\"state\":\"queued\",\"revision\":\"new\",\"entry\":null}"))
        }
        let response = try await client.add(address: " 8.8.8.8 ", label: "Работа", ttl: 28800)
        XCTAssertEqual(response.state, "queued")
    }

    func testUnauthorizedIsNotTreatedAsEmptyAllowlist() async {
        let client = makeClient { _ in (401, self.data("{\"error\":\"unauthorized\"}")) }
        do { _ = try await client.entries(); XCTFail("Must fail") }
        catch AccessError.unauthorized { }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testRedirectResponseIsRejected() async {
        let client = makeClient { _ in (302, Data()) }
        do { _ = try await client.entries(); XCTFail("Must fail") }
        catch AccessError.unexpectedResponse { }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testQueuedResponseWaitsForFreshMatchingRevision() async throws {
        var count = 0
        let client = makeClient { request in
            if request.url!.path.hasSuffix("/status") {
                count += 1
                return (200, self.status(revision: count == 1 ? "previous" : "r1"))
            }
            return (200, self.entries("r1"))
        }
        let confirmation = try await client.confirm("r1", attempts: 3, interval: 0)
        XCTAssertEqual(confirmation, .applied)
        XCTAssertEqual(count, 2)
    }

    func testStaleStatusDoesNotConfirmFirewallSuccess() async throws {
        let client = makeClient { request in
            if request.url!.path.hasSuffix("/status") {
                return (200, self.status(date: Date().addingTimeInterval(-120)))
            }
            return (200, self.entries("r1"))
        }
        let confirmation = try await client.confirm("r1", attempts: 2, interval: 0)
        XCTAssertEqual(confirmation, .pending)
    }

    func testDisabledFilterDoesNotConfirmFirewallSuccess() async throws {
        let client = makeClient { _ in (200, self.status(state: "disabled")) }
        let confirmation = try await client.confirm("r1", attempts: 1, interval: 0)
        XCTAssertEqual(confirmation, .disabled)
    }

    func testConcurrentRevisionIsShownAsSuperseded() async throws {
        let client = makeClient { request in
            if request.url!.path.hasSuffix("/status") { return (200, self.status(revision: "previous")) }
            return (200, self.entries("another-device"))
        }
        let confirmation = try await client.confirm("r1", attempts: 2, interval: 0)
        XCTAssertEqual(confirmation, .superseded)
    }

    func testMalformedServerResponseIsNotSuccess() async {
        let client = makeClient { _ in (200, self.data("<html>Login</html>")) }
        do { _ = try await client.status(); XCTFail("Must fail") }
        catch AccessError.unexpectedResponse { }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testUnsafeDeleteIDNeverMakesRequest() async {
        let client = makeClient { _ in XCTFail("Must not send request"); return (200, Data()) }
        do { _ = try await client.remove(id: "../status"); XCTFail("Must fail") }
        catch AccessError.invalidRequest { }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testInputRejectsCIDRAndPublicCleartextServer() throws {
        XCTAssertEqual(try InputValidation.address("2606:4700:4700::1111"), "2606:4700:4700::1111")
        XCTAssertThrowsError(try InputValidation.address("8.8.8.0/24"))
        XCTAssertThrowsError(try InputValidation.address("999.1.1.1"))
        XCTAssertThrowsError(try InputValidation.server("http://8.8.8.8:9120"))
        XCTAssertThrowsError(try InputValidation.server("http://192.168.1.10.example.com:9120"))
        XCTAssertThrowsError(try InputValidation.server("https://user:secret@example.com"))
        XCTAssertThrowsError(try InputValidation.server("http://192.168.1.10:9120/v1"))
        XCTAssertEqual(try InputValidation.server("http://192.168.1.10:9120").host, "192.168.1.10")
    }
}
