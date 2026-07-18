#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

/// Builds one publication from the log's latest per-scope events.
internal struct SemanticObservationPublication {
    internal typealias EventsByScope = [SemanticObservationScope: SettledObservationEvent]

    internal struct Evidence {
        internal let interface: Interface
        internal let accessibilityNotifications: [AccessibilityNotificationEvidence]
        internal let firstResponder: AccessibilityTarget?
    }

    internal struct Context {
        internal let continuity: ScreenContinuity
        internal let generation: ScreenGeneration
        internal let previousEvents: EventsByScope
    }

    internal let sourceScope: SemanticObservationScope
    internal let events: EventsByScope

    internal var sourceEvent: SettledObservationEvent {
        guard let event = events[sourceScope] else {
            preconditionFailure("Semantic observation publication has no source event")
        }
        return event
    }

    internal var generation: ScreenGeneration {
        sourceEvent.generation
    }

    // MARK: - Init

    internal init(
        sourceScope: SemanticObservationScope,
        events: EventsByScope
    ) {
        precondition(events[sourceScope] != nil, "Semantic observation scope did not fulfill itself")
        self.sourceScope = sourceScope
        self.events = events
    }

    // MARK: - Publication

    @MainActor
    internal static func make(
        sourceScope: SemanticObservationScope,
        sequence: SettledObservationSequence,
        notificationBatch: AccessibilityNotificationBatch,
        observation: InterfaceObservation,
        semanticSignal: TheTripwire.SemanticSignal,
        context: Context,
        evidenceByScope: [SemanticObservationScope: Evidence]
    ) -> SemanticObservationPublication {
        let eventGeneration = context.continuity.isReplacement
            ? context.generation.advanced()
            : context.generation
        var events: EventsByScope = [:]
        for fulfilledScope in sourceScope.fulfilledScopes {
            guard let evidence = evidenceByScope[fulfilledScope] else {
                preconditionFailure("Semantic observation publication has no evidence for fulfilled scope")
            }
            let previousEvent = context.previousEvents[fulfilledScope]
            let settledObservation = SettledObservation(
                sequence: sequence,
                scope: fulfilledScope,
                observation: observation.semanticObservationProjection(for: fulfilledScope),
                semanticSignal: semanticSignal
            )
            let previousCapture = previousEvent?.trace.captures.last
            let currentCapture = makeCapture(
                settledObservation: settledObservation,
                sequence: (previousCapture?.sequence ?? 0) + 1,
                parentHash: previousCapture?.hash,
                generation: eventGeneration,
                notificationBatch: notificationBatch,
                evidence: evidence,
                fallbackReason: context.continuity.fallbackReason
            )
            let trace = if let previousCapture {
                AccessibilityTrace(captures: [previousCapture, currentCapture])
            } else {
                AccessibilityTrace(capture: currentCapture)
            }
            events[fulfilledScope] = SettledObservationEvent(
                generation: eventGeneration,
                continuity: context.continuity,
                settledObservation: settledObservation,
                previous: previousEvent?.settledObservation,
                previousCursor: previousEvent?.cursor,
                notificationSequence: notificationBatch.through.sequence,
                trace: trace
            )
        }
        return SemanticObservationPublication(sourceScope: sourceScope, events: events)
    }

    private static func makeCapture(
        settledObservation: SettledObservation,
        sequence: Int,
        parentHash: String?,
        generation: ScreenGeneration,
        notificationBatch: AccessibilityNotificationBatch,
        evidence: Evidence,
        fallbackReason: AccessibilityObservationFallbackReason?
    ) -> AccessibilityTrace.Capture {
        let windows = settledObservation.semanticSignal.windows.enumerated().map { index, window in
            AccessibilityTrace.WindowContext(
                index: index,
                level: window.level,
                isKeyWindow: window.isKeyWindow
            )
        }
        return AccessibilityTrace.Capture(
            sequence: sequence,
            interface: evidence.interface,
            parentHash: parentHash,
            context: AccessibilityTrace.Context(
                firstResponder: evidence.firstResponder,
                screenId: settledObservation.observation.tree.id,
                observationGeneration: generation.rawValue,
                windowStack: windows
            ),
            transition: AccessibilityTrace.Transition(
                fallbackReason: fallbackReason,
                accessibilityNotifications: evidence.accessibilityNotifications,
                accessibilityNotificationGap: notificationBatch.gap
            )
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
