import Foundation

public enum InboxError: Error, Equatable {
    case gone              // 404/410 — submission no longer available
    case unauthorized      // 401
    case forbidden         // 403 — wrong scope or not owner
    case network(String)
    case server(Int)
    case decoding(String)
}

/// Bearer-authed client for the owner inbox (`/api/cli/inbox/{id}` + `/ack`).
/// Uses an ephemeral URLSession by default: the meta response carries inline
/// ciphertext (text/note) and short-lived presigned URLs (file) that must NOT
/// land in the on-disk URL cache.
public final class InboxClient: Sendable {
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
    private func authed(_ path: String, method: String) throws -> URLRequest {
        guard let u = URL(string: baseURL + path) else { throw InboxError.network("invalid URL: \(path)") }
        var r = URLRequest(url: u)
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if method != "GET" { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }   // see APIClient.authed
        return r
    }
    private func statusError(_ code: Int) -> InboxError {
        switch code {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404, 410: return .gone
        default: return .server(code)
        }
    }

    public func meta(id: String) async throws -> InboxMeta {
        let req = try authed("/api/cli/inbox/\(pathSafe(id))", method: "GET")
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch { throw InboxError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw InboxError.network("non-HTTP") }
        guard (200...299).contains(http.statusCode) else { throw statusError(http.statusCode) }
        do { return try JSONDecoder().decode(InboxMeta.self, from: data) }
        catch { throw InboxError.decoding("\(error)") }
    }

    public func ack(id: String) async throws {
        let req = try authed("/api/cli/inbox/\(pathSafe(id))/ack", method: "POST")
        let response: URLResponse
        do { (_, response) = try await session.data(for: req) }
        catch { throw InboxError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw InboxError.network("non-HTTP") }
        guard (200...299).contains(http.statusCode) else { throw statusError(http.statusCode) }
    }

    /// Fetch a file submission's ciphertext from its presigned URL (no auth — the
    /// signature is in the query string). In-memory only.
    public func fetchFileCiphertext(from urlString: String) async throws -> Data {
        guard let u = URL(string: urlString), u.scheme == "https" else { throw InboxError.network("invalid download URL") }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(from: u) }
        catch { throw InboxError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw InboxError.network("non-HTTP") }
        // Don't route presigned-URL failures through statusError: 401/403 here
        // are signature/expiry errors from R2, not auth/scope — surface as gone/server.
        switch http.statusCode {
        case 200...299: return data
        case 404, 410: throw InboxError.gone
        default: throw InboxError.server(http.statusCode)
        }
    }
}
