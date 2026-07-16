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
    internal let observedAt: Date

    internal init(
        generation: ObservationGeneration,
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
        case historyEvicted
    }

    internal let reason: Reason
    internal let baseline: ObservationCursor
    internal let current: ObservationCursor
}

internal enum ObservationTransitionValidationError: Error, Sendable, Equatable {
    case scopeMismatch(from: SemanticObservationScope, to: SemanticObservationScope)
    case sequenceDidNotAdvance(from: SettledObservationSequence, to: SettledObservationSequence)
    case generationMismatch(from: ObservationGeneration, to: ObservationGeneration)
    case replacementGenerationDidNotAdvance(from: ObservationGeneration, to: ObservationGeneration)
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
    internal let event: SettledSemanticObservationEvent
    internal let transition: ObservationTransition

    internal var settledCapture: SettledCapture {
        Self.settledCapture(for: event)
    }

    internal var cursor: ObservationCursor {
        settledCapture.cursor
    }

    internal static func initial(_ event: SettledSemanticObservationEvent) -> ObservationEntry {
        ObservationEntry(event: event, transition: .initial)
    }

    internal static func sameGeneration(
        _ event: SettledSemanticObservationEvent,
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
        _ event: SettledSemanticObservationEvent,
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
        event: SettledSemanticObservationEvent,
        transition: ObservationTransition
    ) {
        self.event = event
        self.transition = transition
    }

    private static func settledCapture(
        for event: SettledSemanticObservationEvent
    ) -> SettledCapture {
        guard let capture = event.settledCapture else {
            preconditionFailure("Published semantic observation has no settled capture")
        }
        return capture
    }
}

/// A settled semantic tree and the signal that admitted it.
internal struct SettledSemanticObservation: Sendable, Equatable {
    internal let sequence: SettledObservationSequence
    internal let scope: SemanticObservationScope
    internal let semanticSignal: TheTripwire.SemanticSignal
    private let tree: InterfaceTree

    internal var screen: InterfaceObservation {
        do {
            return try InterfaceObservation.build(tree: tree)
        } catch {
            preconditionFailure("Settled semantic observation failed validation: \(error)")
        }
    }

    internal init(
        sequence: SettledObservationSequence,
        scope: SemanticObservationScope,
        screen: InterfaceObservation,
        semanticSignal: TheTripwire.SemanticSignal
    ) {
        self.sequence = sequence
        self.scope = scope
        self.semanticSignal = semanticSignal
        self.tree = screen.tree
    }
}

/// One published settled observation with its generation and evidence lineage.
internal struct SettledSemanticObservationEvent: Sendable, Equatable {
    internal let generation: ObservationGeneration
    internal let continuity: ScreenContinuity
    internal let sequence: SettledObservationSequence
    internal let scope: SemanticObservationScope
    internal let observation: SettledSemanticObservation
    internal let previous: SettledSemanticObservation?
    internal let previousCursor: ObservationCursor?
    internal let notificationSequence: UInt64
    internal let trace: AccessibilityTrace

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
        generation: ObservationGeneration = .initial,
        continuity: ScreenContinuity,
        sequence: SettledObservationSequence,
        scope: SemanticObservationScope,
        observation: SettledSemanticObservation,
        previous: SettledSemanticObservation?,
        previousCursor: ObservationCursor? = nil,
        notificationSequence: UInt64 = 0,
        trace: AccessibilityTrace
    ) {
        self.generation = generation
        self.continuity = continuity
        self.sequence = sequence
        self.scope = scope
        self.observation = observation
        self.previous = previous
        self.previousCursor = previousCursor
        self.notificationSequence = notificationSequence
        self.trace = trace
    }

    internal func replacingGeneration(_ generation: ObservationGeneration) -> SettledSemanticObservationEvent {
        SettledSemanticObservationEvent(
            generation: generation,
            continuity: continuity,
            sequence: sequence,
            scope: scope,
            observation: observation,
            previous: previous,
            previousCursor: previousCursor,
            notificationSequence: notificationSequence,
            trace: trace
        )
    }
}

/// Settled visible evidence returned to an observation consumer.
internal struct VisibleSemanticObservationEvidence {
    internal let screen: InterfaceObservation
    internal let settledObservationSequence: SettledObservationSequence?
    internal let settleOutcome: SettleOutcome
}

/// Validated evidence admitted for a semantic observation commit.
internal struct InterfaceObservationProof {
    internal let screen: InterfaceObservation
    internal let discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy
    internal let lineageEvidence: ScreenLineageEvidence?

    private init(
        screen: InterfaceObservation,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface,
        lineageEvidence: ScreenLineageEvidence? = nil
    ) {
        self.screen = screen
        self.discoveryCommitPolicy = discoveryCommitPolicy
        self.lineageEvidence = lineageEvidence
    }

    internal static func uncheckedForTesting(
        _ screen: InterfaceObservation,
        lineageEvidence: ScreenLineageEvidence? = nil
    ) -> Self {
        Self(screen: screen, lineageEvidence: lineageEvidence)
    }

    @MainActor internal static func settled(
        _ outcome: SettleSession.Outcome,
        stash: TheStash,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface
    ) -> InterfaceObservationProof? {
        validated(
            outcome,
            stash: stash,
            discoveryCommitPolicy: discoveryCommitPolicy,
            lineageEvidence: nil
        )
    }

    @MainActor internal static func settledAfterViewportMovement(
        _ outcome: SettleSession.Outcome,
        stash: TheStash,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface
    ) -> InterfaceObservationProof? {
        validated(
            outcome,
            stash: stash,
            discoveryCommitPolicy: discoveryCommitPolicy,
            lineageEvidence: .viewportMovement
        )
    }

    @MainActor private static func validated(
        _ outcome: SettleSession.Outcome,
        stash: TheStash,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy,
        lineageEvidence: ScreenLineageEvidence?
    ) -> InterfaceObservationProof? {
        guard outcome.outcome.didSettleCleanly,
              let finalObservation = outcome.finalObservation else { return nil }
        let screen = stash.latestObservation
        guard screen.captureToken == finalObservation.captureToken,
              screen.tree == finalObservation.tree,
              SettleTimeline.fingerprint(of: screen.liveCapture.hierarchy.sortedElements)
                == finalObservation.fingerprint else { return nil }
        return InterfaceObservationProof(
            screen: screen,
            discoveryCommitPolicy: discoveryCommitPolicy,
            lineageEvidence: lineageEvidence
        )
    }
}

/// The settlement result available after an action observation attempt.
internal struct PostActionSettleObservation {
    internal enum Result {
        case committed(SettledSemanticObservationEvent)
        case observedUnsettled(InterfaceTree, notificationBatch: AccessibilityNotificationBatch?)
        case unavailable(notificationBatch: AccessibilityNotificationBatch?)
    }

    internal let settle: SettleSession.Outcome
    internal let result: Result
}

// MARK: - Semantic Observation Projection

internal extension InterfaceObservation {
    func semanticObservationProjection(for scope: SemanticObservationScope) -> InterfaceObservation {
        switch scope {
        case .visible:
            return viewportOnly
        case .discovery:
            return self
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
