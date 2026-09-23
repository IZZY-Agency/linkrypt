import XCTest
@testable import LinkryptCore

final class TokenStoreTests: XCTestCase {
    func testInMemoryRoundTrip() throws {
        let store = InMemoryTokenStore()
        XCTAssertNil(store.read(account: "https://linkrypt.sh"))
        try store.save(token: "tok_abc", account: "https://linkrypt.sh")
        XCTAssertEqual(store.read(account: "https://linkrypt.sh"), "tok_abc")
        try store.delete(account: "https://linkrypt.sh")
        XCTAssertNil(store.read(account: "https://linkrypt.sh"))
    }
    func testLinkCacheKeepsFragmentById() {
        let cache = LinkCache(store: InMemoryLinkCacheStore())
        XCTAssertNil(cache.url(for: "abc"))
        cache.store(id: "abc", url: "https://linkrypt.sh/en/s/abc#k=…")
        XCTAssertEqual(cache.url(for: "abc"), "https://linkrypt.sh/en/s/abc#k=…")
    }

    func testLinkCacheRemoveDeletesEntry() {
        let backingStore = InMemoryLinkCacheStore()
        let cache = LinkCache(store: backingStore)
        cache.store(id: "xyz", url: "https://linkrypt.sh/en/s/xyz#k=test")
        XCTAssertNotNil(cache.url(for: "xyz"))
        cache.remove(id: "xyz")
        XCTAssertNil(cache.url(for: "xyz"), "remove(id:) should delete the entry")
        // Persist check: re-init from same backing store confirms it's gone from storage
        let cache2 = LinkCache(store: backingStore)
        XCTAssertNil(cache2.url(for: "xyz"), "remove(id:) should persist deletion to backing store")
    }
}
