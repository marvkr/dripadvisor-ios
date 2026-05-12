import Testing
import Foundation
@testable import DripAdvisor

/// Custom URLProtocol that serves canned responses — no real network calls.
/// MUST be used within the `.serialized` HTTP parent suite because its state
/// is class-global by design (URLProtocol gives us no way around this).
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        let statusCode: Int
        let body: Data
        let headers: [String: String]
    }

    nonisolated(unsafe) static var stubs: [String: Stub] = [:]
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequest = request
        MockURLProtocol.lastBody = captureBody(from: request)

        let key = (request.url?.path ?? "") + "#" + (request.httpMethod ?? "")
        let stub = MockURLProtocol.stubs[key] ?? Stub(statusCode: 404, body: Data(), headers: [:])
        let response = HTTPURLResponse(
            url: request.url!, statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1", headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func stub(path: String, method: String, status: Int, bodyJSON: String) {
        stubs["\(path)#\(method)"] = Stub(
            statusCode: status,
            body: Data(bodyJSON.utf8),
            headers: ["Content-Type": "application/json"]
        )
    }

    static func reset() {
        stubs.removeAll()
        lastRequest = nil
        lastBody = nil
    }

    private func captureBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var buf = [UInt8](repeating: 0, count: 4096)
        var data = Data()
        while stream.hasBytesAvailable {
            let n = stream.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}

private func makeClient(token: String? = nil) -> APIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return APIClient(
        baseURL: URL(string: "http://test.local")!,
        session: session,
        tokenProvider: { token }
    )
}

private func makeAPI() -> DripAPI {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return DripAPI(client: APIClient(
        baseURL: URL(string: "http://test.local")!,
        session: URLSession(configuration: config),
        tokenProvider: { "test-token" }
    ))
}

// All suites below share MockURLProtocol static state. We use a single
// parent serialized suite so they run sequentially across suites too, not
// just within each suite.
@Suite("HTTP integration", .serialized)
struct HTTPIntegrationSuite {

    @Suite("APIClient")
    struct APIClientTests {
        struct Echo: Codable, Equatable { let id: String; let name: String }
        struct Req: Encodable { let title: String }

        @Test("GET deserializes snake_case JSON into camelCase Swift")
        func getDeserializesSnakeCase() async throws {
            MockURLProtocol.reset()
            MockURLProtocol.stub(
                path: "/v1/thing", method: "GET", status: 200,
                bodyJSON: #"{"id":"abc","name":"Hoodie"}"#
            )
            let c = makeClient()
            let got: Echo = try await c.get("/v1/thing")
            #expect(got == Echo(id: "abc", name: "Hoodie"))
        }

        @Test("POST encodes camelCase Swift as snake_case JSON")
        func postEncodesSnakeCase() async throws {
            MockURLProtocol.reset()
            MockURLProtocol.stub(
                path: "/v1/thing", method: "POST", status: 201,
                bodyJSON: #"{"id":"abc","name":"Hoodie"}"#
            )
            let c = makeClient()
            let _: Echo = try await c.post("/v1/thing", body: Req(title: "hi"))
            let body = String(data: MockURLProtocol.lastBody ?? Data(), encoding: .utf8) ?? ""
            #expect(body.contains("\"title\":\"hi\""))
        }

        @Test("401 throws .unauthorized")
        func unauthorizedMapped() async {
            MockURLProtocol.reset()
            MockURLProtocol.stub(path: "/v1/me", method: "GET", status: 401, bodyJSON: "{}")
            let c = makeClient()
            do {
                let _: Echo = try await c.get("/v1/me")
                Issue.record("expected error")
            } catch let APIError.unauthorized {
                // ok
            } catch {
                Issue.record("expected .unauthorized, got \(error)")
            }
        }

        @Test("sets Authorization header when token provided")
        func sendsBearer() async throws {
            MockURLProtocol.reset()
            MockURLProtocol.stub(
                path: "/v1/me", method: "GET", status: 200,
                bodyJSON: #"{"id":"x","name":"y"}"#
            )
            let c = makeClient(token: "abc123")
            let _: Echo = try await c.get("/v1/me")
            #expect(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
        }

