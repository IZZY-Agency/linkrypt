import Foundation

/// base64url without padding — matches `URL_SAFE_NO_PAD` (Rust) and the
/// browser fragment encoding. The AES key/iv/salt/hash all travel this way.
public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        var s = data.base64EncodedString()
        s = s.replacingOccurrences(of: "+", with: "-")
             .replacingOccurrences(of: "/", with: "_")
        // strip trailing '=' padding (base64url is unpadded)
        return String(s.reversed().drop(while: { $0 == "=" }).reversed())
    }

    public static func decode(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+")
                      .replacingOccurrences(of: "_", with: "/")
        let rem = s.count % 4
        if rem > 0 { s += String(repeating: "=", count: 4 - rem) }
        return Data(base64Encoded: s)
    }
}
