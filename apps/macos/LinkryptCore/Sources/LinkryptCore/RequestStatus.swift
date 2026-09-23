import Foundation

/// Owner-facing status of a request, by lifecycle precedence.
public enum RequestStatus {
    public static func of(_ r: RequestRow, now: Int) -> String {
        if r.revokedAt != nil { return "revoked" }
        if r.burnedAt != nil { return "burned" }
        if r.submittedAt != nil { return "submitted" }   // a submission arrived, even past expiry
        // `<=`: the server's submit path uses `expires_at > now` (strict), so a
        // request at exactly `expiresAt == now` is already refused — show it as
        // expired here too, not pending.
        if let exp = r.expiresAt, exp <= now { return "expired" }
        return "pending"
    }
}
