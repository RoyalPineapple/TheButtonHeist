import ThePlans
import Foundation
import CoreGraphics
import AccessibilitySnapshotModel

// MARK: - Typed Geometry Evidence

public struct FiniteDimension: Codable, Equatable, Hashable, Sendable,
    ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, Comparable, CustomStringConvertible {
    public enum ValidationError: Error, Sendable, Equatable, CustomStringConvertible {
        case invalid

        public var description: String { "dimension must be finite and non-negative" }
    }

    public let value: Double

    public init(validating value: Double) throws(ValidationError) {
        guard value.isFinite, value >= 0 else { throw .invalid }
        self.value = value
    }

    public init(integerLiteral value: Int) {
        self = requireValidLiteralPayload { try Self(validating: Double(value)) }
    }

    public init(floatLiteral value: Double) {
        self = requireValidLiteralPayload { try Self(validating: value) }
    }

    public init(from decoder: Decoder) throws {
        self = try decodeSingleValue(from: decoder, admitting: Self.init(validating:))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeSingleValue(value, to: encoder)
    }

    public var description: String { String(value) }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }
}

public struct ScreenRect: Codable, Equatable, Hashable, Sendable {
    public let x: FiniteCoordinate
    public let y: FiniteCoordinate
    public let width: FiniteDimension
    public let height: FiniteDimension

    public init(
        x: FiniteCoordinate,
        y: FiniteCoordinate,
        width: FiniteDimension,
        height: FiniteDimension
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(validating rect: CGRect) throws {
        self.init(
            x: try FiniteCoordinate(validating: Double(rect.origin.x)),
            y: try FiniteCoordinate(validating: Double(rect.origin.y)),
            width: try FiniteDimension(validating: Double(rect.size.width)),
            height: try FiniteDimension(validating: Double(rect.size.height))
        )
    }

    public init(validating rect: AccessibilityRect) throws {
        self.init(
            x: try FiniteCoordinate(validating: rect.origin.x),
            y: try FiniteCoordinate(validating: rect.origin.y),
            width: try FiniteDimension(validating: rect.size.width),
            height: try FiniteDimension(validating: rect.size.height)
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case x, y, width, height
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "screen rect")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decode(FiniteCoordinate.self, forKey: .x),
            y: try container.decode(FiniteCoordinate.self, forKey: .y),
            width: try container.decode(FiniteDimension.self, forKey: .width),
            height: try container.decode(FiniteDimension.self, forKey: .height)
        )
    }

    public var cgRect: CGRect {
        CGRect(x: x.value, y: y.value, width: width.value, height: height.value)
    }

    public var midX: Double {
        x.value + width.value / 2
    }

    public var midY: Double {
        y.value + height.value / 2
    }
}

public struct ContentRect: Codable, Equatable, Hashable, Sendable {
    public let x: FiniteCoordinate
    public let y: FiniteCoordinate
    public let width: FiniteDimension
    public let height: FiniteDimension

    public init(
        x: FiniteCoordinate,
        y: FiniteCoordinate,
        width: FiniteDimension,
        height: FiniteDimension
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(validating rect: CGRect) throws {
        self.init(
            x: try FiniteCoordinate(validating: Double(rect.origin.x)),
            y: try FiniteCoordinate(validating: Double(rect.origin.y)),
            width: try FiniteDimension(validating: Double(rect.size.width)),
            height: try FiniteDimension(validating: Double(rect.size.height))
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case x, y, width, height
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "content rect")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decode(FiniteCoordinate.self, forKey: .x),
            y: try container.decode(FiniteCoordinate.self, forKey: .y),
            width: try container.decode(FiniteDimension.self, forKey: .width),
            height: try container.decode(FiniteDimension.self, forKey: .height)
        )
    }

    public var cgRect: CGRect {
        CGRect(x: x.value, y: y.value, width: width.value, height: height.value)
    }

    public var origin: CGPoint {
        CGPoint(x: x.value, y: y.value)
    }

    public var size: CGSize {
        CGSize(width: width.value, height: height.value)
    }
}

public struct ScrollContentPoint: Codable, Equatable, Hashable, Sendable {
    public let x: FiniteCoordinate
    public let y: FiniteCoordinate

    public init(x: FiniteCoordinate, y: FiniteCoordinate) {
        self.x = x
        self.y = y
    }

    public init(validating point: CGPoint) throws {
        self.init(
            x: try FiniteCoordinate(validating: Double(point.x)),
            y: try FiniteCoordinate(validating: Double(point.y))
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case x, y
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "scroll content point")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decode(FiniteCoordinate.self, forKey: .x),
            y: try container.decode(FiniteCoordinate.self, forKey: .y)
        )
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x.value, y: y.value)
    }
}

