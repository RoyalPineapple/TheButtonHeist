#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

internal struct ObservationGeneration: RawRepresentable, Sendable, Equatable, Hashable {
    internal static let initial = ObservationGeneration(rawValue: 0)

    internal let rawValue: UInt64

    internal func advanced() -> ObservationGeneration {
        ObservationGeneration(rawValue: rawValue + 1)
    }
}

internal struct ObservationCursor: Sendable, Equatable, Hashable {
    internal let generation: ObservationGeneration
    internal let scope: SemanticObservationScope
    internal let sequence: SettledObservationSequence
    internal let captureHash: String
    internal let notificationSequence: UInt64
}

internal struct SettledCapture: Sendable, Equatable {
    internal let cursor: ObservationCursor
    internal let capture: AccessibilityTrace.Capture

    internal init(cursor: ObservationCursor, capture: AccessibilityTrace.Capture) {
        self.cursor = cursor
        self.capture = capture
    }

    internal init?(previousOf event: SettledSemanticObservationEvent) {
        guard let cursor = event.previousCursor,
              let capture = event.trace.captures.first,
              capture.hash == cursor.captureHash
        else { return nil }
        self.init(cursor: cursor, capture: capture)
    }
}

internal struct ObservationGap: Sendable, Equatable {
    internal enum Reason: Sendable, Equatable {
        case noObservationAfterBaseline
        case scopeChanged
        case historyUnavailable
    }

    internal let reason: Reason
    internal let baseline: ObservationCursor
    internal let current: ObservationCursor
}

internal enum Completeness: Sendable, Equatable {
    case complete
    case incomplete(ObservationGap)
}

internal struct ObservationWindow: Sendable, Equatable {
    private enum TraceHistory: Sendable, Equatable {
        case observed
        case supplied(prefix: AccessibilityTrace, continuation: [AccessibilityTrace.Capture])
    }

    internal let baseline: SettledCapture
    internal let current: SettledCapture
    internal let captures: [SettledCapture]
    internal let completeness: Completeness
    private let traceHistory: TraceHistory

    internal var trace: AccessibilityTrace {
        switch traceHistory {
        case .observed:
            AccessibilityTrace(captures: captures.map(\.capture))
        case .supplied(let prefix, let continuation):
            AccessibilityTrace(captures: Self.appending(continuation, to: prefix.captures))
        }
    }

    internal init(
        baseline: SettledCapture,
        current: SettledCapture,
        captures: [SettledCapture],
        completeness: Completeness
    ) {
        self.init(
            baseline: baseline,
            current: current,
            captures: captures,
            completeness: completeness,
            traceHistory: .observed
        )
    }

    private init(
        baseline: SettledCapture,
        current: SettledCapture,
        captures: [SettledCapture],
        completeness: Completeness,
        traceHistory: TraceHistory
    ) {
        self.baseline = baseline
        self.current = current
        self.captures = captures
        self.completeness = completeness
        self.traceHistory = traceHistory
    }

    internal static func direct(
        from baseline: SettledCapture,
        through event: SettledSemanticObservationEvent
    ) -> ObservationWindow? {
        guard let current = event.settledCapture else { return nil }
        let completeness: Completeness
        if baseline.cursor.scope != current.cursor.scope {
            completeness = .incomplete(ObservationGap(
                reason: .scopeChanged,
                baseline: baseline.cursor,
                current: current.cursor
            ))
        } else if current.cursor.sequence <= baseline.cursor.sequence {
            completeness = .incomplete(ObservationGap(
                reason: .noObservationAfterBaseline,
                baseline: baseline.cursor,
                current: current.cursor
            ))
        } else if event.previousCursor?.sequence == baseline.cursor.sequence,
                  event.previousCursor?.captureHash == baseline.cursor.captureHash {
            completeness = .complete
        } else {
            completeness = .incomplete(ObservationGap(
                reason: .historyUnavailable,
                baseline: baseline.cursor,
                current: current.cursor
            ))
        }
        return ObservationWindow(
            baseline: baseline,
            current: current,
            captures: [baseline, current],
            completeness: completeness
        )
    }

    internal func merging(
        _ candidate: ObservationWindow,
        previousCursor: ObservationCursor?
    ) -> ObservationWindow {
        guard candidate.current.cursor.sequence > current.cursor.sequence else {
            return self
        }
        let additionalCaptures = candidate.captures.filter {
            $0.cursor.sequence > current.cursor.sequence
        }
        guard !additionalCaptures.isEmpty else { return self }

        let continuesCurrentWindow = candidate.captures.contains { $0.cursor == current.cursor }
            || previousCursor == current.cursor
        let mergedCompleteness: Completeness
        if isComplete || isAwaitingFirstObservation, continuesCurrentWindow {
            mergedCompleteness = .complete
        } else {
            mergedCompleteness = .incomplete(ObservationGap(
                reason: Self.gapReason(
                    from: current.cursor,
                    to: candidate.current.cursor
                ),
                baseline: baseline.cursor,
                current: candidate.current.cursor
            ))
        }
        let mergedTraceHistory: TraceHistory = switch traceHistory {
        case .observed:
            .observed
        case .supplied(let prefix, let continuation):
            .supplied(
                prefix: prefix,
                continuation: Self.appending(
                    additionalCaptures.map(\.capture),
                    to: continuation
                )
            )
        }
        return ObservationWindow(
            baseline: baseline,
            current: candidate.current,
            captures: captures + additionalCaptures,
            completeness: mergedCompleteness,
            traceHistory: mergedTraceHistory
        )
    }

    internal func preserving(_ trace: AccessibilityTrace) -> ObservationWindow {
        let observedCaptures = captures.map(\.capture)
        let continuation: [AccessibilityTrace.Capture]
        if let endpointHash = trace.captures.last?.hash,
           let endpointIndex = observedCaptures.lastIndex(where: { $0.hash == endpointHash }) {
            continuation = Array(observedCaptures.suffix(from: observedCaptures.index(after: endpointIndex)))
        } else {
            continuation = [current.capture]
        }
        return ObservationWindow(
            baseline: baseline,
            current: current,
            captures: captures,
            completeness: completeness,
            traceHistory: .supplied(prefix: trace, continuation: continuation)
        )
    }

    private var isComplete: Bool {
        if case .complete = completeness { return true }
        return false
    }

    private var isAwaitingFirstObservation: Bool {
        guard baseline.cursor == current.cursor,
              case .incomplete(let gap) = completeness else { return false }
        return gap.reason == .noObservationAfterBaseline
    }

    private static func gapReason(
        from previous: ObservationCursor,
        to current: ObservationCursor
    ) -> ObservationGap.Reason {
        if previous.scope != current.scope {
            return .scopeChanged
        }
        if current.sequence <= previous.sequence {
            return .noObservationAfterBaseline
        }
        return .historyUnavailable
    }

    private static func appending(
        _ captures: [AccessibilityTrace.Capture],
        to existing: [AccessibilityTrace.Capture]
    ) -> [AccessibilityTrace.Capture] {
        captures.reduce(into: existing) { result, capture in
            guard result.last?.hash != capture.hash else { return }
            result.append(capture)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
