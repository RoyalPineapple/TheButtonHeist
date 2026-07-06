import ThePlans
import Foundation
import CoreGraphics
import AccessibilitySnapshotModel

// MARK: - Typed Geometry Evidence

public struct ScreenRect: Codable, Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.size.width),
            height: Double(rect.size.height)
        )
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public var midX: Double {
        x + width / 2
    }

    public var midY: Double {
        y + height / 2
    }
}

public struct ContentRect: Codable, Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.size.width),
            height: Double(rect.size.height)
        )
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public var origin: CGPoint {
        CGPoint(x: x, y: y)
    }

    public var size: CGSize {
        CGSize(width: width, height: height)
    }
}

public struct ScrollContentPoint: Codable, Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.init(x: Double(point.x), y: Double(point.y))
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

public struct ActivationPointEvidence: Codable, Equatable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        case explicit
        case defaultCenter
        case unavailable
    }

    public let source: Source
    public let point: ScreenPoint?

    public init(source: Source, point: ScreenPoint?) {
        precondition(
            (source == .unavailable) == (point == nil),
            "Activation point evidence requires a point exactly when the source is available"
        )
        self.source = source
        self.point = point
    }

    public static func explicit(_ point: ScreenPoint) -> ActivationPointEvidence {
        ActivationPointEvidence(source: .explicit, point: point)
    }

    public static func defaultCenter(_ point: ScreenPoint) -> ActivationPointEvidence {
        ActivationPointEvidence(source: .defaultCenter, point: point)
    }

    public static let unavailable = ActivationPointEvidence(source: .unavailable, point: nil)

    private enum CodingKeys: String, CodingKey {
        case source
        case point
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let source = try container.decode(Source.self, forKey: .source)
        let point = try container.decodeIfPresent(ScreenPoint.self, forKey: .point)
        guard (source == .unavailable) == (point == nil) else {
            throw DecodingError.dataCorruptedError(
                forKey: .point,
                in: container,
                debugDescription: "Activation point evidence requires a point exactly when the source is available"
            )
        }
        self.source = source
        self.point = point
    }
}

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

public extension TreePath {
    func hasPrefix(_ prefix: TreePath) -> Bool {
        guard prefix.indices.count <= indices.count else { return false }
        return zip(prefix.indices, indices).allSatisfy { $0 == $1 }
    }
}

package extension TreePath {
    var parent: TreePath? {
        guard !indices.isEmpty else { return nil }
        return TreePath(Array(indices.dropLast()))
    }

    func removingPrefix(_ prefix: TreePath) -> TreePath? {
        guard hasPrefix(prefix) else { return nil }
        return TreePath(Array(indices.dropFirst(prefix.indices.count)))
    }

    func relative(to prefix: TreePath) -> TreePath? {
        removingPrefix(prefix)
    }

    func appending(contentsOf path: TreePath) -> TreePath {
        TreePath(indices + path.indices)
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
        self.actions = actions.canonicalElementActionArray
    }
}

extension InterfaceElementAnnotation {
    private enum CodingKeys: String, CodingKey {
        case path
        case actions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            path: try container.decode(TreePath.self, forKey: .path),
            actions: try container.decode(ElementActionSet.self, forKey: .actions).orderedActions
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(ElementActionSet(actions), forKey: .actions)
    }
}

