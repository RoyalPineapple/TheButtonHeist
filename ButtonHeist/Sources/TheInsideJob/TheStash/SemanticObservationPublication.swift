#if canImport(UIKit)
#if DEBUG
import TheScore

internal enum SemanticObservationGenerationClassifier {
    @MainActor
    internal static func classify(
        currentGeneration: ObservationGeneration,
        previousInScope: SettledSemanticObservationEvent?,
        latestSource: SettledSemanticObservationEvent?,
        candidate: InterfaceObservation,
        scope: SemanticObservationScope,
        notifications: [AccessibilityNotificationKind]
    ) -> ScreenClassifier.Classification {
        if notifications.contains(where: {
            if case .screenChanged = $0 { return true }
            return false
        }) {
            return .screenChangedNotification
        }
        if let previousInScope {
            precondition(
                previousInScope.generation.rawValue <= currentGeneration.rawValue,
                "scoped observation generation cannot lead the stream"
            )
            if previousInScope.generation == currentGeneration {
                return ScreenClassifier.classify(
                    before: ScreenClassifier.snapshot(
                        of: previousInScope.observation.screen
                            .semanticObservationProjection(for: scope).tree
                    ),
                    after: ScreenClassifier.snapshot(of: candidate.tree),
                    notifications: notifications
                )
            }
        }

        let previousSnapshot = latestSource.map { event in
            ScreenClassifier.snapshot(
                of: event.observation.screen
                    .semanticObservationProjection(for: scope).tree
            )
        }
        return ScreenClassifier.classify(
            before: previousSnapshot,
            after: ScreenClassifier.snapshot(of: candidate.tree),
            notifications: notifications
        )
    }
}

/// Builds one publication from the log's latest per-scope events.
internal struct SemanticObservationPublication {
    internal typealias EventsByScope = [SemanticObservationScope: SettledSemanticObservationEvent]

    internal struct Context {
        internal let generationClassification: ScreenClassifier.Classification
        internal let generation: ObservationGeneration
        internal let previousEvents: EventsByScope
    }

    internal let sourceScope: SemanticObservationScope
    internal let events: EventsByScope

    internal var sourceEvent: SettledSemanticObservationEvent {
        guard let event = events[sourceScope] else {
            preconditionFailure("Semantic observation publication has no source event")
        }
        return event
    }

    internal var generation: ObservationGeneration {
        sourceEvent.generation
    }

    internal init(
        sourceScope: SemanticObservationScope,
        events: EventsByScope
    ) {
        precondition(events[sourceScope] != nil, "Semantic observation scope did not fulfill itself")
        self.sourceScope = sourceScope
        self.events = events
    }

    @MainActor
    internal static func make(
        sourceScope: SemanticObservationScope,
        sequence: SettledObservationSequence,
        notificationBatch: AccessibilityNotificationBatch,
        screen: InterfaceObservation,
        semanticSignal: TheTripwire.SemanticSignal,
        context: Context,
        stash: TheStash,
        notificationIdentityScreen: InterfaceObservation? = nil
    ) -> SemanticObservationPublication {
        let notificationKinds = notificationBatch.events.map(\.kind)
        let eventGeneration = context.generationClassification.isScreenReplacement
            ? context.generation.advanced()
            : context.generation
        var events: EventsByScope = [:]
        for fulfilledScope in sourceScope.fulfilledScopes {
            let previousEvent = context.previousEvents[fulfilledScope]
            let observation = SettledSemanticObservation(
                sequence: sequence,
                scope: fulfilledScope,
                screen: screen.semanticObservationProjection(for: fulfilledScope),
                semanticSignal: semanticSignal
            )
            let classification = ScreenClassifier.classify(
                before: previousEvent.map {
                    ScreenClassifier.snapshot(of: $0.observation.screen.tree)
                },
                after: ScreenClassifier.snapshot(of: observation.screen.tree),
                notifications: notificationKinds
            )
            let fallbackReason = classification.fallbackReason
            if let fallbackReason {
                AccessibilityObservationFallbackLog.record(
                    fallbackReason,
                    source: .settledObservation
                )
            }
            events[fulfilledScope] = SemanticObservationEventFactory.makeEvent(
                observation: observation,
                previous: previousEvent,
                generation: eventGeneration,
                notificationBatch: notificationBatch,
                stash: stash,
                notificationIdentityScreen: notificationIdentityScreen,
                fallbackReason: fallbackReason
            )
        }
        return SemanticObservationPublication(sourceScope: sourceScope, events: events)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
