import Foundation

/// The token owner's EFFECTIVE plan limits as reported by `/api/cli/whoami`
/// (admin → `internal`). Pure value type: the composer, the ⌥⇧V overlay and
/// Settings › Sharing filter their option lists through it so the app never
/// offers an expiry / opens count / feature the server's share-create gates
/// would reject with 402 "Plan limit".
///
/// `nil` caps mean "unlimited" (the server sends JSON `null`). A missing
/// `limits` object altogether (older server) decodes to `nil` on `WhoAmI`
/// and is treated as unrestricted — see the `Optional` extension below.
public struct PlanLimits: Decodable, Equatable, Sendable {
    public struct Features: Decodable, Equatable, Sendable {
        public let requestLinks: Bool
        public let emailRecipient: Bool
        public let notifyOnOpen: Bool
        public let passphrase: Bool
        public init(requestLinks: Bool, emailRecipient: Bool, notifyOnOpen: Bool, passphrase: Bool) {
            self.requestLinks = requestLinks; self.emailRecipient = emailRecipient
            self.notifyOnOpen = notifyOnOpen; self.passphrase = passphrase
        }
    }

    /// Accepted `expiresIn` keys (`"1h"`, `"24h"`, …), server order.
    public let expiresIn: [String]
    public let maxOpensPerShare: Int?
    public let maxFileSizeBytes: Int?
    public let features: Features

    public init(expiresIn: [String], maxOpensPerShare: Int?, maxFileSizeBytes: Int?, features: Features) {
        self.expiresIn = expiresIn; self.maxOpensPerShare = maxOpensPerShare
        self.maxFileSizeBytes = maxFileSizeBytes; self.features = features
    }

    public func allows(expiry: String) -> Bool { expiresIn.contains(expiry) }
    public func allows(opens: Int) -> Bool { maxOpensPerShare.map { opens <= $0 } ?? true }

    /// `candidates` minus what the plan rejects, in the caller's order.
    public func filter(expiries candidates: [String]) -> [String] { candidates.filter(allows(expiry:)) }
    public func filter(opens candidates: [Int]) -> [Int] { candidates.filter(allows(opens:)) }

    /// `preferred` if allowed, else the first allowed candidate. Falls back to
    /// `preferred` when nothing is allowed so the server still gets to answer.
    public func clamp(expiry preferred: String, candidates: [String]) -> String {
        allows(expiry: preferred) ? preferred : (filter(expiries: candidates).first ?? preferred)
    }
    public func clamp(opens preferred: Int, candidates: [Int]) -> Int {
        allows(opens: preferred) ? preferred : (filter(opens: candidates).first ?? preferred)
    }
}

/// `nil` limits (server predates the field, or whoami hasn't loaded yet) =
/// unrestricted: offer everything and let the server's 402 be the backstop.
public extension Optional where Wrapped == PlanLimits {
    func filter(expiries candidates: [String]) -> [String] { self?.filter(expiries: candidates) ?? candidates }
    func filter(opens candidates: [Int]) -> [Int] { self?.filter(opens: candidates) ?? candidates }
    func clamp(expiry preferred: String, candidates: [String]) -> String {
        self?.clamp(expiry: preferred, candidates: candidates) ?? preferred
    }
    func clamp(opens preferred: Int, candidates: [Int]) -> Int {
        self?.clamp(opens: preferred, candidates: candidates) ?? preferred
    }
    func allows(feature: KeyPath<PlanLimits.Features, Bool>) -> Bool {
        self.map { $0.features[keyPath: feature] } ?? true
    }
}