public enum ScreenFrameEvidence: Equatable, Hashable, Sendable {
    case available(ScreenRect)
    case unavailable

    public var rect: ScreenRect? {
        guard case .available(let rect) = self else { return nil }
        return rect
    }

    public init(_ rect: CGRect) {
        guard let rect = try? ScreenRect(validating: rect) else {
            self = .unavailable
            return
        }
        self = .available(rect)
    }

    public init(_ rect: AccessibilityRect) {
        guard let rect = try? ScreenRect(validating: rect) else {
            self = .unavailable
            return
        }
        self = .available(rect)
    }

    public init(_ shape: AccessibilityShape) {
        switch shape {
        case .frame(let rect):
            self.init(rect)
        case .path(let elements):
            guard !elements.isEmpty else {
                self = .unavailable
                return
            }
            let path = CGMutablePath()
            for element in elements {
                switch element {
                case .move(let point):
                    path.move(to: CGPoint(x: point.x, y: point.y))
                case .line(let point):
                    path.addLine(to: CGPoint(x: point.x, y: point.y))
                case .quadCurve(let point, let control):
                    path.addQuadCurve(
                        to: CGPoint(x: point.x, y: point.y),
                        control: CGPoint(x: control.x, y: control.y)
                    )
                case .curve(let point, let control1, let control2):
                    path.addCurve(
                        to: CGPoint(x: point.x, y: point.y),
                        control1: CGPoint(x: control1.x, y: control1.y),
                        control2: CGPoint(x: control2.x, y: control2.y)
                    )
                case .closeSubpath:
                    path.closeSubpath()
                }
            }
            self.init(path.boundingBoxOfPath)
        }
    }

}

package struct InterfaceGeometryAdmissionError: Error, Equatable, CustomStringConvertible {
    package let path: TreePath
    package let field: String

    package var description: String {
        "Invalid interface geometry at \(path.indices): \(field)"
    }
}

package enum InterfaceGeometryAdmission {
    package static func validate(_ tree: [AccessibilityHierarchy]) throws {
        for (index, node) in tree.enumerated() {
            try validate(node, at: TreePath([index]))
        }
    }

    package static func validate(_ element: AccessibilityElement, at path: TreePath) throws {
        try validate(element.shape, at: path, field: "element shape")
        guard element.activationPoint.isFinite else {
            throw InterfaceGeometryAdmissionError(path: path, field: "element activation point")
        }
        for (rotorIndex, rotor) in element.customRotors.enumerated() {
            for (resultIndex, marker) in rotor.resultMarkers.enumerated() {
                guard let shape = marker.shape else { continue }
                try validate(
                    shape,
                    at: path,
                    field: "custom rotor \(rotorIndex) result \(resultIndex) shape"
                )
            }
        }
    }

    package static func validate(_ container: AccessibilityContainer, at path: TreePath) throws {
        try validate(container.frame, at: path, field: "container frame")
        if let size = container.scrollableContentSize {
            try validate(size, at: path, field: "container scrollable content size")
        }
        if case .scrollable(let size) = container.type {
            try validate(size, at: path, field: "scrollable container type content size")
        }
    }

    private static func validate(_ node: AccessibilityHierarchy, at path: TreePath) throws {
        switch node {
        case .element(let element, _):
            try validate(element, at: path)
        case .container(let container, let children):
            try validate(container, at: path)
            for (index, child) in children.enumerated() {
                try validate(child, at: path.appending(index))
            }
        }
    }

    private static func validate(
        _ shape: AccessibilityShape,
        at path: TreePath,
        field: String
    ) throws {
        switch shape {
        case .frame(let rect):
            try validate(rect, at: path, field: field)
        case .path(let elements):
            guard elements.allSatisfy(\.pointsAreFinite) else {
                throw InterfaceGeometryAdmissionError(path: path, field: field)
            }
        }
    }

    private static func validate(
        _ rect: AccessibilityRect,
        at path: TreePath,
        field: String
    ) throws {
        guard ScreenFrameEvidence(rect).rect != nil else {
            throw InterfaceGeometryAdmissionError(path: path, field: field)
        }
    }

    private static func validate(
        _ size: AccessibilitySize,
        at path: TreePath,
        field: String
    ) throws {
        guard (try? FiniteDimension(validating: size.width)) != nil,
              (try? FiniteDimension(validating: size.height)) != nil else {
            throw InterfaceGeometryAdmissionError(path: path, field: field)
        }
    }
}

