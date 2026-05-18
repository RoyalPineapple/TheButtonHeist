import CryptoKit
import Foundation
import AccessibilitySnapshotModel

// MARK: - Accessibility Trace

/// Accessibility state observed during a session.
///
/// Screen changes create full baseline captures. Same-screen changes are stored
/// as replayable patches on top of that baseline. `captures` remains the
/// materialized projection for callers that want the full state at every point.
public struct AccessibilityTrace: Codable, Sendable, Equatable {
    public let segments: [ScreenSegment]

    public var captures: [Capture] {
        segments.flatMap(\.captures)
    }

    private enum CodingKeys: String, CodingKey {
        case segments
    }

    public init(captures: [Capture]) {
        var segments: [ScreenSegment] = []
        var currentSegment: ScreenSegment?
        var previousCapture: Capture?

        for (index, capture) in captures.enumerated() {
            let linked = Capture(
                sequence: index + 1,
                interface: capture.interface,
                parentHash: previousCapture?.hash,
                context: capture.context,
                transition: capture.transition,
                hash: capture.hash
            )

            guard let before = previousCapture, var segment = currentSegment else {
                currentSegment = ScreenSegment(baseline: linked)
                previousCapture = linked
                continue
            }

            if linked.transition.startsScreenSegment {
                segments.append(segment)
                currentSegment = ScreenSegment(baseline: linked)
            } else if let observed = ObservedTransition.between(before, linked) {
                segment.append(observed)
                currentSegment = segment
            } else {
                segments.append(segment)
                currentSegment = ScreenSegment(baseline: linked)
            }
            previousCapture = linked
        }

        if let currentSegment {
            segments.append(currentSegment)
        }
        self.init(segments: segments)
    }

    public init(segments: [ScreenSegment]) {
        self.segments = segments
    }

    public init(capture: Capture) {
        self.init(captures: [capture])
    }

    public init(first interface: Interface) {
        self.init(capture: Capture(sequence: 1, interface: interface))
    }

    public init(interface: Interface) {
        self.init(first: interface)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(segments: try container.decode([ScreenSegment].self, forKey: .segments))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(segments, forKey: .segments)
    }

    public func appending(
        _ interface: Interface,
        context: Context = .empty,
        transition: Transition = .empty
    ) -> AccessibilityTrace {
        let capture = Capture(
            sequence: captures.count + 1,
            interface: interface,
            parentHash: captures.last?.hash,
            context: context,
            transition: transition
        )
        return AccessibilityTrace(captures: captures + [capture])
    }

    public func capture(hash: String) -> Capture? {
        captures.first { $0.hash == hash }
    }

    /// Lookup by a capture ref emitted from this normalized trace. Capture
    /// refs created before `AccessibilityTrace(captures:)` renumbers a chain
    /// may have stale sequences; use `capture(hash:)` for those.
    public func capture(ref: CaptureRef) -> Capture? {
        captures.first { $0.sequence == ref.sequence && $0.hash == ref.hash }
    }

    public var isLinearChain: Bool {
        for index in captures.indices {
            let expectedParent = index == captures.startIndex ? nil : captures[captures.index(before: index)].hash
            guard captures[index].parentHash == expectedParent else { return false }
        }
        return true
    }

    public var receipts: [Receipt] {
        captures.map(Receipt.init(capture:))
    }

    public var integrityIssues: [IntegrityIssue] {
        var issues: [IntegrityIssue] = []
        var expectedParentHash: String?

        for (segmentIndex, segment) in segments.enumerated() {
            let baseline = segment.baseline
            let computedBaselineHash = Capture.hash(interface: baseline.interface, context: baseline.context)
            if baseline.hash != computedBaselineHash {
                issues.append(.captureHashMismatch(
                    segment: segmentIndex,
                    sequence: baseline.sequence,
                    recordedHash: baseline.hash,
                    computedHash: computedBaselineHash
                ))
            }
            if baseline.parentHash != expectedParentHash {
                issues.append(.parentHashMismatch(
                    segment: segmentIndex,
                    sequence: baseline.sequence,
                    recordedParentHash: baseline.parentHash,
                    expectedParentHash: expectedParentHash
                ))
            }

            var previous = baseline
            for transition in segment.transitions {
                if transition.fromHash != previous.hash {
                    issues.append(.transitionFromHashMismatch(
                        segment: segmentIndex,
                        sequence: transition.sequence,
                        recordedFromHash: transition.fromHash,
                        expectedFromHash: previous.hash
                    ))
                }
                let materialized = transition.materialize(after: previous)
                if materialized.hash != transition.toHash {
                    issues.append(.transitionToHashMismatch(
                        segment: segmentIndex,
                        sequence: transition.sequence,
                        recordedToHash: transition.toHash,
                        computedToHash: materialized.hash
                    ))
                }
                previous = materialized
            }

            expectedParentHash = previous.hash
        }

        return issues
    }

