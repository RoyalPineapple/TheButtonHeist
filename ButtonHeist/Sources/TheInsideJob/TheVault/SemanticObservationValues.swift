#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

internal struct ScreenGeneration: RawRepresentable, Sendable, Equatable, Hashable {
    internal static let initial = ScreenGeneration(rawValue: 0)

    internal let rawValue: UInt64

    internal func advanced() -> ScreenGeneration {
        ScreenGeneration(rawValue: rawValue + 1)
    }
}

internal struct ObservationCursor: Sendable, Equatable, Hashable {
    internal let generation: ScreenGeneration
    internal let scope: SemanticObservationScope
    internal let sequence: SettledObservationSequence
    internal let captureHash: String
    internal let notificationSequence: UInt64
    internal let observedAt: Date

    internal init(
        generation: ScreenGeneration,
        scope: SemanticObservationScope,
        sequence: SettledObservationSequence,
        capture: AccessibilityTrace.Capture,
        notificationSequence: UInt64
    ) {
        self.generation = generation
        self.scope = scope
        self.sequence = sequence
        captureHash = capture.hash
        self.notificationSequence = notificationSequence
        observedAt = capture.interface.timestamp
    }
}

internal struct SettledCapture: Sendable, Equatable {
    internal let cursor: ObservationCursor
    internal let capture: AccessibilityTrace.Capture

    internal init(cursor: ObservationCursor, capture: AccessibilityTrace.Capture) {
        precondition(cursor.captureHash == capture.hash, "settled capture cursor must identify its capture")
        self.cursor = cursor
        self.capture = capture
    }

    internal init?(previousOf event: SettledObservationEvent) {
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
        case historyEvicted
    }

    internal let reason: Reason
    internal let baseline: ObservationCursor
    internal let current: ObservationCursor
}

internal enum ObservationTransitionValidationError: Error, Sendable, Equatable {
    case scopeMismatch(from: SemanticObservationScope, to: SemanticObservationScope)
    case sequenceDidNotAdvance(from: SettledObservationSequence, to: SettledObservationSequence)
    case generationMismatch(from: ScreenGeneration, to: ScreenGeneration)
    case replacementGenerationDidNotAdvance(from: ScreenGeneration, to: ScreenGeneration)
}

private enum ObservationTransitionLineage {
    static func validate(
        from previousCursor: ObservationCursor,
        to currentCursor: ObservationCursor
    ) throws(ObservationTransitionValidationError) {
        guard currentCursor.scope == previousCursor.scope else {
            throw ObservationTransitionValidationError.scopeMismatch(
                from: previousCursor.scope,
                to: currentCursor.scope
            )
        }
        guard currentCursor.sequence > previousCursor.sequence else {
            throw ObservationTransitionValidationError.sequenceDidNotAdvance(
                from: previousCursor.sequence,
                to: currentCursor.sequence
            )
        }
    }
}

internal struct SameGenerationTransition: Sendable, Equatable {
    internal let previousCursor: ObservationCursor

    internal init(
        from previousCursor: ObservationCursor,
        to currentCursor: ObservationCursor
    ) throws(ObservationTransitionValidationError) {
        try ObservationTransitionLineage.validate(
            from: previousCursor,
            to: currentCursor
        )
        guard currentCursor.generation == previousCursor.generation else {
            throw ObservationTransitionValidationError.generationMismatch(
                from: previousCursor.generation,
                to: currentCursor.generation
            )
        }
        self.previousCursor = previousCursor
    }
}

internal struct ScreenBoundaryTransition: Sendable, Equatable {
    internal let previousCursor: ObservationCursor

    internal init(
        from previousCursor: ObservationCursor,
        to currentCursor: ObservationCursor
    ) throws(ObservationTransitionValidationError) {
        try ObservationTransitionLineage.validate(
            from: previousCursor,
            to: currentCursor
        )
        guard currentCursor.generation.rawValue > previousCursor.generation.rawValue else {
            throw ObservationTransitionValidationError.replacementGenerationDidNotAdvance(
                from: previousCursor.generation,
                to: currentCursor.generation
            )
        }
        self.previousCursor = previousCursor
    }
}

internal enum ObservationTransition: Sendable, Equatable {
    case initial
    case sameGeneration(SameGenerationTransition)
    case screenBoundary(ScreenBoundaryTransition)

    internal var previousCursor: ObservationCursor? {
        switch self {
        case .initial:
            nil
        case .sameGeneration(let transition):
            transition.previousCursor
        case .screenBoundary(let transition):
            transition.previousCursor
        }
    }
}

/// One retained settled event and the typed edge that admitted it.
internal struct ObservationEntry: Sendable, Equatable {
    internal let event: SettledObservationEvent
    internal let transition: ObservationTransition

    internal var settledCapture: SettledCapture {
        Self.settledCapture(for: event)
    }

    internal var cursor: ObservationCursor {
        settledCapture.cursor
    }

    internal static func initial(_ event: SettledObservationEvent) -> ObservationEntry {
        ObservationEntry(event: event, transition: .initial)
    }

    internal static func sameGeneration(
        _ event: SettledObservationEvent,
        after previousCursor: ObservationCursor
    ) throws(ObservationTransitionValidationError) -> ObservationEntry {
        let transition = try SameGenerationTransition(
            from: previousCursor,
            to: settledCapture(for: event).cursor
        )
        return ObservationEntry(
            event: event,
            transition: .sameGeneration(transition)
        )
    }

