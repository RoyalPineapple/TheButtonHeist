import ThePlans
import Foundation
import AccessibilitySnapshotModel

public enum ScrollContainerAxis: String, Codable, Sendable {
    case none
    case horizontal
    case vertical
    case both
}

public enum ScrollContainerMetrics {
    public static let pageOverlap: Double = 44

    public static func axis(
        contentWidth: Double,
        contentHeight: Double,
        viewportWidth: Double,
        viewportHeight: Double
    ) -> ScrollContainerAxis {
        let horizontal = isScrollable(contentLength: contentWidth, viewportLength: viewportWidth)
        let vertical = isScrollable(contentLength: contentHeight, viewportLength: viewportHeight)

        switch (horizontal, vertical) {
        case (true, true):
            return .both
        case (true, false):
            return .horizontal
        case (false, true):
            return .vertical
        case (false, false):
            return .none
        }
    }

    public static func estimatedHorizontalPageScrolls(
        contentWidth: Double,
        viewportWidth: Double
    ) -> Int {
        estimatedPageScrolls(contentLength: contentWidth, viewportLength: viewportWidth)
    }

    public static func estimatedVerticalPageScrolls(
        contentHeight: Double,
        viewportHeight: Double
    ) -> Int {
        estimatedPageScrolls(contentLength: contentHeight, viewportLength: viewportHeight)
    }

    public static func estimatedPageScrolls(
        contentLength: Double,
        viewportLength: Double
    ) -> Int {
        guard contentLength.isFinite,
              viewportLength.isFinite,
              viewportLength > 0
        else {
            return 0
        }

        let scrollableDistance = contentLength - viewportLength
        guard scrollableDistance > 1 else { return 0 }

        let pageStep = max(1, viewportLength - pageOverlap)
        return Int(ceil(scrollableDistance / pageStep))
    }

    private static func isScrollable(
        contentLength: Double,
        viewportLength: Double
    ) -> Bool {
        guard contentLength.isFinite,
              viewportLength.isFinite,
              viewportLength > 0
        else {
            return false
        }

        return contentLength > viewportLength + 1
    }
}

// MARK: - Interface

/// Position of a node in an accessibility hierarchy forest.
///
/// Paths are root-relative child indexes. The first root is `[0]`; its second
/// child is `[0, 1]`. They are capture-local, not durable identities.
public struct TreePath: Codable, Equatable, Hashable, Sendable {
    public let indices: [Int]

    public init(_ indices: [Int]) {
        self.indices = indices
    }

    public static let root = TreePath([])

    public func appending(_ index: Int) -> TreePath {
        TreePath(indices + [index])
    }
}

extension TreePath: Comparable {
    public static func < (lhs: TreePath, rhs: TreePath) -> Bool {
        for (left, right) in zip(lhs.indices, rhs.indices) where left != right {
            return left < right
        }
        return lhs.indices.count < rhs.indices.count
    }
}

public struct ScrollInventory: Codable, Equatable, Hashable, Sendable {
    public let totalElementCount: Int?
    public let visibleIndices: [Int]

    public init(totalElementCount: Int?, visibleIndices: [Int]) {
        self.totalElementCount = totalElementCount
        self.visibleIndices = visibleIndices
    }
}

/// Button Heist metadata attached to one parser element.
///
/// `AccessibilityElement` is the accessibility fact. These annotations are
/// BH affordances derived from a parse: targeting metadata plus supported action
/// names. They are keyed by capture-local tree path so the accessibility tree
/// itself stays full-fidelity and unmodified.
public struct InterfaceElementAnnotation: Codable, Equatable, Hashable, Sendable {
    public let path: TreePath
    public let actions: [ElementAction]

    public init(
        path: TreePath,
        actions: [ElementAction]
    ) {
        self.path = path
        self.actions = actions
    }
}

/// Button Heist metadata attached to one parser container.
///
/// Container type, modal state, and geometry live on `AccessibilityContainer`.
/// The only BH addition is the generated container name used for subtree
/// targeting and tree-diff references within the current capture shape.
public struct InterfaceContainerAnnotation: Codable, Equatable, Hashable, Sendable {
    public let path: TreePath
    public let containerName: ContainerName?
    public let scrollInventory: ScrollInventory?

