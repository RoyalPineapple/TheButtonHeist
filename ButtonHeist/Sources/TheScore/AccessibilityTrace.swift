import Foundation

// MARK: - Accessibility Trace

/// Accessibility state observed during a session.
///
/// Captures are the durable source of truth. Segments and replayable patches
/// are derived projections for callers that need compact change summaries.
public struct AccessibilityTrace: Codable, Sendable, Equatable {
    public let captures: [Capture]

    public var segments: [ScreenSegment] {
        Self.projectSegments(from: captures)
    }

    private enum CodingKeys: String, CodingKey {
        case captures
        case segments
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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.segments) {
            throw DecodingError.dataCorruptedError(
                forKey: .segments,
                in: container,
                debugDescription: "AccessibilityTrace stores captures; segments are derived projections and are not accepted as trace truth"
            )
        }
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

    private static func projectSegments(from captures: [Capture]) -> [ScreenSegment] {
        var segments: [ScreenSegment] = []
        var currentSegment: ScreenSegment?
        var previousCapture: Capture?

        for capture in captures {
            guard let before = previousCapture, var segment = currentSegment else {
                currentSegment = ScreenSegment(baseline: capture)
                previousCapture = capture
                continue
            }

            switch AccessibilityTrace.Delta.between(before, capture).kind {
            case .screenChanged:
                segments.append(segment)
                currentSegment = ScreenSegment(baseline: capture)
            case .elementsChanged, .noChange:
                guard let observed = ObservedTransition.between(before, capture) else {
                    segments.append(segment)
                    currentSegment = ScreenSegment(baseline: capture)
                    previousCapture = capture
                    continue
                }
                segment.append(observed)
                currentSegment = segment
            }
            previousCapture = capture
        }

        if let currentSegment {
            segments.append(currentSegment)
        }
        return segments
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

        for (index, capture) in captures.enumerated() {
            let computedHash = Capture.hash(interface: capture.interface, context: capture.context)
            if capture.hash != computedHash {
                issues.append(.captureHashMismatch(
                    index: index,
                    sequence: capture.sequence,
                    recordedHash: capture.hash,
                    computedHash: computedHash
                ))
            }
            if capture.parentHash != expectedParentHash {
                issues.append(.parentHashMismatch(
                    index: index,
                    sequence: capture.sequence,
                    recordedParentHash: capture.parentHash,
                    expectedParentHash: expectedParentHash
                ))
            }

            expectedParentHash = capture.hash
        }

        return issues
    }

    public var hasValidIntegrity: Bool {
        integrityIssues.isEmpty
    }

}