    public var hasValidIntegrity: Bool {
        integrityIssues.isEmpty
    }

}

private enum AccessibilityTraceCaptureCodingKeys: String, CodingKey {
    case sequence
    case hash
    case parentHash
    case interface
    case context
    case transition
}

public extension AccessibilityTrace {
    struct ScreenSegment: Codable, Sendable, Equatable {
        public let baseline: Capture
        public private(set) var transitions: [ObservedTransition]

        public init(baseline: Capture, transitions: [ObservedTransition] = []) {
            self.baseline = baseline
            self.transitions = transitions
        }

        public var captures: [Capture] {
            transitions.reduce(into: [baseline]) { result, transition in
                guard let previous = result.last else { return }
                result.append(transition.materialize(after: previous))
            }
        }

        public var currentCapture: Capture {
            captures.last ?? baseline
        }

        public mutating func append(_ transition: ObservedTransition) {
            transitions.append(transition)
        }

    }

    enum IntegrityIssue: Sendable, Equatable {
        case captureHashMismatch(
            segment: Int,
            sequence: Int,
            recordedHash: String,
            computedHash: String
        )
        case parentHashMismatch(
            segment: Int,
            sequence: Int,
            recordedParentHash: String?,
            expectedParentHash: String?
        )
        case transitionFromHashMismatch(
            segment: Int,
            sequence: Int,
            recordedFromHash: String,
            expectedFromHash: String
        )
        case transitionToHashMismatch(
            segment: Int,
            sequence: Int,
            recordedToHash: String,
            computedToHash: String
        )
    }

    struct ObservedTransition: Codable, Sendable, Equatable {
        public let sequence: Int
        public let fromHash: String
        public let toHash: String
        public let cause: TransitionCause
        public let patch: AccessibilityPatch

        public init(
            sequence: Int,
            fromHash: String,
            toHash: String,
            cause: TransitionCause = .unknown,
            patch: AccessibilityPatch
        ) {
            self.sequence = sequence
            self.fromHash = fromHash
            self.toHash = toHash
            self.cause = cause
            self.patch = patch
        }

        public static func between(
            _ before: Capture,
            _ after: Capture,
            cause: TransitionCause = .unknown
        ) -> ObservedTransition? {
            guard let patch = AccessibilityPatch.between(before, after) else { return nil }
            return ObservedTransition(
                sequence: after.sequence,
                fromHash: before.hash,
                toHash: after.hash,
                cause: cause,
                patch: patch
            )
        }

        public func materialize(after capture: Capture, sequence: Int? = nil) -> Capture {
            patch.apply(to: capture, sequence: sequence ?? self.sequence)
        }
    }

    enum TransitionCause: Codable, Sendable, Equatable, Hashable {
        case command(String)
        case external
        case system
        case animation
        case timer
        case unknown
    }

    struct AccessibilityPatch: Codable, Sendable, Equatable {
        public let operations: [Operation]
        public let context: Context
        public let transition: Transition

        public init(
            operations: [Operation],
            context: Context,
            transition: Transition = .empty
        ) {
            self.operations = operations
            self.context = context
            self.transition = transition
        }

        public static func between(_ before: Capture, _ after: Capture) -> AccessibilityPatch? {
            between(
                before.interface,
                after.interface,
                context: after.context,
                transition: after.transition
            )
        }

