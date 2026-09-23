import Foundation

/// Decouples a cold-launch file-open event from the not-yet-wired consumer:
/// buffers URLs received before `onReady`, then delivers them once when the
/// consumer registers. Used only from the main actor (the AppDelegate owns it).
public final class DropBuffer {
    private var sink: (([URL]) -> Void)?
    private var buffered: [URL] = []

    public init() {}

    public func receive(_ urls: [URL]) {
        if let sink { sink(urls) } else { buffered.append(contentsOf: urls) }
    }

    public func onReady(_ sink: @escaping ([URL]) -> Void) {
        self.sink = sink
        guard !buffered.isEmpty else { return }
        let pending = buffered
        buffered.removeAll()
        sink(pending)
    }
}
