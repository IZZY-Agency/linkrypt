import XCTest
@testable import LinkryptCore

final class RecipientClientTests: XCTestCase {
    final class MockURLProtocol: URLProtocol {
        nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
        override func startLoading() {
            let (resp, data) = MockURLProtocol.handler!(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    private func makeClient() -> RecipientClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return RecipientClient(baseURL: "https://linkrypt.sh", session: URLSession(configuration: cfg))
    }
    private func resp(_ req: URLRequest, _ status: Int, _ json: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
    }
    /// URLSession moves a request's httpBody into httpBodyStream by the time it
    /// reaches a URLProtocol, so read whichever is present.
    private func bodyData(_ req: URLRequest) -> Data {
        if let b = req.httpBody { return b }
        guard let s = req.httpBodyStream else { return Data() }
        s.open(); defer { s.close() }
        var out = Data()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096); defer { buf.deallocate() }
        while s.hasBytesAvailable {
            let n = s.read(buf, maxLength: 4096)
            if n <= 0 { break }
            out.append(buf, count: n)
        }
        return out
    }

    func testMetaTextPayload() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "GET")
            XCTAssertTrue(req.url!.absoluteString.hasSuffix("/api/shares/abc/meta"))
            return self.resp(req, 200, #"{"passphraseRequired":false,"type":"text","size":12,"ciphertext":"AAAA","paddingVersion":"v1","opensRemaining":0,"expiresAt":99}"#)
        }
        guard case .payload(let type, _, _, let ct, let dl, let pad, let opens, _) = try await makeClient().meta(id: "abc") else {
            return XCTFail("expected .payload")
        }
        XCTAssertEqual(type, .text); XCTAssertEqual(ct, "AAAA"); XCTAssertNil(dl)
        XCTAssertEqual(pad, .v1); XCTAssertEqual(opens, 0)
    }

    func testMetaFilePayload() async throws {
        MockURLProtocol.handler = { req in
            self.resp(req, 200, #"{"passphraseRequired":false,"type":"file","size":100,"filename":"a.bin","downloadUrl":"https://r2/x","paddingVersion":"v0","opensRemaining":1,"expiresAt":99}"#)
        }
        guard case .payload(let type, _, let fn, let ct, let dl, _, _, _) = try await makeClient().meta(id: "f") else {
            return XCTFail("expected .payload")
        }
        XCTAssertEqual(type, .file); XCTAssertEqual(fn, "a.bin"); XCTAssertNil(ct); XCTAssertEqual(dl, "https://r2/x")
    }

    func testMetaPassphraseRequiredThenPost() async throws {
        MockURLProtocol.handler = { req in
            if req.httpMethod == "GET" {
                return self.resp(req, 200, #"{"passphraseRequired":true,"passphraseSalt":"c2FsdA","passphraseKdf":"argon2id","type":"text","size":5,"opensRemaining":1,"expiresAt":99}"#)
            }
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.value(forHTTPHeaderField: "content-type"), "application/json")
            let obj = try? JSONSerialization.jsonObject(with: self.bodyData(req))
            XCTAssertEqual((obj as? [String: String])?["passphraseAttempt"], "hash")
            return self.resp(req, 200, #"{"passphraseRequired":false,"type":"text","size":5,"ciphertext":"Qk9P","paddingVersion":"v1","opensRemaining":0,"expiresAt":99}"#)
        }
        let c = makeClient()
        guard case .passphraseRequired(let salt, let kdf, _, _, _, _, _) = try await c.meta(id: "p") else {
            return XCTFail("expected .passphraseRequired")
        }
        XCTAssertEqual(salt, "c2FsdA"); XCTAssertEqual(kdf, .argon2id)
        guard case .payload(_, _, _, let ct, _, _, _, _) = try await c.submitPassphrase(id: "p", attempt: "hash") else {
            return XCTFail("expected .payload")
        }
        XCTAssertEqual(ct, "Qk9P")
    }

    func testFetchCiphertextReturnsBytes() async throws {
        let raw = Data([0xDE, 0xAD, 0xBE, 0xEF])
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "GET")
            XCTAssertEqual(req.url!.absoluteString, "https://r2.example/blob?sig=x")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, raw)
        }
        let got = try await makeClient().fetchCiphertext(from: "https://r2.example/blob?sig=x")
        XCTAssertEqual(got, raw)
    }

    func testFetchCiphertextNon2xxThrowsGone() async {
        MockURLProtocol.handler = { req in self.resp(req, 404, "") }
        do { _ = try await makeClient().fetchCiphertext(from: "https://r2.example/blob"); XCTFail("expected throw") }
        catch let e as RecipientError { XCTAssertEqual(e, .gone) }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testFetchCiphertextBadURLThrows() async {
        do { _ = try await makeClient().fetchCiphertext(from: "not a url"); XCTFail("expected throw") }
        catch let e as RecipientError { if case .network = e {} else { XCTFail("expected .network") } }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testStatusMapping() async {
        let cases: [(Int, RecipientError)] = [(401, .passphraseInvalid), (404, .gone), (410, .gone), (429, .rateLimited)]
        for (status, expected) in cases {
            MockURLProtocol.handler = { req in self.resp(req, status, #"{"error":"x"}"#) }
            do { _ = try await makeClient().meta(id: "e"); XCTFail("expected throw for \(status)") }
            catch let e as RecipientError { XCTAssertEqual(e, expected, "status \(status)") }
            catch { XCTFail("wrong error type for \(status): \(error)") }
        }
    }
}