    public init(
        path: TreePath,
        containerName: ContainerName?,
        scrollInventory: ScrollInventory? = nil
    ) {
        self.path = path
        self.containerName = containerName
        self.scrollInventory = scrollInventory
    }
}

/// Button Heist annotations for an `AccessibilityHierarchy` capture.
public struct InterfaceAnnotations: Codable, Equatable, Hashable, Sendable {
    public static let empty = InterfaceAnnotations()

    public let elements: [InterfaceElementAnnotation]
    public let containers: [InterfaceContainerAnnotation]

    public init(
        elements: [InterfaceElementAnnotation] = [],
        containers: [InterfaceContainerAnnotation] = []
    ) {
        self.elements = elements
        self.containers = containers
    }

    public var elementByPath: [TreePath: InterfaceElementAnnotation] {
        Dictionary(elements.map { ($0.path, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    public var containerByPath: [TreePath: InterfaceContainerAnnotation] {
        Dictionary(containers.map { ($0.path, $0) }, uniquingKeysWith: { _, latest in latest })
    }
}

public struct InterfaceDiagnostics: Codable, Equatable, Sendable {
    public let discovery: InterfaceDiscoveryDiagnostics?

    public init(discovery: InterfaceDiscoveryDiagnostics? = nil) {
        self.discovery = discovery
    }
}

public enum InterfaceDiscoveryStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case complete
    case limited
}

public enum InterfaceDiscoveryReasonCode: String, Codable, Equatable, Hashable, Sendable, CaseIterable, Comparable {
    case discoveryScrollLimit = "scroll-attempt-budget"
    case containerScrollLimit = "container-scroll-budget"
    case leadingEdgeResetLimit = "leading-edge-reset-budget"
    case notExplored = "not-explored"

    public static func < (
        lhs: InterfaceDiscoveryReasonCode,
        rhs: InterfaceDiscoveryReasonCode
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct InterfaceDiscoveryDiagnostics: Codable, Equatable, Sendable {
    public let state: InterfaceDiscoveryStatus
    public let reasonCodes: [InterfaceDiscoveryReasonCode]
    public let includedElementCount: Int
    public let scrollAttempts: Int
    public let maxScrollsPerDiscovery: Int
    public let maxScrollsPerContainer: Int
    public let exploredScrollableContainerCount: Int
    public let omittedScrollableContainerCount: Int
    public let omittedContainers: [InterfaceDiscoveryOmittedContainer]
    public let nextAction: String?

    public init(
        state: InterfaceDiscoveryStatus,
        reasonCodes: [InterfaceDiscoveryReasonCode] = [],
        includedElementCount: Int,
        scrollAttempts: Int,
        maxScrollsPerDiscovery: Int,
        maxScrollsPerContainer: Int,
        exploredScrollableContainerCount: Int,
        omittedScrollableContainerCount: Int,
        omittedContainers: [InterfaceDiscoveryOmittedContainer] = [],
        nextAction: String? = nil
    ) {
        self.state = state
        self.reasonCodes = reasonCodes
        self.includedElementCount = includedElementCount
        self.scrollAttempts = scrollAttempts
        self.maxScrollsPerDiscovery = maxScrollsPerDiscovery
        self.maxScrollsPerContainer = maxScrollsPerContainer
        self.exploredScrollableContainerCount = exploredScrollableContainerCount
        self.omittedScrollableContainerCount = omittedScrollableContainerCount
        self.omittedContainers = omittedContainers
        self.nextAction = nextAction
    }
}

public struct InterfaceDiscoveryOmittedContainer: Codable, Equatable, Hashable, Sendable {
    public let containerName: ContainerName?
    public let type: String
    public let reasonCodes: [InterfaceDiscoveryReasonCode]
    public let scrollAxis: ScrollContainerAxis?
    public let viewportWidth: Double?
    public let viewportHeight: Double?
    public let contentWidth: Double?
    public let contentHeight: Double?

    public init(
        containerName: ContainerName? = nil,
        type: String,
        reasonCodes: [InterfaceDiscoveryReasonCode],
        scrollAxis: ScrollContainerAxis? = nil,
        viewportWidth: Double? = nil,
        viewportHeight: Double? = nil,
        contentWidth: Double? = nil,
        contentHeight: Double? = nil
    ) {
        self.containerName = containerName
        self.type = type
        self.reasonCodes = reasonCodes
        self.scrollAxis = scrollAxis
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
    }

}

extension InterfaceDiscoveryOmittedContainer: Comparable {
    public static func < (
        left: InterfaceDiscoveryOmittedContainer,
        right: InterfaceDiscoveryOmittedContainer
    ) -> Bool {
        let leftName = left.containerName?.rawValue ?? ""
        let rightName = right.containerName?.rawValue ?? ""
        if leftName != rightName { return leftName < rightName }
        if left.type != right.type { return left.type < right.type }

        let leftViewportWidth = left.viewportWidth ?? 0
        let rightViewportWidth = right.viewportWidth ?? 0
        if leftViewportWidth != rightViewportWidth {
            return leftViewportWidth < rightViewportWidth
        }

        return (left.viewportHeight ?? 0) < (right.viewportHeight ?? 0)
    }
}

/// A snapshot of the current accessibility interface returned by the server.
///
/// The wire shape carries the parser's full-fidelity `AccessibilityHierarchy`
/// plus Button Heist annotations. There is no parallel lossy tree on the wire;
/// flat elements are an explicit projection for matching and formatting.
public struct Interface: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let tree: [AccessibilityHierarchy]
    public let annotations: InterfaceAnnotations
    public let diagnostics: InterfaceDiagnostics?

    /// Button Heist element projection in VoiceOver traversal order.
    public var projectedElements: [HeistElement] {
        let annotationsByPath = annotations.elementByPath
        return tree.pathIndexedElements.map { item in
            HeistElement(
                accessibilityElement: item.element,
                annotation: annotationsByPath[item.path]
            )
        }
    }

    public init(
        timestamp: Date,
        tree: [AccessibilityHierarchy],
        annotations: InterfaceAnnotations = .empty,
        diagnostics: InterfaceDiagnostics? = nil
    ) {
        self.timestamp = timestamp
        self.tree = tree
        self.annotations = annotations
        self.diagnostics = diagnostics
    }

    public func withDiagnostics(_ diagnostics: InterfaceDiagnostics?) -> Interface {
        Interface(
            timestamp: timestamp,
            tree: tree,
            annotations: annotations,
            diagnostics: diagnostics
        )
    }

    public func annotations(
        forSubtree node: AccessibilityHierarchy,
        originalPath: TreePath,
        rootPath: TreePath
    ) -> InterfaceAnnotations {
        let elementsByPath = annotations.elementByPath
        let elements = node.compactMapSubtrees(path: rootPath) { node, newPath -> InterfaceElementAnnotation? in
            guard case .element = node else { return nil }
            let relativePath = Array(newPath.indices.dropFirst(rootPath.indices.count))
            let oldPath = TreePath(originalPath.indices + relativePath)
            guard let annotation = elementsByPath[oldPath] else { return nil }
            return InterfaceElementAnnotation(
                path: newPath,
                actions: annotation.actions
            )
        }
        let containersByPath = annotations.containerByPath
        let containers = node.compactMapSubtrees(path: rootPath) { node, newPath -> InterfaceContainerAnnotation? in
            guard case .container = node else { return nil }
            let relativePath = Array(newPath.indices.dropFirst(rootPath.indices.count))
            let oldPath = TreePath(originalPath.indices + relativePath)
            guard let annotation = containersByPath[oldPath] else { return nil }
            return InterfaceContainerAnnotation(
                path: newPath,
                containerName: annotation.containerName,
                scrollInventory: annotation.scrollInventory
            )
        }
        return InterfaceAnnotations(elements: elements, containers: containers)
    }

}
