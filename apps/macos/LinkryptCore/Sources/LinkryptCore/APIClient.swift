import Foundation

public final class APIClient: Sendable {
    let baseURL: String
    private let token: String
    let session: URLSession

    public init(baseURL: String, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.token = token
        self.session = session
    }

    private func url(_ path: String) throws -> URL {
        guard let u = URL(string: baseURL + path) else {
            throw APIError.network("invalid URL: \(path)")
        }
        return u
    }

    private func pathSafe(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    }

    private func authed(_ path: String, method: String) throws -> URLRequest {
        var r = URLRequest(url: try url(path))
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Declare JSON on every mutation, even bodiless ones (DELETE revoke):
        // the server's CSRF origin check 403s a non-GET with no Content-Type + no
        // Origin, and a bearer client never sends an Origin. Callers with a
        // binary body override this with application/octet-stream.
        if method != "GET" { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return r
    }

    /// Sends the request, maps non-2xx to typed APIError, returns body bytes.
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch { throw APIError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("non-HTTP response")
        }
        switch http.statusCode {
        case 200...299: return data
        case 401: throw APIError.unauthorized
        case 402:
            struct Plan: Decodable { let limit: String?; let upgrade: String? }
            let p = try? JSONDecoder().decode(Plan.self, from: data)
            throw APIError.planLimit(limit: p?.limit ?? "unknown", upgrade: p?.upgrade ?? "/pricing")
        case 403:
            throw APIError.forbidden(message: String(data: data, encoding: .utf8) ?? "forbidden")
        default:
            throw APIError.server(status: http.statusCode,
                                  message: String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decoding("\(T.self): \(error)") }
    }

    public func whoami() async throws -> WhoAmI {
        try decode(WhoAmI.self, try await send(try authed("/api/cli/whoami", method: "GET")))
    }

    /// Validates the token AND that it carries the scopes the sender app needs.
    @discardableResult
    public func login(requiring scopes: [String]) async throws -> WhoAmI {
        let who = try await whoami()
        let missing = scopes.filter { !who.scopes.contains($0) }
        if !missing.isEmpty { throw APIError.insufficientScope(missing: missing) }
        return who
    }

    public func listShares() async throws -> [ShareRow] {
        let data = try await send(try authed("/api/cli/list", method: "GET"))
        return try decode(ShareListResponse.self, data).shares
    }

    public func revoke(id: String) async throws {
        let path = "/api/cli/revoke/\(pathSafe(id))"
        _ = try await send(try authed(path, method: "DELETE"))   // 204, empty body OK
    }

    public func audit(limit: Int? = nil) async throws -> Data {
        let path = limit.map { "/api/cli/audit?limit=\($0)" } ?? "/api/cli/audit"
        return try await send(try authed(path, method: "GET"))
    }

    public func createShare(_ req: CreateShareRequest) async throws -> CreateShareResponse {
        var r = try authed("/api/cli/shares", method: "POST")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONEncoder().encode(req)
        return try decode(CreateShareResponse.self, try await send(r))
    }

    public func finalizeText(id: String, ciphertext: Data) async throws {
        var r = try authed("/api/cli/shares/\(pathSafe(id))/finalize", method: "POST")
        r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        r.httpBody = ciphertext
        _ = try await send(r)
    }

    public func finalizeFile(id: String) async throws {
        var r = try authed("/api/cli/shares/\(pathSafe(id))/finalize", method: "POST")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = Data("{}".utf8)
        _ = try await send(r)
    }

    /// PUT ciphertext to the presigned R2 URL (no auth header — the signature
    /// is in the query string). `uploadUrl` comes from createShare for files.
    public func putR2(uploadUrl: String, ciphertext: Data) async throws {
        guard let u = URL(string: uploadUrl) else { throw APIError.network("bad uploadUrl") }
        var r = URLRequest(url: u)
        r.httpMethod = "PUT"
        r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        r.httpBody = ciphertext
        _ = try await send(r)
    }

    public func createRequest(_ req: CreateRequestRequest) async throws -> CreatedRequest {
        var r = try authed("/api/cli/requests", method: "POST")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONEncoder().encode(req)
        return try decode(CreatedRequest.self, try await send(r))
    }

    public func listRequests() async throws -> [RequestRow] {
        let data = try await send(try authed("/api/cli/requests", method: "GET"))
        return try decode(RequestListResponse.self, data).requests
    }

    public func revokeRequest(id: String) async throws {
        let path = "/api/cli/requests/\(pathSafe(id))"
        _ = try await send(try authed(path, method: "DELETE"))   // 204, empty body OK
    }

    public func emailLink(id: String, url: String, recipientEmail: String, lang: String) async throws {
        var r = try authed("/api/cli/shares/\(pathSafe(id))/email-link", method: "POST")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: [
            "url": url, "recipientEmail": recipientEmail, "lang": lang
        ])
        _ = try await send(r)
    }
}
