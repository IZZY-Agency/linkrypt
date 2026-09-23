import Foundation

public enum APIError: Error, Equatable {
    case unauthorized                          // 401
    case planLimit(limit: String, upgrade: String)  // 402
    case forbidden(message: String)            // 403
    case server(status: Int, message: String)  // other non-2xx
    case network(String)
    case decoding(String)
    case insufficientScope(missing: [String])  // client-side scope check
}
