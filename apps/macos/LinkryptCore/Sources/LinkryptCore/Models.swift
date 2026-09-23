import Foundation

public enum ShareType: String, Codable, Sendable { case text, file }
public enum PaddingVersion: String, Codable, Sendable { case v0, v1 }
public enum PassphraseKdf: String, Codable, Sendable { case pbkdf2, argon2id }

/// POST /api/cli/shares body. camelCase keys match the server contract; nil
/// fields are omitted (encoder set to skip nils via explicit encode).
public struct CreateShareRequest: Encodable {
    public let type: ShareType
    public let size: Int
    public let rawSize: Int?
    public let expiresIn: String
    public let maxOpens: Int
    public let label: String?
    public let filename: String?
    public let recipientEmail: String?
    public let notifyOnOpen: Bool?
    public let passphraseSalt: String?
    public let passphraseHash: String?
    public let passphraseKdf: PassphraseKdf?
    public let paddingVersion: PaddingVersion?

    public init(type: ShareType, size: Int, rawSize: Int?, expiresIn: String,
                maxOpens: Int, label: String?, filename: String?,
                recipientEmail: String?, notifyOnOpen: Bool?,
                passphraseSalt: String?, passphraseHash: String?,
                passphraseKdf: PassphraseKdf?, paddingVersion: PaddingVersion?) {
        self.type = type; self.size = size; self.rawSize = rawSize
        self.expiresIn = expiresIn; self.maxOpens = maxOpens; self.label = label
        self.filename = filename; self.recipientEmail = recipientEmail
        self.notifyOnOpen = notifyOnOpen; self.passphraseSalt = passphraseSalt
        self.passphraseHash = passphraseHash; self.passphraseKdf = passphraseKdf
        self.paddingVersion = paddingVersion
    }
}

extension CreateShareRequest {
    enum CodingKeys: String, CodingKey {
        case type, size, rawSize, expiresIn, maxOpens, label, filename
        case recipientEmail, notifyOnOpen, passphraseSalt, passphraseHash
        case passphraseKdf, paddingVersion
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(size, forKey: .size)
        try c.encodeIfPresent(rawSize, forKey: .rawSize)
        try c.encode(expiresIn, forKey: .expiresIn)
        try c.encode(maxOpens, forKey: .maxOpens)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encodeIfPresent(filename, forKey: .filename)
        try c.encodeIfPresent(recipientEmail, forKey: .recipientEmail)
        try c.encodeIfPresent(notifyOnOpen, forKey: .notifyOnOpen)
        try c.encodeIfPresent(passphraseSalt, forKey: .passphraseSalt)
        try c.encodeIfPresent(passphraseHash, forKey: .passphraseHash)
        try c.encodeIfPresent(passphraseKdf, forKey: .passphraseKdf)
        try c.encodeIfPresent(paddingVersion, forKey: .paddingVersion)
    }
}

public struct CreateShareResponse: Decodable {
    public let id: String
    public let uploadUrl: String?
}

public struct WhoAmI: Decodable {
    public let userId: String
    public let email: String?
    public let scopes: [String]
    /// Effective plan name (`free` / `pro` / `internal`); nil on an older server.
    public let plan: String?
    /// Effective plan limits used to filter the option lists; nil on an older server.
    public let limits: PlanLimits?
}

public struct ShareRow: Decodable, Identifiable {
    public let id: String
    public let type: String
    public let label: String?
    public let filename: String?
    public let size: Int?
    public let maxOpens: Int
    public let opensUsed: Int
    public let expiresAt: Int?
    public let createdAt: Int?
    public let burnedAt: Int?
    public let revokedAt: Int?

    enum CodingKeys: String, CodingKey {
        case id, type, label, filename, size, maxOpens, opensUsed
        case expiresAt, createdAt, burnedAt, revokedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(String.self, forKey: .type)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        filename = try c.decodeIfPresent(String.self, forKey: .filename)
        size = try c.decodeIfPresent(Int.self, forKey: .size)
        maxOpens = try c.decode(Int.self, forKey: .maxOpens)
        opensUsed = try c.decode(Int.self, forKey: .opensUsed)
        expiresAt = ShareRow.epoch(c, .expiresAt)
        createdAt = ShareRow.epoch(c, .createdAt)
        burnedAt = ShareRow.epoch(c, .burnedAt)
        revokedAt = ShareRow.epoch(c, .revokedAt)
    }

    /// A timestamp may arrive as epoch seconds (Int, the normalized wire shape)
    /// or as an ISO-8601 string (a JSON-serialized Date). Returns epoch
    /// seconds, or nil when absent / null / unparseable.
    private static func epoch(_ c: KeyedDecodingContainer<CodingKeys>,
                              _ key: CodingKeys) -> Int? {
        if let i = try? c.decode(Int.self, forKey: key) { return i }
        if let s = try? c.decode(String.self, forKey: key) {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return Int(d.timeIntervalSince1970) }
            f.formatOptions = [.withInternetDateTime]   // some strings lack fractional seconds
            if let d = f.date(from: s) { return Int(d.timeIntervalSince1970) }
        }
        return nil
    }
}

public struct ShareListResponse: Decodable { public let shares: [ShareRow] }

// MARK: - Request links (owner-side create + track)

/// Body for POST /api/cli/requests. `label` is omitted from the wire when nil.
public struct CreateRequestRequest: Encodable {
    public let label: String?
    public let expiresIn: String
    public let maxSubmissions: Int
    public init(label: String?, expiresIn: String, maxSubmissions: Int = 1) {
        self.label = label; self.expiresIn = expiresIn; self.maxSubmissions = maxSubmissions
    }
    enum CodingKeys: String, CodingKey { case label, expiresIn, maxSubmissions }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(label, forKey: .label)   // omit nil
        try c.encode(expiresIn, forKey: .expiresIn)
        try c.encode(maxSubmissions, forKey: .maxSubmissions)
    }
}

/// A request-link row from GET /api/cli/requests. Timestamps are epoch seconds
/// (the endpoint normalizes its Date columns to integers), so they decode
/// as `Int?` with a plain JSONDecoder — same convention as `ShareRow`.
public struct RequestRow: Decodable, Identifiable {
    public let id: String
    public let label: String?
    public let maxSubmissions: Int
    public let submissionsUsed: Int
    public let expiresAt: Int?
    public let createdAt: Int?
    public let submittedAt: Int?
    public let burnedAt: Int?
    public let revokedAt: Int?
    public let contentType: String?
    public let filename: String?
    public let size: Int?
}
public struct RequestListResponse: Decodable { public let requests: [RequestRow] }
public struct CreatedRequest: Decodable { public let id: String }

// MARK: - Inbox (owner reads a submission)

/// A submitted-request payload from GET /api/cli/inbox/{id}. Raw AES-GCM (no
/// padding) — decrypt with Crypto.aesGcmDecrypt and use the plaintext directly.
public struct InboxMeta: Decodable {
    public let contentType: String          // "text" | "file" | "note"
    public let size: Int
    public let filename: String?
    public let ciphertext: String?          // text/note: base64url inline
    public let downloadUrl: String?         // file: presigned R2 GET
}

/// Public request info from GET /api/requests/{id}/info.
public struct RequestInfo: Decodable {
    public let label: String?
    public let expiresAt: Int
}
