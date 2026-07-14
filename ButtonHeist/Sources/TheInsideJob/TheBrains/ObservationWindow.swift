#if canImport(UIKit)
#if DEBUG
import Foundation
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
    internal let captures: [SettledCapture]

    internal var current: SettledCapture {
        captures[captures.count - 1]
    }

    internal var trace: AccessibilityTrace {
        AccessibilityTrace(captures: captures.map(\.capture))
    }

    internal init(
        baseline: SettledCapture,
        retainedEntries: [ObservationEntry]
    ) throws(ObservationWindowConstructionError) {
        var expectedCursor = baseline.cursor
        var captures = [baseline]
        captures.reserveCapacity(retainedEntries.count + 1)
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
            captures.append(entry.settledCapture)
            expectedCursor = entry.cursor
        }
        let current = captures[captures.count - 1]
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
            captures: captures,
            completeness: completeness
        )
    }

    private init(
        baseline: SettledCapture,
        captures: [SettledCapture],
        completeness: Completeness
    ) {
        precondition(!captures.isEmpty, "Observation windows require at least one observed capture")
        self.baseline = baseline
        self.captures = captures
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
            captures: contiguousCapturedSuffix(
                endingAt: current,
                retainedEntries: retainedEntries
            ),
            completeness: .incomplete(gap)
        )
    }

    private static func contiguousCapturedSuffix(
        endingAt current: SettledCapture,
        retainedEntries: [ObservationEntry]
    ) -> [SettledCapture] {
        guard retainedEntries.last?.cursor == current.cursor else { return [current] }
        var firstIndex = retainedEntries.index(before: retainedEntries.endIndex)
        while firstIndex > retainedEntries.startIndex {
            let previousIndex = retainedEntries.index(before: firstIndex)
            let previousCursor = retainedEntries[firstIndex].transition.previousCursor
            guard previousCursor == retainedEntries[previousIndex].cursor else { break }
            firstIndex = previousIndex
        }
        return retainedEntries[firstIndex...].map(\.settledCapture)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
