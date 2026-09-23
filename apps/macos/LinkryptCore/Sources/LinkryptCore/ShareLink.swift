import Foundation

public enum ShareLink {
    public static func buildFragment(key: Data, iv: Data) -> String {
        "k=\(Base64URL.encode(key))&iv=\(Base64URL.encode(iv))"
    }

    /// Recipient URL. The `/{lang}/` segment is MANDATORY — the server's
    /// share-email validator rejects `/s/{id}` without a locale, and the page
    /// route is `[lang]/s/[id]`. Default lang is "en".
    public static func recipientURL(baseURL: String, lang: String = "en",
                                    id: String, key: Data, iv: Data) -> String {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return "\(base)/\(lang)/s/\(id)#\(buildFragment(key: key, iv: iv))"
    }

    /// Request link the owner shares — KEYLESS (the submitter generates the key
    /// at submit time). `{base}/{lang}/r/{id}`.
    public static func requestURL(baseURL: String, lang: String = "en", id: String) -> String {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return "\(base)/\(lang)/r/\(id)"
    }

    /// Not `Equatable` on purpose: it holds the secret `key`/`iv`, and `Data`
    /// equality isn't constant-time — compare individual non-secret fields if
    /// needed, never the whole struct.
    public struct ParsedShareLink {
        public let baseURL: String
        public let id: String
        public let key: Data
        public let iv: Data
    }

    /// Parse a recipient URL `https://host[:port][/lang]/s/{id}#k=…&iv=…`.
    /// Returns nil unless: scheme is https, a host is present, no userinfo, the
    /// path is exactly `/s/{id}` or `/{lang}/s/{id}` (2-letter lang), and the
    /// fragment yields a 32-byte key + 12-byte iv.
    public static func parse(_ url: String) -> ParsedShareLink? {
        guard let c = URLComponents(string: url),
              c.scheme == "https", let host = c.host,
              c.user == nil, c.password == nil else { return nil }
        let segs = c.path.split(separator: "/").map(String.init)
        let id: String
        if segs.count == 2, segs[0] == "s" {
            id = segs[1]
        } else if segs.count == 3, segs[1] == "s",
                  segs[0].range(of: #"^[a-z]{2}$"#, options: .regularExpression) != nil {
            id = segs[2]
        } else {
            return nil
        }
        guard !id.isEmpty, let frag = c.fragment, let parts = parseFragment(frag),
              parts.key.count == Crypto.keyLen, parts.iv.count == Crypto.ivLen else { return nil }
        var base = "https://\(host)"
        if let port = c.port { base += ":\(port)" }
        return ParsedShareLink(baseURL: base, id: id, key: parts.key, iv: parts.iv)
    }

    public static func parseFragment(_ fragment: String) -> (key: Data, iv: Data)? {
        var k: Data?; var iv: Data?
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            if kv[0] == "k" { k = Base64URL.decode(String(kv[1])) }
            if kv[0] == "iv" { iv = Base64URL.decode(String(kv[1])) }
        }
        guard let key = k, let ivv = iv else { return nil }
        return (key, ivv)
    }
}

/// Parse an owner inbox link `https://host/app/inbox/{id}#k=…&iv=…` (the URL the
/// owner receives by email). Returns nil unless: https, host present, no
/// userinfo, path exactly `/app/inbox/{id}`, fragment yields 32-byte key + 12-byte iv.
public enum InboxLink {
    public struct Parsed {
        public let baseURL: String
        public let id: String
        public let key: Data
        public let iv: Data
    }
    public static func parse(_ url: String) -> Parsed? {
        guard let c = URLComponents(string: url),
              c.scheme == "https", let host = c.host,
              c.user == nil, c.password == nil else { return nil }
        let segs = c.path.split(separator: "/").map(String.init)
        guard segs.count == 3, segs[0] == "app", segs[1] == "inbox", !segs[2].isEmpty else { return nil }
        guard let frag = c.fragment, let parts = ShareLink.parseFragment(frag),
              parts.key.count == Crypto.keyLen, parts.iv.count == Crypto.ivLen else { return nil }
        var base = "https://\(host)"
        if let port = c.port { base += ":\(port)" }
        return Parsed(baseURL: base, id: segs[2], key: parts.key, iv: parts.iv)
    }
}

/// Parse a (keyless) request link `https://host[/lang]/r/{id}` the owner shares.
/// Returns nil unless: https, host present, no userinfo, path `/r/{id}` or
/// `/{lang}/r/{id}` (2-letter lang). No fragment needed (the submitter makes the key).
public enum RequestLink {
    public struct Parsed { public let baseURL: String; public let id: String }
    public static func parse(_ url: String) -> Parsed? {
        guard let c = URLComponents(string: url),
              c.scheme == "https", let host = c.host,
              c.user == nil, c.password == nil else { return nil }
        let segs = c.path.split(separator: "/").map(String.init)
        let id: String
        if segs.count == 2, segs[0] == "r" {
            id = segs[1]
        } else if segs.count == 3, segs[1] == "r",
                  segs[0].range(of: #"^[a-z]{2}$"#, options: .regularExpression) != nil {
            id = segs[2]
        } else {
            return nil
        }
        guard !id.isEmpty else { return nil }
        var base = "https://\(host)"
        if let port = c.port { base += ":\(port)" }
        return Parsed(baseURL: base, id: id)
    }
}
