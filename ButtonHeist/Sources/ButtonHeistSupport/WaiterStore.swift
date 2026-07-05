package struct WaiterStore<Waiter> {
    private var nextID: UInt64 = 0
    private var storage: [UInt64: Waiter] = [:]

    package init() {}

    package var count: Int {
        storage.count
    }

    package var isEmpty: Bool {
        storage.isEmpty
    }

    package mutating func reserveID() -> UInt64 {
        defer { nextID &+= 1 }
        return nextID
    }

    @discardableResult
    package mutating func insert(_ waiter: Waiter) -> UInt64 {
        let id = reserveID()
        insert(waiter, id: id)
        return id
    }

    package mutating func insert(_ waiter: Waiter, id: UInt64) {
        precondition(storage[id] == nil, "WaiterStore registered duplicate waiter id")
        storage[id] = waiter
    }

    package mutating func remove(id: UInt64) -> Waiter? {
        storage.removeValue(forKey: id)
    }

    package mutating func removeAll() -> [Waiter] {
        let waiters = Array(storage.values)
        storage.removeAll()
        return waiters
    }

    package mutating func removeAll(where shouldRemove: (Waiter) -> Bool) -> [Waiter] {
        var removed: [Waiter] = []
        for id in Array(storage.keys) {
            guard let waiter = storage[id], shouldRemove(waiter) else { continue }
            if let waiter = storage.removeValue(forKey: id) {
                removed.append(waiter)
            }
        }
        return removed
    }

    package mutating func updateAll(_ update: (inout Waiter) -> Void) {
        for id in Array(storage.keys) {
            guard var waiter = storage[id] else { continue }
            update(&waiter)
            storage[id] = waiter
        }
    }
}

package func waiterTimeout(
    after duration: Duration,
    _ operation: @escaping @Sendable () async -> Void
) -> Task<Void, Never> {
    Task {
        _ = try? await Task.sleep(for: duration)
        guard !Task.isCancelled else { return }
        await operation()
    }
}