        @Test("5xx maps to .badResponse with status + body")
        func badResponse() async {
            MockURLProtocol.reset()
            MockURLProtocol.stub(path: "/v1/thing", method: "GET", status: 500, bodyJSON: "boom")
            let c = makeClient()
            do {
                let _: Echo = try await c.get("/v1/thing")
                Issue.record("expected error")
            } catch let APIError.badResponse(status, body) {
                #expect(status == 500)
                #expect(body == "boom")
            } catch {
                Issue.record("wrong error: \(error)")
            }
        }
    }

    @MainActor
    @Suite("WardrobeSync")
    struct WardrobeSyncTests {

        @Test("push succeeds on 201 — nothing enqueued")
        func pushSucceeds() async {
            MockURLProtocol.reset()
            MockURLProtocol.stub(
                path: "/v1/wardrobe", method: "POST", status: 201,
                bodyJSON: #"{"id":"11111111-1111-1111-1111-111111111111","name":"Tee","brand":"Uniqlo","category":"top","tags":[],"created_at":"2026-04-23T09:00:00Z"}"#
            )
            let sync = WardrobeSync(api: makeAPI())
            await sync.pushAfterInsert(WardrobeItem(name: "Tee", brand: "Uniqlo", category: .top))
            #expect(sync.pendingCount == 0)
        }

        @Test("push enqueues on server error, retry drains")
        func retryDrains() async {
            MockURLProtocol.reset()
            MockURLProtocol.stub(path: "/v1/wardrobe", method: "POST", status: 500, bodyJSON: "boom")
            let sync = WardrobeSync(api: makeAPI())
            await sync.pushAfterInsert(WardrobeItem(name: "Tee", brand: "Uniqlo", category: .top))
            #expect(sync.pendingCount == 1)

            MockURLProtocol.stub(
                path: "/v1/wardrobe", method: "POST", status: 201,
                bodyJSON: #"{"id":"22222222-2222-2222-2222-222222222222","name":"Tee","brand":"Uniqlo","category":"top","tags":[],"created_at":"2026-04-23T09:00:00Z"}"#
            )
            await sync.retryPending()
            #expect(sync.pendingCount == 0)
        }

        @Test("pullLatest returns decoded items")
        func pullLatest() async throws {
            MockURLProtocol.reset()
            MockURLProtocol.stub(
                path: "/v1/wardrobe", method: "GET", status: 200,
                bodyJSON: #"""
                {"items":[{"id":"33333333-3333-3333-3333-333333333333","name":"Jeans","brand":"Levi's","category":"bottom","tags":["denim"],"created_at":"2026-04-23T09:00:00Z"}]}
                """#
            )
            let sync = WardrobeSync(api: makeAPI())
            let items = try await sync.pullLatest()
            #expect(items.count == 1)
            #expect(items.first?.name == "Jeans")
            #expect(items.first?.tags == ["denim"])
        }
    }

    @MainActor
    @Suite("DripStore sync bridge")
    struct DripStoreSyncTests {

        @Test("addItem with sync pushes to backend")
        func addItemTriggersSync() async {
            MockURLProtocol.reset()
            MockURLProtocol.stub(
                path: "/v1/wardrobe", method: "POST", status: 201,
                bodyJSON: #"{"id":"44444444-4444-4444-4444-444444444444","name":"Tee","brand":"Uniqlo","category":"top","tags":[],"created_at":"2026-04-23T09:00:00Z"}"#
            )
            let sync = WardrobeSync(api: makeAPI())
            let store = DripStore()
            store.sync = sync

            store.addItem(WardrobeItem(name: "Tee", brand: "Uniqlo", category: .top))

            for _ in 0..<40 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(25))
                if sync.pendingCount == 0 { break }
            }
            #expect(sync.pendingCount == 0, "expected successful push to leave nothing pending")
            #expect(store.wardrobe.count == 1)
        }

        @Test("addItem without sync is purely local")
        func addItemWithoutSync() async {
            let store = DripStore()
            #expect(store.sync == nil)
            store.addItem(WardrobeItem(name: "Tee", brand: "Uniqlo", category: .top))
            try? await Task.sleep(for: .milliseconds(50))
            #expect(store.wardrobe.count == 1)
            #expect(store.wardrobe.first?.name == "Tee")
        }
    }
}
