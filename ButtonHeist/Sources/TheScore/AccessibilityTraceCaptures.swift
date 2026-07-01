import ThePlans
import CryptoKit
import Foundation
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
    case screenChangeReason
    case transient
    case accessibilityNotifications
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
                tree: interface.tree,
                annotations: interface.annotations,
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

        /// Reason a same-edge transition was classified as a screen change.
        /// Stored as a string so producers outside TheScore can evolve their
        /// classifier without making this wire receipt depend on that enum.
        public let screenChangeReason: String?
        /// Elements that appeared and disappeared while settling this edge.
        public let transient: [HeistElement]
        /// AX notification traffic observed while moving into this capture.
        /// Element payloads reference nodes in this capture's interface tree.
        public let accessibilityNotifications: [AccessibilityNotificationEvidence]

        public init(
            screenChangeReason: String? = nil,
            transient: [HeistElement] = [],
            accessibilityNotifications: [AccessibilityNotificationEvidence] = []
        ) {
            self.screenChangeReason = screenChangeReason
            self.transient = transient
            self.accessibilityNotifications = accessibilityNotifications
        }

        public var isEmpty: Bool {
            screenChangeReason == nil && transient.isEmpty && accessibilityNotifications.isEmpty
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(
                allowed: AccessibilityTraceTransitionCodingKeys.self,
                typeName: "accessibility trace transition"
            )
            let container = try decoder.container(keyedBy: AccessibilityTraceTransitionCodingKeys.self)
            self.init(
                screenChangeReason: try container.decodeIfPresent(String.self, forKey: .screenChangeReason),
                transient: try container.decodeIfPresent([HeistElement].self, forKey: .transient) ?? [],
                accessibilityNotifications: try container.decodeIfPresent(
                    [AccessibilityNotificationEvidence].self,
                    forKey: .accessibilityNotifications
                ) ?? []
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: AccessibilityTraceTransitionCodingKeys.self)
            try container.encodeIfPresent(screenChangeReason, forKey: .screenChangeReason)
            if !transient.isEmpty {
                try container.encode(transient, forKey: .transient)
            }
            if !accessibilityNotifications.isEmpty {
                try container.encode(accessibilityNotifications, forKey: .accessibilityNotifications)
            }
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
        public let firstResponder: ElementTarget?
        /// Software keyboard state affects text-entry affordances even when
        /// the hierarchy is otherwise unchanged.
        public let keyboardVisible: Bool?
        /// Screen identity derived from the parsed accessibility hierarchy.
        public let screenId: String?
        /// Front-to-back app window signal, normalized to avoid storing
        /// process object identifiers.
        public let windowStack: [WindowContext]

        public init(
            firstResponder: ElementTarget? = nil,
            keyboardVisible: Bool? = nil,
            screenId: String? = nil,
            windowStack: [WindowContext] = []
        ) {
            self.firstResponder = firstResponder
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

}

private struct StableCaptureContent: Codable {
    let tree: [AccessibilityHierarchy]
    let annotations: InterfaceAnnotations
    let context: AccessibilityTrace.Context
}

private func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
}
