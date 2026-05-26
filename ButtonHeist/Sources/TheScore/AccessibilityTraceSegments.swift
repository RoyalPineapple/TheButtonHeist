import Foundation

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
            guard AccessibilityTrace.Delta.between(before, after).kind != .screenChanged else { return nil }
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
}
