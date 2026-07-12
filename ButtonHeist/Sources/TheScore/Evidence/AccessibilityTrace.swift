import ThePlans
import Foundation

// MARK: - Accessibility Trace

/// Accessibility state observed during a session.
///
/// Captures are the durable source of truth. Change facts are derived
/// projections for callers that need compact change summaries.
public struct AccessibilityTrace: Codable, Sendable, Equatable {
    public let captures: [Capture]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case captures
    }

    public init(captures: [Capture]) {
        self.captures = Self.normalized(captures)
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
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "AccessibilityTrace")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(captures: try container.decode([Capture].self, forKey: .captures))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(captures, forKey: .captures)
    }

    private static func normalized(_ captures: [Capture]) -> [Capture] {
        var previousCapture: Capture?
        return captures.enumerated().map { index, capture in
            let linked = Capture(
                sequence: index + 1,
                interface: capture.interface,
                parentHash: previousCapture?.hash,
                context: capture.context,
                transition: capture.transition,
                hash: capture.hash
            )
            previousCapture = linked
            return linked
        }
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

}
