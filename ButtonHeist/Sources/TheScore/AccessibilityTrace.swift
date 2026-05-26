import Foundation

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

            switch AccessibilityTrace.Delta.between(before, linked).kind {
            case .screenChanged:
                segments.append(segment)
                currentSegment = ScreenSegment(baseline: linked)
            case .elementsChanged, .noChange:
                guard let observed = ObservedTransition.between(before, linked) else {
                    segments.append(segment)
                    currentSegment = ScreenSegment(baseline: linked)
                    previousCapture = linked
                    continue
                }
                segment.append(observed)
                currentSegment = segment
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
