import XCTest
@testable import LinkryptCore

final class SubmitClientTests: XCTestCase {
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
    private func makeClient() -> SubmitClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return SubmitClient(baseURL: "https://linkrypt.sh", token: "tok_test",
                            session: URLSession(configuration: cfg))
    }

    func testInfoDecodes() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertTrue(req.url!.absoluteString.hasSuffix("/api/requests/r1/info"))
            let body = #"{"label":"Invoice","expiresAt":99}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let info = try await makeClient().info(id: "r1")
        XCTAssertEqual(info.label, "Invoice")
        XCTAssertEqual(info.expiresAt, 99)
    }

    func testSubmitTextSendsBearerToSubmit() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok_test")
            XCTAssertTrue(req.url!.absoluteString.hasSuffix("/api/cli/requests/r1/submit"))
            XCTAssertEqual(req.httpMethod, "POST")
            let ok = #"{"ok":true}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, ok)
        }
        try await makeClient().submitText(id: "r1", type: "text", plaintext: Data("hi".utf8))
    }

    func testSubmitText403MapsToForbidden() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data())
        }
        do { try await makeClient().submitText(id: "r1", type: "text", plaintext: Data("x".utf8)); XCTFail("expected forbidden") }
        catch SubmitError.forbidden {} catch { XCTFail("wrong error: \(error)") }
    }

    func testSubmitFileTwoPhase() async throws {
        var calls = 0
        MockURLProtocol.handler = { req in
            calls += 1
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok_test")
            XCTAssertTrue(req.url!.absoluteString.hasSuffix("/api/cli/requests/r1/submit"))
            XCTAssertEqual(req.httpMethod, "POST")
            if calls == 1 {   // phase 1: init → presigned URL + submissionId
                let body = #"{"uploadUrl":"https://r2.example/up?sig=x","submissionId":"sub1"}"#.data(using: .utf8)!
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    #"{"ok":true}"#.data(using: .utf8)!)   // phase 2: finalize
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("submit-file-test.bin")
        try Data([1, 2, 3, 4]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        var putURL: String?
        var putBytes: Data?
        try await makeClient().submitFile(id: "r1", fileURL: tmp, putR2: { url, data in
            putURL = url; putBytes = data
        })
        XCTAssertEqual(calls, 2)                              // init + finalize
        XCTAssertEqual(putURL, "https://r2.example/up?sig=x") // ciphertext PUT to the presigned URL
        // 4-byte plaintext → AES-GCM ciphertext is 4 + 16-byte tag = 20 bytes;
        // proves real encryption ran (not the raw plaintext) before the PUT.
        XCTAssertEqual(putBytes?.count, 20)
    }
}
