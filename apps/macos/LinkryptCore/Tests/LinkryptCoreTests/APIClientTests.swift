import XCTest
@testable import LinkryptCore

final class APIClientTests: XCTestCase {
    func testCreateShareRequestEncodesCamelCase() throws {
        let req = CreateShareRequest(
            type: .text, size: 263, rawSize: 247, expiresIn: "24h", maxOpens: 1,
            label: "API keys", filename: nil, recipientEmail: nil,
            notifyOnOpen: true, passphraseSalt: nil, passphraseHash: nil,
            passphraseKdf: nil, paddingVersion: .v0)
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["expiresIn"] as? String, "24h")
        XCTAssertEqual(json["maxOpens"] as? Int, 1)
        XCTAssertEqual(json["rawSize"] as? Int, 247)
        XCTAssertEqual(json["notifyOnOpen"] as? Bool, true)
        XCTAssertEqual(json["paddingVersion"] as? String, "v0")
        XCTAssertNil(json["filename"])           // nil fields omitted
    }
}

extension APIClientTests {
    /// Routes all requests to a closure so we can assert request + stub response.
    final class MockURLProtocol: URLProtocol {
        nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
        override func startLoading() {
            guard let h = MockURLProtocol.handler else { fatalError("no handler") }
            let (resp, data) = h(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    func makeClient() -> APIClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return APIClient(baseURL: "https://linkrypt.sh",
                         token: "tok_test",
                         session: URLSession(configuration: cfg))
    }

    func testWhoamiSendsBearerAndDecodes() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok_test")
            XCTAssertTrue(req.url!.absoluteString.hasSuffix("/api/cli/whoami"))
            let body = #"{"userId":"u1","scopes":["shares:write","shares:read"]}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let who = try await makeClient().whoami()
        XCTAssertEqual(who.userId, "u1")
        XCTAssertTrue(who.scopes.contains("shares:write"))
    }

    func testMissingScopeThrows() async {
        MockURLProtocol.handler = { req in
            let body = #"{"userId":"u1","scopes":["audit:read"]}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        do {
            _ = try await makeClient().login(requiring: ["shares:write", "shares:read"])
            XCTFail("expected insufficientScope")
        } catch APIError.insufficientScope(let missing) {
            XCTAssertEqual(Set(missing), Set(["shares:write", "shares:read"]))
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testPlanLimit402Maps() async {
        MockURLProtocol.handler = { req in
            let body = #"{"ok":false,"error":"plan limit","limit":"passphrase","upgrade":"/pricing"}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 402, httpVersion: nil, headerFields: nil)!, body)
        }
        do {
            _ = try await makeClient().listShares()
            XCTFail("expected planLimit")
        } catch APIError.planLimit(let limit, let upgrade) {
            XCTAssertEqual(limit, "passphrase"); XCTAssertEqual(upgrade, "/pricing")
        } catch { XCTFail("wrong error: \(error)") }
    }
}

extension APIClientTests {
    // HTTP 401 maps to APIError.unauthorized
    func test401MapsToUnauthorized() async {
        MockURLProtocol.handler = { req in
            return (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        do {
            _ = try await makeClient().listShares()
            XCTFail("expected unauthorized")
        } catch APIError.unauthorized {
            // pass
        } catch { XCTFail("wrong error: \(error)") }
    }

    // putR2 must NOT send an Authorization header (presigned URL carries auth in the query string)
    func testPutR2SendsNoAuthHeader() async throws {
        var capturedAuth: String? = "SENTINEL"
        MockURLProtocol.handler = { req in
            capturedAuth = req.value(forHTTPHeaderField: "Authorization")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }
        try await makeClient().putR2(uploadUrl: "https://r2.example.com/upload?X-Amz-Signature=abc",
                                     ciphertext: Data(repeating: 0, count: 8))
        XCTAssertNil(capturedAuth, "putR2 must not send an Authorization header")
    }
}

extension APIClientTests {
    func testCreateShareThenFinalizeText() async throws {
        var seenPaths: [String] = []
        var finalizeContentType: String?
        MockURLProtocol.handler = { req in
            seenPaths.append(req.url!.path)
            if req.url!.path.hasSuffix("/finalize") {
                finalizeContentType = req.value(forHTTPHeaderField: "Content-Type")
                let body = #"{"ok":true}"#.data(using: .utf8)!
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
            let body = #"{"id":"abc123"}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, body)
        }
        let client = makeClient()
        let req = CreateShareRequest(type: .text, size: 21, rawSize: 5, expiresIn: "24h",
            maxOpens: 1, label: nil, filename: nil, recipientEmail: nil, notifyOnOpen: nil,
            passphraseSalt: nil, passphraseHash: nil, passphraseKdf: nil, paddingVersion: .v0)
        let resp = try await client.createShare(req)
        XCTAssertEqual(resp.id, "abc123")
        try await client.finalizeText(id: resp.id, ciphertext: Data(repeating: 7, count: 21))
        XCTAssertTrue(seenPaths.contains("/api/cli/shares"))
        XCTAssertTrue(seenPaths.contains("/api/cli/shares/abc123/finalize"))
        XCTAssertEqual(finalizeContentType, "application/octet-stream")
    }
}

extension APIClientTests {
    func testCreateRequestSendsBearerAndDecodesId() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok_test")
            XCTAssertTrue(req.url!.absoluteString.hasSuffix("/api/cli/requests"))
            XCTAssertEqual(req.httpMethod, "POST")
            let body = #"{"id":"req_1"}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, body)
        }
        let made = try await makeClient().createRequest(
            CreateRequestRequest(label: "invoice", expiresIn: "24h"))
        XCTAssertEqual(made.id, "req_1")
    }

    func testListRequestsDecodes() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "GET")
            XCTAssertTrue(req.url!.absoluteString.hasSuffix("/api/cli/requests"))
            let body = #"{"requests":[{"id":"r1","label":"a","maxSubmissions":1,"submissionsUsed":0,"expiresAt":99,"createdAt":1,"submittedAt":null,"burnedAt":null,"revokedAt":null,"contentType":null,"filename":null,"size":null}]}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let rows = try await makeClient().listRequests()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].id, "r1")
        XCTAssertEqual(rows[0].expiresAt, 99)
    }

    func testRevokeRequestSendsDeleteWithBearer() async throws {
        var seenMethod: String?
        MockURLProtocol.handler = { req in
            seenMethod = req.httpMethod
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok_test")
            XCTAssertTrue(req.url!.absoluteString.hasSuffix("/api/cli/requests/r1"))
            return (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }
        try await makeClient().revokeRequest(id: "r1")
        XCTAssertEqual(seenMethod, "DELETE")
    }
}

extension APIClientTests {
    /// Bodiless mutations (DELETE revoke, POST ack) must still declare a JSON
    /// content type: the server's CSRF origin check 403s a non-GET request
    /// with no Content-Type and no Origin, and bearer clients never send an
    /// Origin. This keeps the clients robust on their own.
    func testRevokeSendsJsonContentTypeWithoutBody() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "DELETE")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
            return (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }
        try await makeClient().revoke(id: "abc")
    }

    func testFinalizeTextKeepsOctetStreamContentType() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        try await makeClient().finalizeText(id: "abc", ciphertext: Data([1, 2, 3]))
    }
}
