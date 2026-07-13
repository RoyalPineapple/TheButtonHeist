#if canImport(UIKit)
#if DEBUG
import TheScore

/// Reduces settled source observations into events for every fulfilled scope.
internal struct SemanticObservationFulfillmentState {
    internal typealias EventsByFulfilledScope = [SemanticObservationScope: SettledSemanticObservationEvent]

    internal struct Publication {
        internal let events: EventsByFulfilledScope
        internal let generation: ObservationGeneration
        internal let startsNewGeneration: Bool
    }

    private struct CurrentFulfillment {
        fileprivate let sourceEvent: SettledSemanticObservationEvent
        fileprivate var eventsByFulfilledScope: EventsByFulfilledScope
    }

    private enum State {
        case empty
        case observing(CurrentFulfillment)
        case invalidated(CurrentFulfillment?)
    }

    private var state: State = .empty

    internal var latestSourceEvent: SettledSemanticObservationEvent? {
        currentFulfillment?.sourceEvent
    }

    internal var latestSettledObservationInvalidated: Bool {
        switch state {
        case .empty, .invalidated:
            true
        case .observing:
            false
        }
    }

    internal var latestObservation: SettledSemanticObservation? {
        latestSourceEvent?.observation
    }

    private var currentFulfillment: CurrentFulfillment? {
        switch state {
        case .empty:
            return nil
        case .observing(let fulfillment):
            return fulfillment
        case .invalidated(let fulfillment):
            return fulfillment
        }
    }

    internal func previousEvent(for scope: SemanticObservationScope) -> SettledSemanticObservationEvent? {
        currentFulfillment?.eventsByFulfilledScope[scope] ?? currentFulfillment?.sourceEvent
    }

    internal mutating func clear() {
        state = .empty
    }

    internal mutating func invalidate() {
        switch state {
        case .empty:
            state = .invalidated(nil)
        case .observing(let fulfillment):
            state = .invalidated(fulfillment)
        case .invalidated(.some(let fulfillment)):
            state = .invalidated(fulfillment)
        case .invalidated(.none):
            break
        }
    }

    @MainActor
    internal mutating func publish(
        sourceScope: SemanticObservationScope,
        sourceClassification: ScreenClassifier.Classification,
        sequence: SettledObservationSequence,
        generation: ObservationGeneration,
        notificationBatch: AccessibilityNotificationBatch,
        screen: InterfaceObservation,
        semanticSignal: TheTripwire.SemanticSignal,
        stash: TheStash,
        notificationIdentityScreen: InterfaceObservation? = nil
    ) -> Publication {
        let pendingAccessibilityNotifications = notificationBatch.events
        let notificationKinds = pendingAccessibilityNotifications.map(\.kind)
        let previousEvents = currentFulfillment?.eventsByFulfilledScope ?? [:]
        let sourcePreviousEvent = previousEvent(for: sourceScope)
        let sourceObservation = SettledSemanticObservation(
            sequence: sequence,
            scope: sourceScope,
            screen: screen.semanticObservationProjection(for: sourceScope),
            semanticSignal: semanticSignal
        )
        let startsNewGeneration = sourceClassification.isScreenReplacement
        let eventGeneration = startsNewGeneration ? generation.advanced() : generation
        var currentEvents = startsNewGeneration ? [:] : previousEvents
        var events: EventsByFulfilledScope = [:]
        for fulfilledScope in sourceScope.fulfilledScopes {
            let previousEvent = previousEvents[fulfilledScope]
                ?? (fulfilledScope == sourceScope ? sourcePreviousEvent : nil)
            let observation = fulfilledScope == sourceScope
                ? sourceObservation
                : SettledSemanticObservation(
                    sequence: sequence,
                    scope: fulfilledScope,
                    screen: screen.semanticObservationProjection(for: fulfilledScope),
                    semanticSignal: semanticSignal
                )
            let classification = fulfilledScope == sourceScope
                ? sourceClassification
                : ScreenClassifier.classify(
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
            let event = SemanticObservationEventFactory.makeEvent(
                observation: observation,
                previous: previousEvent,
                generation: eventGeneration,
                notificationBatch: notificationBatch,
                stash: stash,
                notificationIdentityScreen: notificationIdentityScreen,
                fallbackReason: fallbackReason
            )
            currentEvents[fulfilledScope] = event
            events[fulfilledScope] = event
        }
        guard let publishedSourceEvent = events[sourceScope] else {
            preconditionFailure("Semantic observation scope did not fulfill itself")
        }
        state = .observing(CurrentFulfillment(
            sourceEvent: publishedSourceEvent,
            eventsByFulfilledScope: currentEvents
        ))
        return Publication(
            events: events,
            generation: eventGeneration,
            startsNewGeneration: startsNewGeneration
        )
    }

    internal func cleanEvent(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) -> SettledSemanticObservationEvent? {
        guard case .observing(let fulfillment) = state,
              let latest = fulfillment.eventsByFulfilledScope[scope],
              latest.sequence > (sequence ?? 0)
        else {
            return nil
        }
        return latest
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
