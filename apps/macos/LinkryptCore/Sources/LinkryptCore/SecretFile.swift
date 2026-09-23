import Foundation

public enum SecretFileError: Error, Equatable {
    case tooLarge
    case notUTF8
}

/// Validates a file's bytes for use as a text-share secret. Cap is checked
/// before decode; decode is STRICT UTF-8 (`String(data:encoding:.utf8)` is nil
/// on any invalid byte — no lossy replacement), so binary/partial input fails
/// as `.notUTF8`. The app must ALSO preflight the file's on-disk size before
/// reading (see ComposerView) so a huge file never reaches here.
public enum SecretFile {
    public static func decode(_ data: Data) -> Result<String, SecretFileError> {
        guard Crypto.textPlaintextFitsCap(data.count) else { return .failure(.tooLarge) }
        guard let text = String(data: data, encoding: .utf8) else { return .failure(.notUTF8) }
        return .success(text)
    }
}
