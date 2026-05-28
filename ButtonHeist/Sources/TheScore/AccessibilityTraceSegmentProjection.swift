import Foundation

public extension AccessibilityTrace {
    /// Derived same-screen run of captures. Captures remain trace truth; this
    /// projection is rebuilt from captures when callers need patch-style replay.
    struct ScreenSegmentProjection: Codable, Sendable, Equatable {
        public let baseline: Capture
        public private(set) var transitions: [ObservedTransitionProjection]

        public init(baseline: Capture, transitions: [ObservedTransitionProjection] = []) {
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

        public mutating func append(_ transition: ObservedTransitionProjection) {
            transitions.append(transition)
        }
    }

    /// Patch-backed edge used inside `ScreenSegmentProjection`.
    struct ObservedTransitionProjection: Codable, Sendable, Equatable {
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
        ) -> ObservedTransitionProjection? {
            guard AccessibilityTrace.Delta.between(before, after).kind != .screenChanged else { return nil }
            guard let patch = AccessibilityPatch.between(before, after) else { return nil }
            return ObservedTransitionProjection(
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

    var screenSegmentsProjection: [ScreenSegmentProjection] {
        Self.projectScreenSegments(from: captures)
    }

    private static func projectScreenSegments(from captures: [Capture]) -> [ScreenSegmentProjection] {
        var segments: [ScreenSegmentProjection] = []
        var currentSegment: ScreenSegmentProjection?
        var previousCapture: Capture?

        for capture in captures {
            guard let before = previousCapture, var segment = currentSegment else {
                currentSegment = ScreenSegmentProjection(baseline: capture)
                previousCapture = capture
                continue
            }

            switch AccessibilityTrace.Delta.between(before, capture).kind {
            case .screenChanged:
                segments.append(segment)
                currentSegment = ScreenSegmentProjection(baseline: capture)
            case .elementsChanged, .noChange:
                guard let observed = ObservedTransitionProjection.between(before, capture) else {
                    segments.append(segment)
                    currentSegment = ScreenSegmentProjection(baseline: capture)
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
}
