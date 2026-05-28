import Foundation
import AccessibilitySnapshotModel

public extension AccessibilityTrace {
    enum AccessibilityPatchOperation: Codable, Sendable, Equatable {
        case updateElement(
            path: TreePath,
            element: AccessibilityElement
        )
        case updateContainer(
            path: TreePath,
            container: AccessibilityContainer
        )
        case insertSubtree(TreeInsertion)
        case removeSubtree(TreeRemoval)
        case moveSubtree(
            TreeMove,
            node: AccessibilityHierarchy
        )
        case replaceTree(
            tree: [AccessibilityHierarchy]
        )
    }

    struct AccessibilityPatch: Codable, Sendable, Equatable {
        public let operations: [AccessibilityPatchOperation]
        public let timestamp: Date
        public let annotations: InterfaceAnnotations
        public let context: Context
        public let transition: Transition

        public init(
            operations: [AccessibilityPatchOperation],
            timestamp: Date,
            annotations: InterfaceAnnotations,
            context: Context,
            transition: Transition = .empty
        ) {
            self.operations = operations
            self.timestamp = timestamp
            self.annotations = annotations
            self.context = context
            self.transition = transition
        }
    }
}
