import Foundation

/// The files picked in the composer, with everything needed to decide — before
/// any network call — whether they can be sent: display names, the exact
/// payload size and the problems that block sending.
public struct FileSelection: Equatable {
    public struct Item: Equatable {
        public let url: URL
        public let size: Int
    }

    public enum Problem: Error, Equatable {
        case empty
        case tooMany
        case overBundleCap
        /// The payload is larger than one share can carry (`Padding.maxPlaintext`).
        case overFormatCap
        case overPlan
        /// Produced by the post-read check when a file changed while being read.
        case changed
        case unreadable
    }

    public private(set) var items: [Item] = []

    public init() {}

    /// Appends the acceptable URLs in order and returns the rejected ones with
    /// their reason. The same URL may be added more than once.
    @discardableResult
    public mutating func add(_ urls: [URL]) -> [(url: URL, reason: DroppedFile.Rejection)] {
        var rejected: [(url: URL, reason: DroppedFile.Rejection)] = []
        for url in urls {
            if let reason = DroppedFile.rejectionReason(url) {
                rejected.append((url, reason))
            } else if let size = Self.currentSize(of: url) {
                items.append(Item(url: url, size: size))
            } else {
                rejected.append((url, .unsupported))
            }
        }
        return rejected
    }

    public mutating func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
    }

    public mutating func removeAll() { items.removeAll() }

    /// One item keeps its real file name; two or more get the unique bundle entry names.
    public var displayNames: [String] {
        items.count == 1
            ? [items[0].url.lastPathComponent]
            : FileBundle.uniqueNames(items.map { $0.url.lastPathComponent })
    }

    /// Bytes that will be encrypted and uploaded: the file itself for one item,
    /// the exact bundle size for two or more.
    public var payloadBytes: Int { Self.payload(names: displayNames, sizes: items.map(\.size)) }

    /// Problem based on the sizes recorded when the files were added.
    public func problem(planMaxBytes: Int?) -> Problem? {
        Self.problem(count: items.count, names: displayNames, sizes: items.map(\.size), planMaxBytes: planMaxBytes)
    }

    /// Re-reads every file's current size from disk and runs the same checks on
    /// those sizes. On success returns those live sizes, in list order, so the
    /// caller can verify that what it reads matches what was checked; a file
    /// that cannot be read yields `.unreadable`.
    public func livePreflight(planMaxBytes: Int?) -> Result<[Int], Problem> {
        var live: [Int] = []
        for item in items {
            guard let size = Self.currentSize(of: item.url) else { return .failure(.unreadable) }
            live.append(size)
        }
        if let problem = Self.problem(count: items.count, names: displayNames, sizes: live, planMaxBytes: planMaxBytes) {
            return .failure(problem)
        }
        return .success(live)
    }

    /// Payload bytes for the given sizes (one per item, in list order). A size
    /// list that does not match the items yields `Int.max`, so callers fail closed.
    public func payloadBytes(forSizes sizes: [Int]) -> Int {
        guard sizes.count == items.count else { return Int.max }
        return Self.payload(names: displayNames, sizes: sizes)
    }

    // MARK: - Private

    private static func payload(names: [String], sizes: [Int]) -> Int {
        switch sizes.count {
        case 0: return 0
        case 1: return sizes[0]
        default: return FileBundle.size(names: names, sizes: sizes)
        }
    }

    private static func problem(count: Int, names: [String], sizes: [Int], planMaxBytes: Int?) -> Problem? {
        if count == 0 { return .empty }
        if count > FileBundle.maxEntries { return .tooMany }
        let payload = payload(names: names, sizes: sizes)
        if count >= 2, payload > FileBundle.maxBytes { return .overBundleCap }
        // Only a single file can reach this: two or more are capped at 1 GiB above.
        if payload > Padding.maxPlaintext { return .overFormatCap }
        if let limit = planMaxBytes, payload > limit { return .overPlan }
        return nil
    }

    /// Current on-disk size, bypassing any cached resource values.
    private static func currentSize(of url: URL) -> Int? {
        let fresh = URL(fileURLWithPath: url.path)
        return (try? fresh.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }
}
