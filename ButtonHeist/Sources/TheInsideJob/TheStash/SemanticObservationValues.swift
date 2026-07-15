#if canImport(UIKit)
#if DEBUG
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

    private init(
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
                captureHash: $0.hash,
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
        sequence: SettledObservationSequence,
        scope: SemanticObservationScope,
        observation: SettledSemanticObservation,
        previous: SettledSemanticObservation?,
        previousCursor: ObservationCursor? = nil,
        notificationSequence: UInt64 = 0,
        trace: AccessibilityTrace
    ) {
        self.generation = generation
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
    private enum GenerationAdmission {
        case classifyAtCommit
        case replace(reason: AccessibilityObservationFallbackReason)

        fileprivate var authoritativeReplacementClassification: ScreenClassifier.Classification? {
            guard case .replace(let reason) = self else { return nil }
            return .inferredScreenChange(reason: reason)
        }
    }

    internal let screen: InterfaceObservation
    private let generationAdmission: GenerationAdmission
    internal let discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy

    internal var authoritativeReplacementClassification: ScreenClassifier.Classification? {
        generationAdmission.authoritativeReplacementClassification
    }

    private init(
        screen: InterfaceObservation,
        generationAdmission: GenerationAdmission = .classifyAtCommit,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface
    ) {
        self.screen = screen
        self.generationAdmission = generationAdmission
        self.discoveryCommitPolicy = discoveryCommitPolicy
    }

    @MainActor internal static func settled(
        _ outcome: SettleSession.Outcome,
        stash: TheStash
    ) -> InterfaceObservationProof? {
        guard outcome.outcome.didSettleCleanly,
              let finalObservation = outcome.finalObservation else { return nil }
        let screen = stash.latestObservation
        guard screen.captureToken == finalObservation.captureToken,
              screen.tree == finalObservation.tree,
              SettleTimeline.fingerprint(of: screen.liveCapture.hierarchy.sortedElements)
                == finalObservation.fingerprint else { return nil }
        return InterfaceObservationProof(screen: screen)
    }

    @MainActor internal static func explored(
        _ exploration: Navigation.ExploredScreen,
        stash: TheStash
    ) -> InterfaceObservationProof? {
        guard exploration.screen.captureToken == stash.latestObservation.captureToken else {
            return nil
        }
        let generationAdmission: GenerationAdmission
        switch exploration.generationDisposition {
        case .preservesGeneration:
            generationAdmission = .classifyAtCommit
        case .replacesGeneration(let reason):
            generationAdmission = .replace(reason: reason)
        }
        return InterfaceObservationProof(
            screen: exploration.screen,
            generationAdmission: generationAdmission,
            discoveryCommitPolicy: exploration.discoveryCommitPolicy
        )
    }
}

fileprivate extension InterfaceObservationProof {
    static func forTesting(_ screen: InterfaceObservation) -> InterfaceObservationProof {
        InterfaceObservationProof(screen: screen)
    }
}

internal extension SemanticObservationStream {
    @discardableResult
    func commitVisibleObservationForTesting(
        _ screen: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil,
        notificationIdentityScreen: InterfaceObservation? = nil
    ) -> SettledSemanticObservationEvent {
        commitSettledVisibleObservation(
            .forTesting(screen),
            notificationBatch: notificationBatch,
            notificationIdentityScreen: notificationIdentityScreen
        )
    }

    @discardableResult
    func commitDiscoveryObservationForTesting(
        _ screen: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) -> SettledSemanticObservationEvent {
        commitSettledDiscoveryObservation(
            .forTesting(screen),
            notificationBatch: notificationBatch
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
