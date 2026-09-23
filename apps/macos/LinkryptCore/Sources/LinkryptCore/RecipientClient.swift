import Foundation

public enum RecipientError: Error, Equatable {
    case gone              // 404 / 410 — burned, revoked, expired, frozen, consumed
    case passphraseInvalid // 401
    case rateLimited       // 429
    case network(String)
    case server(Int)
    case decoding(String)
}

public enum RecipientMeta {
    case passphraseRequired(salt: String, kdf: PassphraseKdf, type: ShareType,
                            size: Int, filename: String?, opensRemaining: Int, expiresAt: Int)
    case payload(type: ShareType, size: Int, filename: String?, ciphertext: String?,
                 downloadUrl: String?, paddingVersion: PaddingVersion, opensRemaining: Int, expiresAt: Int)
}

/// Unauthenticated recipient client for `GET/POST /api/shares/{id}/meta`.
/// Mirrors `APIClient`'s session/mock pattern but carries no Authorization.
public final class RecipientClient: Sendable {
    let baseURL: String
    let session: URLSession

    public init(baseURL: String, session: URLSession? = nil) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        // Default to an ephemeral session: recipient responses carry ciphertext
        // and short-lived presigned URLs that must NOT land in the on-disk URL
        // cache. Tests inject their own session.
        self.session = session ?? URLSession(configuration: .ephemeral)
    }

    public func meta(id: String) async throws -> RecipientMeta {
        var r = URLRequest(url: try url(id))
        r.httpMethod = "GET"
        return try await send(r)
    }

    public func submitPassphrase(id: String, attempt: String) async throws -> RecipientMeta {
        var r = URLRequest(url: try url(id))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = try JSONEncoder().encode(["passphraseAttempt": attempt])
        return try await send(r)
    }

    /// Fetch the ciphertext blob from a presigned download URL (file shares).
    /// The URL is a short-lived bearer URL — callers keep it in memory only.
    public func fetchCiphertext(from urlString: String) async throws -> Data {
        guard let u = URL(string: urlString), u.scheme == "https" else {
            throw RecipientError.network("invalid download URL")
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(from: u) }
        catch { throw RecipientError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw RecipientError.network("non-HTTP") }
        switch http.statusCode {
        case 200...299: return data
        case 404, 410: throw RecipientError.gone
        default: throw RecipientError.server(http.statusCode)
        }
    }

    private func url(_ id: String) throws -> URL {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let u = URL(string: "\(baseURL)/api/shares/\(safe)/meta") else {
            throw RecipientError.network("invalid URL")
        }
        return u
    }

    private func send(_ request: URLRequest) async throws -> RecipientMeta {
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw RecipientError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw RecipientError.network("non-HTTP") }
        switch http.statusCode {
        case 200...299:
            do { return try decode(data) }
            catch let e as RecipientError { throw e }
            catch { throw RecipientError.decoding("\(error)") }
        case 401: throw RecipientError.passphraseInvalid
        case 404, 410: throw RecipientError.gone
        case 429: throw RecipientError.rateLimited
        default: throw RecipientError.server(http.statusCode)
        }
    }

    private struct DTO: Decodable {
        let passphraseRequired: Bool
        let passphraseSalt: String?
        let passphraseKdf: PassphraseKdf?
        let type: ShareType?
        let size: Int
        let filename: String?
        let ciphertext: String?
        let downloadUrl: String?
        let paddingVersion: PaddingVersion?
        let opensRemaining: Int
        let expiresAt: Int
    }

    private func decode(_ data: Data) throws -> RecipientMeta {
        let d = try JSONDecoder().decode(DTO.self, from: data)
        if d.passphraseRequired {
            guard let salt = d.passphraseSalt else { throw RecipientError.decoding("missing salt") }
            return .passphraseRequired(salt: salt, kdf: d.passphraseKdf ?? .pbkdf2,
                                       type: d.type ?? .text, size: d.size, filename: d.filename,
                                       opensRemaining: d.opensRemaining, expiresAt: d.expiresAt)
        }
        return .payload(type: d.type ?? .text, size: d.size, filename: d.filename,
                        ciphertext: d.ciphertext, downloadUrl: d.downloadUrl,
                        paddingVersion: d.paddingVersion ?? .v0,
                        opensRemaining: d.opensRemaining, expiresAt: d.expiresAt)
    }
}
