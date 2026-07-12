package extension Sequence where Element: Equatable {
    func uniqued() -> [Element] {
        reduce(into: []) { elements, element in
            if !elements.contains(element) {
                elements.append(element)
            }
        }
    }
}

package extension Sequence {
    func uniqued<Key: Hashable>(
        on key: (Element) -> Key,
        excluding initialKeys: Set<Key> = []
    ) -> [Element] {
        var seen = initialKeys
        return filter { seen.insert(key($0)).inserted }
    }
}
