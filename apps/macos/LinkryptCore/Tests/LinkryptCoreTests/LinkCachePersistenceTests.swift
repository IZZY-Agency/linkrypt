import XCTest
@testable import LinkryptCore

/// A store whose wipe() fails, to prove setPersistent/clearAll surface the
/// failure instead of presenting a false "off/cleared" state.
private final class FailingWipeStore: LinkCacheStore {
    private var dict: [String: String]
    init(_ seed: [String: String] = [:]) { dict = seed }
    func load() -> [String: String] { dict }
    func save(_ d: [String: String]) { dict = d }
    func wipe() throws { throw LinkCacheError.wipeFailed(-25300) }
}

final class LinkCachePersistenceTests: XCTestCase {
    func testPersistentByDefaultLoadsAndSaves() {
        let store = InMemoryLinkCacheStore()
        let cache = LinkCache(store: store, persistent: true)
        cache.store(id: "a", url: "u-a")
        XCTAssertEqual(store.load(), ["a": "u-a"])     // written through
        XCTAssertTrue(cache.isPersistent)
    }

    func testSetPersistentFalseWipesStoreButKeepsSession() throws {
        let store = InMemoryLinkCacheStore()
        let cache = LinkCache(store: store, persistent: true)
        cache.store(id: "a", url: "u-a")
        try cache.setPersistent(false)
        XCTAssertFalse(cache.isPersistent)
        XCTAssertEqual(store.load(), [:])               // keychain blob wiped
        XCTAssertEqual(cache.url(for: "a"), "u-a")      // session entry retained
        cache.store(id: "b", url: "u-b")               // new entries not persisted while off
        XCTAssertEqual(store.load(), [:])
        XCTAssertEqual(cache.url(for: "b"), "u-b")
    }

    func testSetPersistentTrueRepersistsSession() throws {
        let store = InMemoryLinkCacheStore()
        let cache = LinkCache(store: store, persistent: false)
        cache.store(id: "a", url: "u-a")
        XCTAssertEqual(store.load(), [:])               // not persisted while off
        try cache.setPersistent(true)
        XCTAssertEqual(store.load(), ["a": "u-a"])      // session flushed to store
    }

    func testClearAllEmptiesBoth() throws {
        let store = InMemoryLinkCacheStore()
        let cache = LinkCache(store: store, persistent: true)
        cache.store(id: "a", url: "u-a")
        try cache.clearAll()
        XCTAssertNil(cache.url(for: "a"))
        XCTAssertEqual(store.load(), [:])
    }

    func testWipeFailureThrowsAndDoesNotFlipState() {
        let cache = LinkCache(store: FailingWipeStore(["a": "u-a"]), persistent: true)
        XCTAssertThrowsError(try cache.setPersistent(false))
        XCTAssertTrue(cache.isPersistent, "must stay persistent on wipe failure")
    }
}
