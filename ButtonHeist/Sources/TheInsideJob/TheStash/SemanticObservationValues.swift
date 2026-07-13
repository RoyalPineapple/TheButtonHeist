#if canImport(UIKit)
#if DEBUG
import TheScore

/// A settled semantic tree and the signal that admitted it.
internal struct SettledSemanticObservation: Sendable {
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
internal struct SettledSemanticObservationEvent: Sendable {
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

    internal static func testing(_ screen: InterfaceObservation) -> InterfaceObservationProof {
        InterfaceObservationProof(screen: screen)
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