private extension AccessibilityPathElement {
    var pointsAreFinite: Bool {
        switch self {
        case .move(let point), .line(let point):
            point.isFinite
        case .quadCurve(let point, let control):
            point.isFinite && control.isFinite
        case .curve(let point, let control1, let control2):
            point.isFinite && control1.isFinite && control2.isFinite
        case .closeSubpath:
            true
        }
    }
}

public enum ActivationPointEvidence: Codable, Equatable, Hashable, Sendable {
    case explicit(ScreenPoint)
    case defaultCenter(ScreenPoint)
    case unavailable

    public var point: ScreenPoint? {
        switch self {
        case .explicit(let point), .defaultCenter(let point):
            point
        case .unavailable:
            nil
        }
    }

    private enum Source: String, Codable {
        case explicit
        case defaultCenter
        case unavailable
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case source
        case point
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActivationPointEvidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Source.self, forKey: .source) {
        case .explicit:
            self = .explicit(try container.decode(ScreenPoint.self, forKey: .point))
        case .defaultCenter:
            self = .defaultCenter(try container.decode(ScreenPoint.self, forKey: .point))
        case .unavailable:
            guard !container.contains(.point) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .point,
                    in: container,
                    debugDescription: "Unavailable activation point evidence must not include a point"
                )
            }
            self = .unavailable
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .explicit(let point):
            try container.encode(Source.explicit, forKey: .source)
            try container.encode(point, forKey: .point)
        case .defaultCenter(let point):
            try container.encode(Source.defaultCenter, forKey: .source)
            try container.encode(point, forKey: .point)
        case .unavailable:
            try container.encode(Source.unavailable, forKey: .source)
        }
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

    package init(_ indices: [Int]) {
        precondition(indices.allSatisfy { $0 >= 0 }, "TreePath indices must be non-negative")
        self.indices = indices
    }

    public init?(validating indices: [Int]) {
        guard indices.allSatisfy({ $0 >= 0 }) else { return nil }
        self.indices = indices
    }

    public static let root = TreePath([])

    package func appending(_ index: Int) -> TreePath {
        TreePath(indices + [index])
    }

    public func appending(validating index: Int) -> TreePath? {
        TreePath(validating: indices + [index])
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case indices
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "tree path")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let admitted = Self(validating: try container.decode([Int].self, forKey: .indices)) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "tree path indices must be non-negative"
            ))
        }
        self = admitted
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

    public init?(totalElementCount: Int?, visibleIndices: [Int]) {
        guard totalElementCount.map({ $0 >= 0 }) ?? true,
              visibleIndices.allSatisfy({ $0 >= 0 }),
              Set(visibleIndices).count == visibleIndices.count,
              totalElementCount.map({ total in visibleIndices.allSatisfy { $0 < total } }) ?? true
        else { return nil }
        self.totalElementCount = totalElementCount
        self.visibleIndices = visibleIndices
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case totalElementCount
        case visibleIndices
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "scroll inventory")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let totalElementCount = try container.decodeIfPresent(Int.self, forKey: .totalElementCount)
        let visibleIndices = try container.decode([Int].self, forKey: .visibleIndices)
        guard let admitted = Self(totalElementCount: totalElementCount, visibleIndices: visibleIndices) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "scroll inventory indices must be unique and inside the total element count"
            ))
        }
        self = admitted
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(totalElementCount, forKey: .totalElementCount)
        try container.encode(visibleIndices, forKey: .visibleIndices)
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
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case path
        case actions
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "interface element annotation")
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

    public init?(
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
        let counts = [
            includedElementCount,
            scrollAttempts,
            maxScrollsPerDiscovery,
            maxScrollsPerContainer,
            exploredScrollableContainerCount,
            omittedScrollableContainerCount,
        ]
        let stateIsConsistent = switch state {
        case .complete:
            reasonCodes.isEmpty && omittedContainers.isEmpty && nextAction == nil
        case .limited:
            !reasonCodes.isEmpty || !omittedContainers.isEmpty
        }
        guard counts.allSatisfy({ $0 >= 0 }),
              omittedScrollableContainerCount == omittedContainers.count,
              stateIsConsistent
        else { return nil }
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

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case state, reasonCodes, includedElementCount, scrollAttempts
        case maxScrollsPerDiscovery, maxScrollsPerContainer
        case exploredScrollableContainerCount, omittedScrollableContainerCount
        case omittedContainers, nextAction
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "interface discovery diagnostics")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let admitted = Self(
            state: try container.decode(InterfaceDiscoveryStatus.self, forKey: .state),
            reasonCodes: try container.decode([InterfaceDiscoveryReasonCode].self, forKey: .reasonCodes),
            includedElementCount: try container.decode(Int.self, forKey: .includedElementCount),
            scrollAttempts: try container.decode(Int.self, forKey: .scrollAttempts),
            maxScrollsPerDiscovery: try container.decode(Int.self, forKey: .maxScrollsPerDiscovery),
            maxScrollsPerContainer: try container.decode(Int.self, forKey: .maxScrollsPerContainer),
            exploredScrollableContainerCount: try container.decode(Int.self, forKey: .exploredScrollableContainerCount),
            omittedScrollableContainerCount: try container.decode(Int.self, forKey: .omittedScrollableContainerCount),
            omittedContainers: try container.decode([InterfaceDiscoveryOmittedContainer].self, forKey: .omittedContainers),
            nextAction: try container.decodeIfPresent(String.self, forKey: .nextAction)
        ) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "interface discovery counts and state must be consistent"
            ))
        }
        self = admitted
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(reasonCodes, forKey: .reasonCodes)
        try container.encode(includedElementCount, forKey: .includedElementCount)
        try container.encode(scrollAttempts, forKey: .scrollAttempts)
        try container.encode(maxScrollsPerDiscovery, forKey: .maxScrollsPerDiscovery)
        try container.encode(maxScrollsPerContainer, forKey: .maxScrollsPerContainer)
        try container.encode(exploredScrollableContainerCount, forKey: .exploredScrollableContainerCount)
        try container.encode(omittedScrollableContainerCount, forKey: .omittedScrollableContainerCount)
        try container.encode(omittedContainers, forKey: .omittedContainers)
        try container.encodeIfPresent(nextAction, forKey: .nextAction)
    }
}