    internal static func screenBoundary(
        _ event: SettledObservationEvent,
        replacing previousCursor: ObservationCursor
    ) throws(ObservationTransitionValidationError) -> ObservationEntry {
        let transition = try ScreenBoundaryTransition(
            from: previousCursor,
            to: settledCapture(for: event).cursor
        )
        return ObservationEntry(
            event: event,
            transition: .screenBoundary(transition)
        )
    }

    internal init(
        event: SettledObservationEvent,
        transition: ObservationTransition
    ) {
        self.event = event
        self.transition = transition
    }

    private static func settledCapture(
        for event: SettledObservationEvent
    ) -> SettledCapture {
        guard let capture = event.settledCapture else {
            preconditionFailure("Published semantic observation has no settled capture")
        }
        return capture
    }
}

/// A settled semantic tree and the signal that admitted it.
internal struct SettledObservation: Sendable, Equatable {
    internal let sequence: SettledObservationSequence
    internal let scope: SemanticObservationScope
    internal let semanticSignal: TheTripwire.SemanticSignal
    private let tree: InterfaceTree
    private let captureID: InterfaceCaptureID

    internal var observation: InterfaceObservation {
        do {
            return try InterfaceObservation.build(
                tree: tree,
                dispatchReferences: .empty,
                captureID: captureID
            )
        } catch {
            preconditionFailure("Settled semantic observation failed validation: \(error)")
        }
    }

    internal init(
        sequence: SettledObservationSequence,
        scope: SemanticObservationScope,
        observation: InterfaceObservation,
        semanticSignal: TheTripwire.SemanticSignal
    ) {
        self.sequence = sequence
        self.scope = scope
        self.semanticSignal = semanticSignal
        self.tree = observation.tree
        self.captureID = observation.captureID
    }
}

/// One committed settled observation with its generation and evidence lineage.
internal struct SettledObservationEvent: Sendable, Equatable {
    internal let generation: ScreenGeneration
    internal let continuity: ScreenContinuity
    internal let settledObservation: SettledObservation
    internal let previous: SettledObservation?
    internal let previousCursor: ObservationCursor?
    internal let notificationSequence: UInt64
    internal let trace: AccessibilityTrace

    internal var sequence: SettledObservationSequence { settledObservation.sequence }
    internal var scope: SemanticObservationScope { settledObservation.scope }

    internal var cursor: ObservationCursor? {
        trace.captures.last.map {
            ObservationCursor(
                generation: generation,
                scope: scope,
                sequence: sequence,
                capture: $0,
                notificationSequence: notificationSequence
            )
        }
    }

    internal var settledCapture: SettledCapture? {
        guard let cursor, let capture = trace.captures.last else { return nil }
        return SettledCapture(cursor: cursor, capture: capture)
    }

    internal var latestCaptureRef: AccessibilityTrace.CaptureRef? {
        trace.captures.last.map(AccessibilityTrace.CaptureRef.init(capture:))
    }

    internal init(
        generation: ScreenGeneration = .initial,
        continuity: ScreenContinuity,
        settledObservation: SettledObservation,
        previous: SettledObservation?,
        previousCursor: ObservationCursor? = nil,
        notificationSequence: UInt64 = 0,
        trace: AccessibilityTrace
    ) {
        self.generation = generation
        self.continuity = continuity
        self.settledObservation = settledObservation
        self.previous = previous
        self.previousCursor = previousCursor
        self.notificationSequence = notificationSequence
        self.trace = trace
    }

}

/// A semantic observation admitted for commit.
internal struct CommittableInterfaceObservation {
    internal let observation: InterfaceObservation
    internal let tripwireSignal: TheTripwire.TripwireSignal
    internal let discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy
    internal let lineageEvidence: ScreenLineageEvidence?

    private init(
        observation: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface,
        lineageEvidence: ScreenLineageEvidence? = nil
    ) {
        self.observation = observation
        self.tripwireSignal = tripwireSignal
        self.discoveryCommitPolicy = discoveryCommitPolicy
        self.lineageEvidence = lineageEvidence
    }

    internal static func admittedForTesting(
        _ observation: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal,
        lineageEvidence: ScreenLineageEvidence? = nil
    ) -> Self {
        Self(
            observation: observation,
            tripwireSignal: tripwireSignal,
            lineageEvidence: lineageEvidence
        )
    }

    @MainActor internal static func admit(
        _ settleResult: SettleSession.Result,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface,
        lineageEvidence: ScreenLineageEvidence? = nil
    ) -> CommittableInterfaceObservation? {
        guard settleResult.outcome.didSettleCleanly,
              let finalObservation = settleResult.finalObservation else { return nil }
        return CommittableInterfaceObservation(
            observation: finalObservation.observation,
            tripwireSignal: settleResult.tripwireSignal,
            discoveryCommitPolicy: discoveryCommitPolicy,
            lineageEvidence: lineageEvidence
        )
    }
}

/// The settlement result available after an action observation attempt.
internal struct ObservationSettlement {
    internal enum CommitOutcome {
        case committed(SettledObservationEvent)
        case observedUnsettled(InterfaceObservation, notificationBatch: AccessibilityNotificationBatch?)
        case unavailable(notificationBatch: AccessibilityNotificationBatch?)
    }

    internal let settleResult: SettleSession.Result
    internal let commitOutcome: CommitOutcome
}

#endif // DEBUG
#endif // canImport(UIKit)
