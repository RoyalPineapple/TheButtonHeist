import CryptoKit
import Foundation

import ThePlans

import AccessibilitySnapshotModel

private enum AccessibilityTraceCaptureCodingKeys: String, CodingKey {
    case sequence
    case hash
    case parentHash
    case interface
    case context
    case transition
}

private enum AccessibilityTraceTransitionCodingKeys: String, CodingKey, CaseIterable {
    case fallbackReason
    case transient
    case accessibilityNotifications
    case accessibilityNotificationGap
}

public extension AccessibilityTrace {
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
            context = try container.decode(Context.self, forKey: .context)
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
            let countSummary = "\(interface.projectedElements.count) elements"
            let description = normalized(InterfaceSummary.screenDescription(for: interface))
            return description == countSummary
                ? countSummary
                : "\(description ?? countSummary) (\(interface.projectedElements.count) elements)"
        }

        public static func hash(_ interface: Interface) -> String {
            hash(interface: interface, context: .empty)
        }

        public static func hash(interface: Interface, context: Context) -> String {
            let encoder = stableHashEncoder()
            let content = StableCaptureContent(
                tree: interface.tree.map(StableCaptureNode.init),
                annotations: StableCaptureAnnotations(interface.annotations),
                context: context
            )
            let data = stableHashData(content, encoder: encoder)
            return "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        private static func stableHashEncoder() -> JSONEncoder {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.nonConformingFloatEncodingStrategy = .convertToString(
                positiveInfinity: "Infinity",
                negativeInfinity: "-Infinity",
                nan: "NaN"
            )
            return encoder
        }

        private static func stableHashData<T: Encodable>(_ value: T, encoder: JSONEncoder) -> Data {
            switch Result(catching: { try encoder.encode(value) }) {
            case .success(let data):
                return data
            case .failure(let error):
                preconditionFailure("Stable accessibility trace hash payload failed to encode: \(error)")
            }
        }
    }

    struct Transition: Codable, Sendable, Equatable, Hashable {
        public static let empty = Transition()

        /// Typed fallback reason used when scoped notifications did not
        /// identify the screen transition.
        public let fallbackReason: AccessibilityObservationFallbackReason?
        /// Elements that appeared and disappeared while settling this edge.
        public let transient: [HeistElement]
        /// AX notification traffic observed while moving into this capture.
        /// Element payloads reference nodes in this capture's interface tree.
        public let accessibilityNotifications: [AccessibilityNotificationEvidence]
        /// Present when the bounded notification stream dropped events before
        /// this edge was captured. Absence means the edge is complete.
        public let accessibilityNotificationGap: AccessibilityNotificationGap?

        public init(
            fallbackReason: AccessibilityObservationFallbackReason? = nil,
            transient: [HeistElement] = [],
            accessibilityNotifications: [AccessibilityNotificationEvidence] = [],
            accessibilityNotificationGap: AccessibilityNotificationGap? = nil
        ) {
            self.fallbackReason = fallbackReason
            self.transient = transient
            self.accessibilityNotifications = accessibilityNotifications
            self.accessibilityNotificationGap = accessibilityNotificationGap
        }

        public var isEmpty: Bool {
            fallbackReason == nil
                && transient.isEmpty
                && accessibilityNotifications.isEmpty
                && accessibilityNotificationGap == nil
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(
                allowed: AccessibilityTraceTransitionCodingKeys.self,
                typeName: "accessibility trace transition"
            )
            let container = try decoder.container(keyedBy: AccessibilityTraceTransitionCodingKeys.self)
            self.init(
                fallbackReason: try container.decodeIfPresent(
                    AccessibilityObservationFallbackReason.self,
                    forKey: .fallbackReason
                ),
                transient: try container.decodeIfPresent([HeistElement].self, forKey: .transient) ?? [],
                accessibilityNotifications: try container.decodeIfPresent(
                    [AccessibilityNotificationEvidence].self,
                    forKey: .accessibilityNotifications
                ) ?? [],
                accessibilityNotificationGap: try container.decodeIfPresent(
                    AccessibilityNotificationGap.self,
                    forKey: .accessibilityNotificationGap
                )
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: AccessibilityTraceTransitionCodingKeys.self)
            try container.encodeIfPresent(fallbackReason, forKey: .fallbackReason)
            if !transient.isEmpty {
                try container.encode(transient, forKey: .transient)
            }
            if !accessibilityNotifications.isEmpty {
                try container.encode(accessibilityNotifications, forKey: .accessibilityNotifications)
            }
            try container.encodeIfPresent(accessibilityNotificationGap, forKey: .accessibilityNotificationGap)
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

        /// The focused (first responder) element, as a durable target
        /// (predicate + ordinal) built server-side via the minimum predicate selector.
        /// No internal id crosses the wire.
        public let firstResponder: AccessibilityTarget?
        /// Software keyboard state affects text-entry affordances even when
        /// the hierarchy is otherwise unchanged.
        public let keyboardVisible: Bool?
        /// Screen identity derived from the parsed accessibility hierarchy.
        public let screenId: String?
        /// Monotonic screen-generation identity owned by the settled
        /// observation stream. Updates are valid only within one generation.
        public let observationGeneration: UInt64?
        /// Front-to-back app window signal, normalized to avoid storing
        /// process object identifiers.
        public let windowStack: [WindowContext]

        public init(
            firstResponder: AccessibilityTarget? = nil,
            keyboardVisible: Bool? = nil,
            screenId: String? = nil,
            observationGeneration: UInt64? = nil,
            windowStack: [WindowContext] = []
        ) {
            self.firstResponder = firstResponder
            self.keyboardVisible = keyboardVisible
            self.screenId = screenId
            self.observationGeneration = observationGeneration
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

}

private struct StableCaptureContent: Codable {
    let tree: [StableCaptureNode]
    let annotations: StableCaptureAnnotations
    let context: AccessibilityTrace.Context
}

private enum StableCaptureNode: Codable {
    case element(StableCaptureElement, traversalIndex: Int)
    case container(StableCaptureContainer, children: [StableCaptureNode])

    init(_ node: AccessibilityHierarchy) {
        switch node {
        case .element(let element, let traversalIndex):
            self = .element(StableCaptureElement(element), traversalIndex: traversalIndex)
        case .container(let container, let children):
            self = .container(StableCaptureContainer(container), children: children.map(Self.init))
        }
    }
}

private struct StableCaptureElement: Codable {
    let description: String
    let label: String?
    let value: String?
    let traits: UInt64
    let identifier: String?
    let hint: String?
    let userInputLabels: [String]?
    let customActions: [String]
    let customContent: [StableCaptureCustomContent]
    let customRotors: [String]
    let accessibilityLanguage: String?
    let respondsToUserInteraction: Bool

    init(_ element: AccessibilityElement) {
        description = element.description
        label = element.label
        value = element.value
        traits = element.traits.rawValue
        identifier = element.identifier
        hint = element.hint
        userInputLabels = element.userInputLabels
        customActions = element.customActions.map(\.name).filter { !$0.isEmpty }.sorted()
        customContent = element.customContent
            .filter { !$0.label.isEmpty || !$0.value.isEmpty }
            .map(StableCaptureCustomContent.init)
        customRotors = element.customRotors.map(\.name).filter { !$0.isEmpty }.sorted()
        accessibilityLanguage = element.accessibilityLanguage
        respondsToUserInteraction = element.respondsToUserInteraction
    }
}

private struct StableCaptureCustomContent: Codable {
    let label: String
    let value: String
    let isImportant: Bool

    init(_ content: AccessibilityElement.CustomContent) {
        label = content.label
        value = content.value
        isImportant = content.isImportant
    }
}

private struct StableCaptureContainer: Codable {
    let type: ContainerPredicateRoleFacts
    let identifier: String?
    let scrollableContentSize: AccessibilitySize?
    let isModalBoundary: Bool
    let customActions: [String]

    init(_ container: AccessibilityContainer) {
        let facts = container.containerPredicateFacts
        type = facts.role
        identifier = facts.identifier
        scrollableContentSize = container.scrollableContentSize
        isModalBoundary = facts.isModalBoundary
        customActions = facts.actions.compactMap { action in
            guard case .custom(let name) = action else { return nil }
            return name
        }.sorted()
    }
}

private struct StableCaptureAnnotations: Codable {
    let elements: [InterfaceElementAnnotation]

    init(_ annotations: InterfaceAnnotations) {
        elements = annotations.elements
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