        public static func between(
            _ before: Interface,
            _ after: Interface,
            context: Context,
            transition: Transition = .empty
        ) -> AccessibilityPatch? {
            guard before.tree.hasSameShape(as: after.tree) else { return nil }

            let beforeElements = before.tree.elementByTraversalIndex
            let afterElements = after.tree.elementByTraversalIndex
            let beforeElementAnnotations = before.annotations.elementByTraversalIndex
            let afterElementAnnotations = after.annotations.elementByTraversalIndex
            let beforeContainers = before.tree.containerByPath
            let afterContainers = after.tree.containerByPath
            let beforeContainerAnnotations = before.annotations.containerByPath
            let afterContainerAnnotations = after.annotations.containerByPath

            var operations: [Operation] = []
            for traversalIndex in afterElements.keys.sorted() {
                guard let afterElement = afterElements[traversalIndex] else { continue }
                if beforeElements[traversalIndex] != afterElement ||
                    beforeElementAnnotations[traversalIndex] != afterElementAnnotations[traversalIndex] {
                    operations.append(.updateElement(
                        traversalIndex: traversalIndex,
                        element: afterElement,
                        annotation: afterElementAnnotations[traversalIndex]
                    ))
                }
            }

            for path in afterContainers.keys.sorted() {
                guard let afterContainer = afterContainers[path] else { continue }
                if beforeContainers[path] != afterContainer ||
                    beforeContainerAnnotations[path] != afterContainerAnnotations[path] {
                    operations.append(.updateContainer(
                        path: path,
                        container: afterContainer,
                        annotation: afterContainerAnnotations[path]
                    ))
                }
            }

            return AccessibilityPatch(operations: operations, context: context, transition: transition)
        }

        public func apply(to capture: Capture, sequence: Int) -> Capture {
            let interface = apply(to: capture.interface)
            return Capture(
                sequence: sequence,
                interface: interface,
                parentHash: capture.hash,
                context: context,
                transition: transition
            )
        }

        public func apply(to interface: Interface) -> Interface {
            var tree = interface.tree
            var elementAnnotations = interface.annotations.elementByTraversalIndex
            var containerAnnotations = interface.annotations.containerByPath

            for operation in operations {
                switch operation {
                case .updateElement(let traversalIndex, let element, let annotation):
                    tree = tree.updatingElement(traversalIndex: traversalIndex, with: element)
                    if let annotation {
                        elementAnnotations[traversalIndex] = annotation
                    } else {
                        elementAnnotations.removeValue(forKey: traversalIndex)
                    }
                case .updateContainer(let path, let container, let annotation):
                    tree = tree.updatingContainer(path: path, with: container)
                    if let annotation {
                        containerAnnotations[path] = annotation
                    } else {
                        containerAnnotations.removeValue(forKey: path)
                    }
                }
            }

            return Interface(
                timestamp: interface.timestamp,
                tree: tree,
                annotations: InterfaceAnnotations(
                    elements: elementAnnotations.values.sorted { $0.traversalIndex < $1.traversalIndex },
                    containers: containerAnnotations
                        .sorted { $0.key < $1.key }
                        .map { InterfaceContainerAnnotation(path: $0.key, stableId: $0.value.stableId) }
                )
            )
        }

        public enum Operation: Codable, Sendable, Equatable {
            case updateElement(
                traversalIndex: Int,
                element: AccessibilityElement,
                annotation: InterfaceElementAnnotation?
            )
            case updateContainer(
                path: TreePath,
                container: AccessibilityContainer,
                annotation: InterfaceContainerAnnotation?
            )
        }
    }

    struct Capture: Codable, Sendable, Equatable {
        /// 1-based position in this trace's linear capture chain.
        public let sequence: Int
        public let hash: String
        /// Hash of the previous capture in the same linear trace, or nil for
        /// the first capture.
        public let parentHash: String?
        public let interface: Interface
        public let context: Context
        /// Metadata about the edge from `parentHash` to this capture. This is
        /// not included in `hash`: it describes the observed transition, not
        /// the captured hierarchy state.
        public let transition: Transition