/// Opaque element identity used only by trace-backed diffing.
///
/// Public element projections stay content-shaped. When a capture has stronger
/// semantic identity metadata, diffing can pair by this value and keep
/// label/identifier churn from masquerading as remove/add churn.
package struct TraceElementIdentity: Codable, Equatable, Hashable, Sendable, Comparable, CustomStringConvertible {
    package let rawValue: String

    package init(_ rawValue: String) {
        precondition(!rawValue.isEmpty, "TraceElementIdentity cannot be empty")
        self.rawValue = rawValue
    }

    package init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        guard !rawValue.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "TraceElementIdentity cannot be empty"
            ))
        }
        self.rawValue = rawValue
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    package var description: String {
        rawValue
    }

    package static func < (lhs: TraceElementIdentity, rhs: TraceElementIdentity) -> Bool {
        lhs.rawValue < rhs.rawValue
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

package struct InterfaceTraceIdentities: Equatable, Sendable {
    package static let empty = InterfaceTraceIdentities()

    package let byPath: [TreePath: TraceElementIdentity]

    package init(_ byPath: [TreePath: TraceElementIdentity] = [:]) {
        self.byPath = byPath
    }

    package subscript(path: TreePath) -> TraceElementIdentity? {
        byPath[path]
    }
}

package struct InterfaceElementRecord: Equatable, Sendable {
    package let path: TreePath
    package let traversalIndex: Int
    package let element: HeistElement
    package let traceIdentity: TraceElementIdentity?

    package init(
        path: TreePath,
        traversalIndex: Int,
        element: HeistElement,
        traceIdentity: TraceElementIdentity? = nil
    ) {
        self.path = path
        self.traversalIndex = traversalIndex
        self.element = element
        self.traceIdentity = traceIdentity
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
    public let type: ContainerTypeName
    public let reasonCodes: [InterfaceDiscoveryReasonCode]
    public let scrollAxis: ScrollContainerAxis?
    public let viewportWidth: Double?
    public let viewportHeight: Double?
    public let contentWidth: Double?
    public let contentHeight: Double?

    public init(
        containerName: ContainerName? = nil,
        type: ContainerTypeName,
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
        if left.type != right.type { return left.type.rawValue < right.type.rawValue }

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
    package let traceIdentities: InterfaceTraceIdentities

    /// Button Heist element projection in VoiceOver traversal order.
    public var projectedElements: [HeistElement] {
        projectedElementRecords.map(\.element)
    }

    package var graph: InterfaceGraph {
        do {
            return try InterfaceGraph(interface: self)
        } catch {
            preconditionFailure("Invalid Interface graph: \(error)")
        }
    }

    /// Trace-aware element projection in VoiceOver traversal order.
    ///
    /// `projectedElements` intentionally stays a public, content-only view.
    /// Diffing uses records so optional trace identity can participate in
    /// pairing without leaking into `HeistElement`.
    package var projectedElementRecords: [InterfaceElementRecord] {
        graph.elementsInTraversalOrder.map(\.interfaceRecord)
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
        self.traceIdentities = .empty
    }

    package init(
        timestamp: Date,
        tree: [AccessibilityHierarchy],
        annotations: InterfaceAnnotations = .empty,
        diagnostics: InterfaceDiagnostics? = nil,
        traceIdentities: InterfaceTraceIdentities
    ) {
        self.timestamp = timestamp
        self.tree = tree
        self.annotations = annotations
        self.diagnostics = diagnostics
        self.traceIdentities = traceIdentities
    }

    public static func == (lhs: Interface, rhs: Interface) -> Bool {
        lhs.timestamp == rhs.timestamp &&
            lhs.tree == rhs.tree &&
            lhs.annotations == rhs.annotations &&
            lhs.diagnostics == rhs.diagnostics
    }

    public func withDiagnostics(_ diagnostics: InterfaceDiagnostics?) -> Interface {
        Interface(
            timestamp: timestamp,
            tree: tree,
            annotations: annotations,
            diagnostics: diagnostics,
            traceIdentities: traceIdentities
        )
    }

    public func annotations(
        forSubtree node: AccessibilityHierarchy,
        originalPath: TreePath,
        rootPath: TreePath
    ) -> InterfaceAnnotations {
        graph.annotationsForSubtree(originalPath: originalPath, rootPath: rootPath)
    }

    package func traceIdentities(
        forSubtree node: AccessibilityHierarchy,
        originalPath: TreePath,
        rootPath: TreePath
    ) -> InterfaceTraceIdentities {
        graph.traceIdentitiesForSubtree(originalPath: originalPath, rootPath: rootPath)
    }

}
