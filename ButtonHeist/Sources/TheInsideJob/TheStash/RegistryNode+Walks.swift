#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser

// MARK: - Registry Node Fold

extension TheStash.RegistryNode {

    /// Bottom-up fold to an arbitrary type. Container closures receive
    /// already-folded child results, mirroring `AccessibilityHierarchy.folded`.
    func folded<Result>(
        onElement: (TheStash.ScreenElement) -> Result,
        onContainer: (TheStash.RegistryContainerEntry, [Result]) -> Result
    ) -> Result {
        switch self {
        case .element(let element):
            return onElement(element)
        case .container(let entry, let children):
            return onContainer(entry, children.map {
                $0.folded(onElement: onElement, onContainer: onContainer)
            })
        }
    }

    /// Bottom-up structural rewrite with optional drops. The container closure
    /// receives only the surviving children — nils are filtered before the
    /// callback runs. A container whose closure returns nil is itself dropped.
    func mapTree(
        onElement: (TheStash.ScreenElement) -> TheStash.RegistryNode?,
        onContainer: (TheStash.RegistryContainerEntry, [TheStash.RegistryNode]) -> TheStash.RegistryNode?
    ) -> TheStash.RegistryNode? {
        switch self {
        case .element(let element):
            return onElement(element)
        case .container(let entry, let children):
            let surviving = children.compactMap {
                $0.mapTree(onElement: onElement, onContainer: onContainer)
            }
            return onContainer(entry, surviving)
        }
    }

}

extension Array where Element == TheStash.RegistryNode {

    /// Bottom-up fold across a forest. One Result per root.
    func folded<Result>(
        onElement: (TheStash.ScreenElement) -> Result,
        onContainer: (TheStash.RegistryContainerEntry, [Result]) -> Result
    ) -> [Result] {
        map { $0.folded(onElement: onElement, onContainer: onContainer) }
    }

    /// Bottom-up structural rewrite across a forest. Roots that map to nil
    /// are dropped.
    func mapTree(
        onElement: (TheStash.ScreenElement) -> TheStash.RegistryNode?,
        onContainer: (TheStash.RegistryContainerEntry, [TheStash.RegistryNode]) -> TheStash.RegistryNode?
    ) -> [TheStash.RegistryNode] {
        compactMap { $0.mapTree(onElement: onElement, onContainer: onContainer) }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