public struct InterfaceDiscoveryOmittedContainer: Codable, Equatable, Hashable, Sendable {
    public let containerName: ContainerName?
    public let type: AccessibilityContainerKind
    public let reasonCodes: [InterfaceDiscoveryReasonCode]
    public let scrollAxis: ScrollContainerAxis?
    public let viewportWidth: FiniteDimension?
    public let viewportHeight: FiniteDimension?
    public let contentWidth: FiniteDimension?
    public let contentHeight: FiniteDimension?

    public init(
        containerName: ContainerName? = nil,
        type: AccessibilityContainerKind,
        reasonCodes: [InterfaceDiscoveryReasonCode],
        scrollAxis: ScrollContainerAxis? = nil,
        viewportWidth: FiniteDimension? = nil,
        viewportHeight: FiniteDimension? = nil,
        contentWidth: FiniteDimension? = nil,
        contentHeight: FiniteDimension? = nil
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

public enum ScreenAction: String, Codable, Equatable, Hashable, Sendable, CaseIterable, Comparable {
    case dismiss
    case magicTap

    public static func < (lhs: ScreenAction, rhs: ScreenAction) -> Bool {
        lhs.rawValue < rhs.rawValue
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
    public let screenActions: [ScreenAction]
    package let traceIdentities: InterfaceTraceIdentities

    /// Button Heist element projection in VoiceOver traversal order.
    public var projectedElements: [HeistElement] {
        projectedElementRecords.map(\.element)
    }

    /// Trace-aware element projection in VoiceOver traversal order.
    ///
    /// `projectedElements` intentionally stays a public, content-only view.
    /// Diffing uses records so optional trace identity can participate in
    /// pairing without leaking into `HeistElement`.
    package var projectedElementRecords: [InterfaceElementRecord] {
        graph.elementsInTraversalOrder.map(\.interfaceRecord)
    }

    package init(
        timestamp: Date,
        tree: [AccessibilityHierarchy],
        diagnostics: InterfaceDiagnostics? = nil
    ) {
        guard let admitted = Self(
            admitting: timestamp,
            tree: tree,
            diagnostics: diagnostics
        ) else {
            preconditionFailure("Interface hierarchy geometry must be admitted before construction")
        }
        self = admitted
    }

    public init?(
        admitting timestamp: Date,
        tree: [AccessibilityHierarchy],
        diagnostics: InterfaceDiagnostics? = nil
    ) {
        guard (try? InterfaceGeometryAdmission.validate(tree)) != nil else { return nil }
        self.init(
            validatedTimestamp: timestamp,
            tree: tree,
            annotations: .empty,
            diagnostics: diagnostics,
            screenActions: [],
            traceIdentities: .empty
        )
    }

    public init(
        timestamp: Date,
        tree: [AccessibilityHierarchy],
        annotations: InterfaceAnnotations,
        diagnostics: InterfaceDiagnostics? = nil
    ) throws {
        try self.init(
            timestamp: timestamp,
            tree: tree,
            annotations: annotations,
            diagnostics: diagnostics,
            screenActions: [],
            traceIdentities: .empty
        )
    }

    package init(
        timestamp: Date,
        tree: [AccessibilityHierarchy],
        diagnostics: InterfaceDiagnostics? = nil,
        traceIdentities: InterfaceTraceIdentities
    ) throws {
        try self.init(
            timestamp: timestamp,
            tree: tree,
            annotations: .empty,
            diagnostics: diagnostics,
            traceIdentities: traceIdentities
        )
    }

    package init(
        timestamp: Date,
        tree: [AccessibilityHierarchy],
        annotations: InterfaceAnnotations,
        diagnostics: InterfaceDiagnostics? = nil,
        screenActions: [ScreenAction] = [],
        traceIdentities: InterfaceTraceIdentities
    ) throws {
        try InterfaceGeometryAdmission.validate(tree)
        try InterfaceGraph.validate(
            tree: tree,
            annotations: annotations,
            traceIdentities: traceIdentities
        )

        self.init(
            validatedTimestamp: timestamp,
            tree: tree,
            annotations: annotations,
            diagnostics: diagnostics,
            screenActions: screenActions,
            traceIdentities: traceIdentities
        )
    }

    package init(
        timestamp: Date,
        projecting tree: [AccessibilityHierarchy],
        diagnostics: InterfaceDiagnostics? = nil,
        screenActions: [ScreenAction] = [],
        elementMetadata: (TreePath, AccessibilityElement, Int) -> InterfaceElementProjectionMetadata?,
        containerMetadata: (TreePath, AccessibilityContainer) -> InterfaceContainerProjectionMetadata?
    ) {
        let projection = InterfaceGraph.projection(
            tree: tree,
            elementMetadata: elementMetadata,
            containerMetadata: containerMetadata
        )

        do {
            try InterfaceGeometryAdmission.validate(tree)
        } catch {
            preconditionFailure("Interface hierarchy geometry must be admitted before projection: \(error)")
        }

        self.init(
            validatedTimestamp: timestamp,
            tree: tree,
            annotations: projection.annotations,
            diagnostics: diagnostics,
            screenActions: screenActions,
            traceIdentities: projection.traceIdentities
        )
    }

    private init(
        validatedTimestamp timestamp: Date,
        tree: [AccessibilityHierarchy],
        annotations: InterfaceAnnotations,
        diagnostics: InterfaceDiagnostics?,
        screenActions: [ScreenAction],
        traceIdentities: InterfaceTraceIdentities
    ) {
        self.timestamp = timestamp
        self.tree = tree
        self.annotations = annotations
        self.diagnostics = diagnostics
        self.screenActions = screenActions.sorted()
        self.traceIdentities = traceIdentities
    }

    public static func == (lhs: Interface, rhs: Interface) -> Bool {
        lhs.timestamp == rhs.timestamp &&
            lhs.tree == rhs.tree &&
            lhs.annotations == rhs.annotations &&
            lhs.diagnostics == rhs.diagnostics &&
            lhs.screenActions == rhs.screenActions
    }

    public func withDiagnostics(_ diagnostics: InterfaceDiagnostics?) -> Interface {
        Interface(
            validatedTimestamp: timestamp,
            tree: tree,
            annotations: annotations,
            diagnostics: diagnostics,
            screenActions: screenActions,
            traceIdentities: traceIdentities
        )
    }

    public func withScreenActions(_ screenActions: [ScreenAction]) -> Interface {
        Interface(
            validatedTimestamp: timestamp,
            tree: tree,
            annotations: annotations,
            diagnostics: diagnostics,
            screenActions: screenActions,
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

    package func selectingSubtree(at originalPath: TreePath) -> Interface {
        guard let node = graph.node(at: originalPath) else {
            preconditionFailure("Cannot project missing interface subtree")
        }
        let rootPath = TreePath([0])
        return Interface(
            validatedTimestamp: timestamp,
            tree: [node],
            annotations: graph.annotationsForSubtree(originalPath: originalPath, rootPath: rootPath),
            diagnostics: diagnostics,
            screenActions: [],
            traceIdentities: graph.traceIdentitiesForSubtree(originalPath: originalPath, rootPath: rootPath)
        )
    }

}
