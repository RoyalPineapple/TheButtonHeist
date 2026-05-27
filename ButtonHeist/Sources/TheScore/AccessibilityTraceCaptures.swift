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
            let countSummary = "\(interface.elements.count) elements"
            let description = normalized(interface.screenDescription)
            return description == countSummary
                ? countSummary
                : "\(description ?? countSummary) (\(interface.elements.count) elements)"
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

    enum IntegrityIssue: Sendable, Equatable {
        case captureHashMismatch(
            index: Int,
            sequence: Int,
            recordedHash: String,
            computedHash: String
        )
        case parentHashMismatch(
            index: Int,
            sequence: Int,
            recordedParentHash: String?,
            expectedParentHash: String?
        )
    }

    struct Context: Codable, Sendable, Equatable, Hashable {
        public static let empty = Context()

        /// Focused accessibility element, when the parser can map first
        /// responder state back to a heist id.
        public let focusedElementId: HeistId?
        /// Software keyboard state affects text-entry affordances even when
        /// the hierarchy is otherwise unchanged.
        public let keyboardVisible: Bool?
        /// Screen identity derived from the parsed accessibility hierarchy.
        public let screenId: String?
        /// Front-to-back app window signal, normalized to avoid storing
        /// process object identifiers.
        public let windowStack: [WindowContext]

        public init(
            focusedElementId: HeistId? = nil,
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
        public let heistId: HeistId?
        public let summary: String

        public init(heistId: HeistId? = nil, summary: String) {
            self.heistId = heistId
            self.summary = summary
        }
    }

    /// Receipt projection over an accessibility capture.
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
