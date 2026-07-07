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

        let removed = store.removeAll { key, waiter in
            key == dropID && waiter == "drop"
        }

        #expect(removed == [WaiterStoreRemoval(key: dropID, waiter: "drop")])
        #expect(store.count == 1)
        #expect(store.remove(id: keepID) == "keep")
        #expect(store.remove(id: dropID) == nil)
    }

    @Test func `uint64 convenience remove all still returns waiters only`() {
        var store = WaiterStore<UInt64, String>()
        _ = store.insert("keep")
        _ = store.insert("drop")

        let removed = store.removeAll { $0 == "drop" }

        #expect(removed == ["drop"])
        #expect(store.count == 1)
    }
}
