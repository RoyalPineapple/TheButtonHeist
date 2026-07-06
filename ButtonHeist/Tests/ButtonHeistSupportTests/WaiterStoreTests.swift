import ButtonHeistSupport
import Testing

@Suite struct WaiterStoreTests {
    @Test func `reserved waiter can be removed once`() {
        var store = WaiterStore<UInt64, Int>()
        let id = store.reserveID()

        store.insert(7, id: id)

        #expect(store.count == 1)
        #expect(store.remove(id: id) == 7)
        #expect(store.remove(id: id) == nil)
        #expect(store.isEmpty)
    }

    @Test func `remove all where leaves non matching waiters`() {
        var store = WaiterStore<UInt64, String>()
        let keepID = store.insert("keep")
        let dropID = store.insert("drop")

        let removed = store.removeAll { $0 == "drop" }

        #expect(removed == ["drop"])
        #expect(store.count == 1)
        #expect(store.remove(id: keepID) == "keep")
        #expect(store.remove(id: dropID) == nil)
    }
}
