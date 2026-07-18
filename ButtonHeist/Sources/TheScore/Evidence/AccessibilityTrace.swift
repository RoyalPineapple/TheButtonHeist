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

    package init(captures: [Capture]) {
        precondition(
            Self.hasCanonicalLineage(captures),
            "Accessibility trace source must provide canonical capture lineage"
        )
        self.captures = captures
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
        let captures = try container.decode([Capture].self, forKey: .captures)
        guard Self.hasCanonicalLineage(captures) else {
            throw DecodingError.dataCorruptedError(
                forKey: .captures,
                in: container,
                debugDescription: "Accessibility trace captures must have contiguous sequence and exact parent lineage"
            )
        }
        self.captures = captures
    }

    private static func hasCanonicalLineage(_ captures: [Capture]) -> Bool {
        captures.enumerated().allSatisfy { index, capture in
            guard index > 0 else { return true }
            let previous = captures[index - 1]
            return capture.sequence == previous.sequence + 1
                && capture.parentHash == previous.hash
        }
    }

    public func appending(
        _ interface: Interface,
        context: Context = .empty,
        transition: Transition = .empty
    ) -> AccessibilityTrace {
        let capture = Capture(
            sequence: (captures.last?.sequence ?? 0) + 1,
            interface: interface,
            parentHash: captures.last?.hash,
            context: context,
            transition: transition
        )
        return AccessibilityTrace(captures: captures + [capture])
    }

    public func capture(ref: CaptureRef) -> Capture? {
        captures.first { $0.sequence == ref.sequence && $0.hash == ref.hash }
    }
}
