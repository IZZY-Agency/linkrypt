import SwiftUI
import UniformTypeIdentifiers

/// Window-level file drop. While the composer is busy or locked it proposes no
/// operation, so Finder shows no copy badge and the drop is refused.
///
/// Dropped URLs load asynchronously. An accepted drop is announced through
/// `began` inside `performDrop`, before any loading starts, so the composer can
/// switch to the file tab and hold off sending until `finished` delivers what
/// the drop produced. `finished` runs exactly once per `began`, at the latest
/// after `loadTimeout`: an item that has not loaded by then is reported as
/// failed, and its late answer is ignored.
struct FileDropDelegate: DropDelegate {
    /// What one accepted drop produced.
    struct Delivery {
        /// The loaded file URLs, in drop order.
        let urls: [URL]
        /// Items whose file URL could not be loaded, or did not load in time.
        let failed: Int
    }

    /// How long one drop may take to load before its missing items are given up.
    static let loadTimeout: TimeInterval = 30

    let isOpen: @MainActor () -> Bool
    let targeted: (Bool) -> Void
    let began: @MainActor () -> Void
    let finished: @MainActor (Delivery) -> Void

    func validateDrop(info: DropInfo) -> Bool { isOpen() && info.hasItemsConforming(to: [.fileURL]) }
    func dropEntered(info: DropInfo) { targeted(isOpen()) }
    func dropExited(info: DropInfo) { targeted(false) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        targeted(isOpen())
        return DropProposal(operation: isOpen() ? .copy : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool {
        targeted(false)
        guard isOpen() else { return false }
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        began()
        Self.loadURLs(from: providers, then: finished)
        return true
    }

    /// Loads every provider's file URL and calls `then` exactly once, on the
    /// main actor, with the loaded URLs in provider order and the number that
    /// failed: when the last item answers, or after `timeout`, whichever is first.
    static func loadURLs(from providers: [NSItemProvider], timeout: TimeInterval = loadTimeout,
                         then: @escaping @MainActor (Delivery) -> Void) {
        let box = URLBox(count: providers.count)
        let group = DispatchGroup()
        for (i, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    if !box.delivered { box.urls[i] = url }   // an answer after the timeout is ignored
                    group.leave()
                }
            }
        }
        let deliver: @MainActor () -> Void = {
            guard !box.delivered else { return }
            box.delivered = true
            let loaded = box.urls.compactMap { $0 }
            then(Delivery(urls: loaded, failed: box.urls.count - loaded.count))
        }
        group.notify(queue: .main) { MainActor.assumeIsolated { deliver() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { MainActor.assumeIsolated { deliver() } }
    }
}

/// Collects dropped URLs by index; only touched on the main queue.
private final class URLBox: @unchecked Sendable {
    var urls: [URL?]
    /// Set once the drop has been delivered; later answers change nothing.
    var delivered = false
    init(count: Int) { urls = Array(repeating: nil, count: count) }
}