        public init(
            sequence: Int,
            interface: Interface,
            parentHash: String? = nil,
            context: Context = .empty,
            transition: Transition = .empty,
            hash: String? = nil
        ) {
            self.sequence = sequence
            self.parentHash = parentHash
            self.interface = interface
            self.context = context
            self.transition = transition
            self.hash = hash ?? Self.hash(interface: interface, context: context)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AccessibilityTraceCaptureCodingKeys.self)
            sequence = try container.decode(Int.self, forKey: .sequence)
            hash = try container.decode(String.self, forKey: .hash)
            parentHash = try container.decodeIfPresent(String.self, forKey: .parentHash)
            interface = try container.decode(Interface.self, forKey: .interface)
            context = try container.decodeIfPresent(Context.self, forKey: .context) ?? .empty
            transition = try container.decodeIfPresent(Transition.self, forKey: .transition) ?? .empty
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: AccessibilityTraceCaptureCodingKeys.self)
            try container.encode(sequence, forKey: .sequence)
            try container.encode(hash, forKey: .hash)
            try container.encodeIfPresent(parentHash, forKey: .parentHash)
            try container.encode(interface, forKey: .interface)
            try container.encode(context, forKey: .context)
            if !transition.isEmpty {
                try container.encode(transition, forKey: .transition)
            }
        }

        public var summary: String {
            let fallback = "\(interface.elements.count) elements"
            let description = normalized(interface.screenDescription)
            return description == fallback ? fallback : "\(description ?? fallback) (\(interface.elements.count) elements)"
        }

        public static func hash(_ interface: Interface) -> String {
            hash(interface: interface, context: .empty)
        }

        public static func hash(interface: Interface, context: Context) -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let content = StableCaptureContent(
                tree: interface.tree,
                annotations: interface.annotations,
                context: context
            )
            let data = (try? encoder.encode(content)) ?? Data()
            return "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    struct Transition: Codable, Sendable, Equatable, Hashable {
        public static let empty = Transition()

        /// Reason a same-edge transition was classified as a screen change.
        /// Stored as a string so producers outside TheScore can evolve their
        /// classifier without making this wire receipt depend on that enum.
        public let screenChangeReason: String?
        /// Elements that appeared and disappeared while settling this edge.
        public let transient: [HeistElement]

        public init(
            screenChangeReason: String? = nil,
            transient: [HeistElement] = []
        ) {
            self.screenChangeReason = screenChangeReason
            self.transient = transient
        }

        public var isEmpty: Bool {
            screenChangeReason == nil && transient.isEmpty
        }

        fileprivate var startsScreenSegment: Bool {
            screenChangeReason != nil
        }
    }

    struct CaptureRef: Codable, Sendable, Equatable, Hashable {
        public let sequence: Int
        public let hash: String

        public init(sequence: Int, hash: String) {
            self.sequence = sequence
            self.hash = hash
        }

        public init(capture: Capture) {
            self.init(sequence: capture.sequence, hash: capture.hash)
        }
    }

    struct CaptureEdge: Codable, Sendable, Equatable, Hashable {
        public let before: CaptureRef
        public let after: CaptureRef

        public init(before: CaptureRef, after: CaptureRef) {
            self.before = before
            self.after = after
        }

        public init(before: Capture, after: Capture) {
            self.init(before: CaptureRef(capture: before), after: CaptureRef(capture: after))
        }

        public var beforeHash: String { before.hash }
        public var afterHash: String { after.hash }
    }

    struct Context: Codable, Sendable, Equatable, Hashable {
        public static let empty = Context()

        /// Focused accessibility element, when the parser can map first
        /// responder state back to a heist id.
        public let focusedElementId: String?
        /// Software keyboard state affects text-entry affordances even when
        /// the hierarchy is otherwise unchanged.
        public let keyboardVisible: Bool?
        /// Screen identity derived from the parsed accessibility hierarchy.
        public let screenId: String?
        /// Front-to-back app window signal, normalized to avoid storing
        /// process object identifiers.
        public let windowStack: [WindowContext]

        public init(
            focusedElementId: String? = nil,
            keyboardVisible: Bool? = nil,
            screenId: String? = nil,
            windowStack: [WindowContext] = []
        ) {
            self.focusedElementId = focusedElementId
            self.keyboardVisible = keyboardVisible
            self.screenId = screenId
            self.windowStack = windowStack
        }
    }

    struct WindowContext: Codable, Sendable, Equatable, Hashable {
        public let index: Int
        public let level: Double
        public let isKeyWindow: Bool

        public init(index: Int, level: Double, isKeyWindow: Bool) {
            self.index = index
            self.level = level
            self.isKeyWindow = isKeyWindow
        }
    }

    enum ReceiptKind: String, Codable, Sendable, Equatable {
        case capture
    }

    struct ReceiptSample: Codable, Sendable, Equatable {
        public let heistId: String?
        public let summary: String

        public init(heistId: String? = nil, summary: String) {
            self.heistId = heistId
            self.summary = summary
        }
    }

    /// Compatibility view over an accessibility capture.
    struct Receipt: Codable, Sendable, Equatable {
        public let capture: Capture

        public init(capture: Capture) {
            self.capture = capture
        }

        public var sequence: Int { capture.sequence }
        public var hash: String { capture.hash }
        public var parentHash: String? { capture.parentHash }
        public var summary: String { capture.summary }
        public var interface: Interface { capture.interface }
        public var kind: ReceiptKind { .capture }

        public var samples: [ReceiptSample] {
            Array(interface.elements.prefix(5)).map {
                ReceiptSample(heistId: nonEmpty($0.heistId), summary: truncate(elementSummary($0), to: 80))
            }
        }

        public var omittedCount: Int? {
            let omitted = interface.elements.count - samples.count
            return omitted > 0 ? omitted : nil
        }
    }
}

