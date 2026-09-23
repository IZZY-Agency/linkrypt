import XCTest
@testable import LinkryptCore

final class InboxClientTests: XCTestCase {
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

    private func makeClient() -> InboxClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return InboxClient(baseURL: "https://linkrypt.sh", token: "tok_test",
                           session: URLSession(configuration: cfg))
    }

    func testMetaSendsBearerAndDecodesText() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok_test")
            XCTAssertTrue(req.url!.absoluteString.hasSuffix("/api/cli/inbox/r1"))
            XCTAssertEqual(req.httpMethod, "GET")
            let body = #"{"contentType":"text","size":4,"ciphertext":"QUJDRA"}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let meta = try await makeClient().meta(id: "r1")
        XCTAssertEqual(meta.contentType, "text")
        XCTAssertEqual(meta.ciphertext, "QUJDRA")
    }

    func testMeta404MapsToGone() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        do { _ = try await makeClient().meta(id: "x"); XCTFail("expected gone") }
        catch InboxError.gone {} catch { XCTFail("wrong error: \(error)") }
    }

    func testAckSendsPostBearer() async throws {
        var seen: String?
        MockURLProtocol.handler = { req in
            seen = req.httpMethod
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok_test")
            XCTAssertTrue(req.url!.absoluteString.hasSuffix("/api/cli/inbox/r1/ack"))
            return (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }
        try await makeClient().ack(id: "r1")
        XCTAssertEqual(seen, "POST")
    }

    func testFetchFileCiphertextReturnsBytes() async throws {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data([0xDE, 0xAD, 0xBE, 0xEF]))
        }
        let bytes = try await makeClient().fetchFileCiphertext(from: "https://r2.example/blob?sig=x")
        XCTAssertEqual(bytes, Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    func testFetchFileCiphertextRejectsNonHttpsURL() async {
        do { _ = try await makeClient().fetchFileCiphertext(from: "http://r2.example/blob"); XCTFail("expected network error") }
        catch InboxError.network {} catch { XCTFail("wrong error: \(error)") }
    }
}
