package struct AsyncWaiterRegistry<Key: Hashable, Value: Sendable> {
    private var waiters: [Key: TimedOneShot<Value>] = [:]

    package init() {}

    package var count: Int {
        waiters.count
    }

    package var isEmpty: Bool {
        waiters.isEmpty
    }

    package mutating func insert(_ waiter: TimedOneShot<Value>, for key: Key) {
        precondition(waiters[key] == nil, "AsyncWaiterRegistry registered duplicate waiter key")
        waiters[key] = waiter
    }

    package mutating func remove(_ key: Key) -> TimedOneShot<Value>? {
        waiters.removeValue(forKey: key)
    }

    @discardableResult
    package mutating func resolve(_ key: Key, returning value: Value) -> Bool {
        guard let waiter = waiters.removeValue(forKey: key) else { return false }
        return waiter.resolve(returning: value)
    }

    package mutating func removeAll() -> [TimedOneShot<Value>] {
        let removed = Array(waiters.values)
        waiters.removeAll()
        return removed
    }

    package mutating func removeAll(where shouldRemove: (Key) -> Bool) -> [(key: Key, waiter: TimedOneShot<Value>)] {
        var removed: [(key: Key, waiter: TimedOneShot<Value>)] = []
        for key in Array(waiters.keys) where shouldRemove(key) {
            if let waiter = waiters.removeValue(forKey: key) {
                removed.append((key, waiter))
            }
        }
        return removed
    }
}
