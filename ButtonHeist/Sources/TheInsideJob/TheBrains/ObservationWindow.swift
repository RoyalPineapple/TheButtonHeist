#if canImport(UIKit)
#if DEBUG
import TheScore

internal enum Completeness: Sendable, Equatable {
    case complete
    case incomplete(ObservationGap)
}

internal enum ObservationWindowConstructionError: Error, Sendable, Equatable {
    case unexpectedInitialEntry(ObservationCursor)
    case discontinuousLineage(expected: ObservationCursor, actual: ObservationCursor)
}

internal struct ObservationWindow: Sendable, Equatable {
    internal let baseline: SettledCapture
    internal let completeness: Completeness
    internal let priorCaptures: [SettledCapture]
    internal let current: SettledCapture
    internal var captures: [SettledCapture] { priorCaptures + [current] }

    internal var trace: AccessibilityTrace {
        AccessibilityTrace(captures: captures.map(\.capture))
    }

    internal init(
        baseline: SettledCapture,
        retainedEntries: [ObservationEntry]
    ) throws(ObservationWindowConstructionError) {
        var expectedCursor = baseline.cursor
        var current = baseline
        var priorCaptures: [SettledCapture] = []
        for entry in retainedEntries {
            guard let previousCursor = entry.transition.previousCursor else {
                throw ObservationWindowConstructionError.unexpectedInitialEntry(entry.cursor)
            }
            guard previousCursor == expectedCursor else {
                throw ObservationWindowConstructionError.discontinuousLineage(
                    expected: expectedCursor,
                    actual: previousCursor
                )
            }
            priorCaptures.append(current)
            current = entry.settledCapture
            expectedCursor = entry.cursor
        }
        let completeness: Completeness = if retainedEntries.isEmpty {
            .incomplete(ObservationGap(
                reason: .noObservationAfterBaseline,
                baseline: baseline.cursor,
                current: current.cursor
            ))
        } else {
            .complete
        }
        self.init(
            baseline: baseline,
            current: current,
            priorCaptures: priorCaptures,
            completeness: completeness
        )
    }

    private init(
        baseline: SettledCapture,
        current: SettledCapture,
        priorCaptures: [SettledCapture],
        completeness: Completeness
    ) {
        self.baseline = baseline
        self.current = current
        self.priorCaptures = priorCaptures
        self.completeness = completeness
    }

    internal static func incomplete(
        baseline: SettledCapture,
        current: SettledCapture,
        retainedEntries: [ObservationEntry],
        gap: ObservationGap
    ) -> ObservationWindow {
        precondition(gap.baseline == baseline.cursor, "Observation gap must describe its baseline")
        precondition(gap.current == current.cursor, "Observation gap must describe its current capture")
        return ObservationWindow(
            baseline: baseline,
            current: current,
            priorCaptures: contiguousPriorCaptures(
                endingAt: current,
                retainedEntries: retainedEntries
            ),
            completeness: .incomplete(gap)
        )
    }

    private static func contiguousPriorCaptures(
        endingAt current: SettledCapture,
        retainedEntries: [ObservationEntry]
    ) -> [SettledCapture] {
        guard retainedEntries.last?.cursor == current.cursor else { return [] }
        var firstIndex = retainedEntries.index(before: retainedEntries.endIndex)
        while firstIndex > retainedEntries.startIndex {
            let previousIndex = retainedEntries.index(before: firstIndex)
            let previousCursor = retainedEntries[firstIndex].transition.previousCursor
            guard previousCursor == retainedEntries[previousIndex].cursor else { break }
            firstIndex = previousIndex
        }
        return retainedEntries[firstIndex...].dropLast().map(\.settledCapture)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
