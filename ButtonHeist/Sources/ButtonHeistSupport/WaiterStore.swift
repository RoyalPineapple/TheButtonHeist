package struct WaiterStoreRemoval<Key: Hashable, Waiter> {
    package let key: Key
    package let waiter: Waiter

    package init(key: Key, waiter: Waiter) {
        self.key = key
        self.waiter = waiter
    }
}

extension WaiterStoreRemoval: Equatable where Key: Equatable, Waiter: Equatable {}
extension WaiterStoreRemoval: Sendable where Key: Sendable, Waiter: Sendable {}

package struct WaiterStore<Key: Hashable, Waiter> {
    private var nextID: UInt64 = 0
    private var storage: [Key: Waiter] = [:]

    package init() {}

    package var count: Int {
        storage.count
    }

    package var isEmpty: Bool {
        storage.isEmpty
    }

    package mutating func insert(_ waiter: Waiter, for key: Key) {
        precondition(storage[key] == nil, "WaiterStore registered duplicate waiter key")
        storage[key] = waiter
    }

    package mutating func remove(_ key: Key) -> Waiter? {
        storage.removeValue(forKey: key)
    }

    package mutating func removeAll() -> [Waiter] {
        let waiters = Array(storage.values)
        storage.removeAll()
        return waiters
    }

    package mutating func removeAll(where shouldRemove: (Key, Waiter) -> Bool) -> [WaiterStoreRemoval<Key, Waiter>] {
        var removed: [WaiterStoreRemoval<Key, Waiter>] = []
        for key in Array(storage.keys) {
            guard let waiter = storage[key], shouldRemove(key, waiter) else { continue }
            if let waiter = storage.removeValue(forKey: key) {
                removed.append(WaiterStoreRemoval(key: key, waiter: waiter))
            }
        }
        return removed
    }

    package mutating func updateAll(_ update: (Key, inout Waiter) -> Void) {
        for key in Array(storage.keys) {
            guard var waiter = storage[key] else { continue }
            update(key, &waiter)
            storage[key] = waiter
        }
    }
}

extension WaiterStore: Sendable where Key: Sendable, Waiter: Sendable {}

package extension WaiterStore where Key == UInt64 {
    mutating func reserveID() -> UInt64 {
        defer { nextID &+= 1 }
        return nextID
    }

    @discardableResult
    mutating func insert(_ waiter: Waiter) -> UInt64 {
        let id = reserveID()
        insert(waiter, id: id)
        return id
    }

    mutating func insert(_ waiter: Waiter, id: UInt64) {
        insert(waiter, for: id)
    }

    mutating func remove(id: UInt64) -> Waiter? {
        remove(id)
    }

    mutating func removeAll(where shouldRemove: (Waiter) -> Bool) -> [Waiter] {
        removeAll { _, waiter in shouldRemove(waiter) }.map(\.waiter)
    }

    mutating func updateAll(_ update: (inout Waiter) -> Void) {
        updateAll { _, waiter in update(&waiter) }
    }
}

package extension WaiterStore {
    @discardableResult
    mutating func resolve<Value>(_ key: Key, returning value: Value) -> Bool where Waiter == TimedOneShot<Value> {
        guard let waiter = remove(key) else { return false }
        return waiter.resolve(returning: value)
    }

    mutating func removeAll<Value>(where shouldRemove: (Key) -> Bool) -> [WaiterStoreRemoval<Key, TimedOneShot<Value>>] where Waiter == TimedOneShot<Value> {
        removeAll { key, _ in shouldRemove(key) }
    }
}
