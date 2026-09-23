import Foundation

public enum SubmitError: Error, Equatable {
    case gone              // 404/410 — request link no longer available
    case unauthorized      // 401
    case forbidden         // 403
    case rateLimited       // 429
    case planLimit         // 402
    case network(String)
    case server(Int)
    case decoding(String)
}

/// Submits a response to a request link. `info` is a public GET; `submitText`/
/// `submitFile` are bearer POSTs to /api/cli/requests/{id}/submit.
public final class SubmitClient: Sendable {
    private let baseURL: String
    private let token: String
    private let session: URLSession

    public init(baseURL: String, token: String, session: URLSession? = nil) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.token = token
        self.session = session ?? URLSession(configuration: .ephemeral)
    }

    private func pathSafe(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    }
    private func statusError(_ code: Int) -> SubmitError {
        switch code {
        case 401: return .unauthorized
        case 402: return .planLimit
        case 403: return .forbidden
        case 404, 410: return .gone
        case 429: return .rateLimited
        default: return .server(code)
        }
    }
    private func send(_ r: URLRequest) async throws -> Data {
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: r) }
        catch { throw SubmitError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw SubmitError.network("non-HTTP") }
        guard (200...299).contains(http.statusCode) else { throw statusError(http.statusCode) }
        return data
    }
    private func bearerPost(_ path: String, json: [String: Any]) throws -> URLRequest {
        guard let u = URL(string: baseURL + path) else { throw SubmitError.network("invalid URL") }
        var r = URLRequest(url: u); r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: json)
        return r
    }

    public func info(id: String) async throws -> RequestInfo {
        guard let u = URL(string: "\(baseURL)/api/requests/\(pathSafe(id))/info") else { throw SubmitError.network("invalid URL") }
        var r = URLRequest(url: u); r.httpMethod = "GET"
        let data = try await send(r)
        do { return try JSONDecoder().decode(RequestInfo.self, from: data) }
        catch { throw SubmitError.decoding("\(error)") }
    }

    /// Encrypt + submit text/note in a single hop. `type` is "text" or "note".
    public func submitText(id: String, type: String, plaintext: Data) async throws {
        let key = Crypto.randomBytes(32), iv = Crypto.randomBytes(12)
        let ct = try Crypto.aesGcmEncrypt(key: key, iv: iv, plaintext: plaintext)
        let req = try bearerPost("/api/cli/requests/\(pathSafe(id))/submit", json: [
            "type": type, "size": ct.count,
            "keyB64u": Base64URL.encode(key), "ivB64u": Base64URL.encode(iv),
            "ciphertextB64u": Base64URL.encode(ct),
        ])
        _ = try await send(req)
    }

    /// Encrypt + submit a file: init (presign) → PUT ciphertext to R2 → finalize.
    /// `putR2` is injected by the caller (reuses APIClient.putR2).
    public func submitFile(id: String, fileURL: URL, putR2: (String, Data) async throws -> Void) async throws {
        let raw = try Data(contentsOf: fileURL)
        let key = Crypto.randomBytes(32), iv = Crypto.randomBytes(12)
        let ct = try Crypto.aesGcmEncrypt(key: key, iv: iv, plaintext: raw)
        let name = fileURL.lastPathComponent
        let initReq = try bearerPost("/api/cli/requests/\(pathSafe(id))/submit", json: [
            "type": "file", "size": ct.count, "filename": name,
            "keyB64u": Base64URL.encode(key), "ivB64u": Base64URL.encode(iv),
        ])
        let initData = try await send(initReq)
        struct Init: Decodable { let uploadUrl: String; let submissionId: String }
        let phase1: Init
        do { phase1 = try JSONDecoder().decode(Init.self, from: initData) }
        catch { throw SubmitError.decoding("\(error)") }
        try await putR2(phase1.uploadUrl, ct)
        let finReq = try bearerPost("/api/cli/requests/\(pathSafe(id))/submit", json: [
            "type": "file", "finalize": true, "submissionId": phase1.submissionId,
            "size": ct.count, "filename": name,
            "keyB64u": Base64URL.encode(key), "ivB64u": Base64URL.encode(iv),
        ])
        _ = try await send(finReq)
    }
}