extension AccessibilityTrace {
    var captureEndpointScreenName: String? {
        captures.last?.screenNameProjection
    }

    var captureEndpointScreenId: String? {
        captures.last?.screenIdProjection
    }
}

extension AccessibilityTrace.Capture {
    var screenNameProjection: String? {
        interface.elements
            .first(where: { $0.traits.contains(.header) })
            .flatMap(\.label)
    }

    var screenIdProjection: String? {
        context.screenId ?? interface.screenId
    }
}

private struct StableCaptureContent: Codable {
    let tree: [AccessibilityHierarchy]
    let annotations: InterfaceAnnotations
    let context: AccessibilityTrace.Context
}

private extension Array where Element == AccessibilityHierarchy {
    func hasSameShape(as other: [AccessibilityHierarchy]) -> Bool {
        guard count == other.count else { return false }
        return zip(self, other).allSatisfy { $0.hasSameShape(as: $1) }
    }

    var elementByTraversalIndex: [Int: AccessibilityElement] {
        Dictionary(uniqueKeysWithValues: indexedElements.map { ($0.traversalIndex, $0.element) })
    }

    var containerByPath: [TreePath: AccessibilityContainer] {
        let entries: [(TreePath, AccessibilityContainer)] = compactMapSubtrees { node, path in
            guard case .container(let container, _) = node else { return nil }
            return (path, container)
        }
        return Dictionary(uniqueKeysWithValues: entries)
    }

    func updatingElement(traversalIndex: Int, with element: AccessibilityElement) -> [AccessibilityHierarchy] {
        map { $0.updatingElement(traversalIndex: traversalIndex, with: element) }
    }

    func updatingContainer(path: TreePath, with container: AccessibilityContainer) -> [AccessibilityHierarchy] {
        enumerated().map { index, node in
            guard path.indices.first == index else { return node }
            return node.updatingContainer(path: TreePath([Int](path.indices.dropFirst())), with: container)
        }
    }
}

private extension AccessibilityHierarchy {
    func hasSameShape(as other: AccessibilityHierarchy) -> Bool {
        switch (self, other) {
        case (.element(_, let lhsIndex), .element(_, let rhsIndex)):
            return lhsIndex == rhsIndex
        case (.container(_, let lhsChildren), .container(_, let rhsChildren)):
            return lhsChildren.hasSameShape(as: rhsChildren)
        case (.element, .container), (.container, .element):
            return false
        }
    }

    func updatingElement(traversalIndex target: Int, with replacement: AccessibilityElement) -> AccessibilityHierarchy {
        switch self {
        case .element(_, let traversalIndex) where traversalIndex == target:
            return .element(replacement, traversalIndex: traversalIndex)
        case .element:
            return self
        case .container(let container, let children):
            return .container(
                container,
                children: children.map { $0.updatingElement(traversalIndex: target, with: replacement) }
            )
        }
    }

    func updatingContainer(path: TreePath, with replacement: AccessibilityContainer) -> AccessibilityHierarchy {
        guard let first = path.indices.first else {
            guard case .container(_, let children) = self else { return self }
            return .container(replacement, children: children)
        }
        guard case .container(let container, let children) = self else { return self }
        let remainingPath = TreePath(Array(path.indices.dropFirst()))
        return .container(
            container,
            children: children.enumerated().map { index, child in
                index == first ? child.updatingContainer(path: remainingPath, with: replacement) : child
            }
        )
    }
}

private func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
}

private func nonEmpty(_ value: String?) -> String? {
    guard let normalized = normalized(value), !normalized.isEmpty else { return nil }
    return normalized
}

private func truncate(_ value: String, to limit: Int) -> String {
    guard limit > 3, value.count > limit else { return value }
    return String(value.prefix(limit - 3)) + "..."
}

private func elementSummary(_ element: HeistElement) -> String {
    let role = element.traits.first?.rawValue ?? nonEmpty(element.description) ?? "element"
    if let label = nonEmpty(element.label) {
        return "\(role) \"\(label)\""
    }
    if let value = nonEmpty(element.value) {
        return "\(role) = \"\(value)\""
    }
    return role
}
