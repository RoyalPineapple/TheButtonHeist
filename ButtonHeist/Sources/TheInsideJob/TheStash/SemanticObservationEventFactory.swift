#if canImport(UIKit)
#if DEBUG

import TheScore

enum SemanticObservationEventFactory {
    @MainActor
    static func makeEvent(
        observation: SettledSemanticObservation,
        previous: SettledSemanticObservationEvent?,
        generation: ObservationGeneration,
        notificationBatch: AccessibilityNotificationBatch,
        stash: TheStash,
        notificationIdentityScreen: InterfaceObservation? = nil,
        fallbackReason: AccessibilityObservationFallbackReason? = nil
    ) -> SettledSemanticObservationEvent {
        let previousCapture = previous?.trace.captures.last
        let currentCapture = semanticTraceCapture(
            for: observation,
            sequence: previousCapture == nil ? 1 : 2,
            parentHash: previousCapture?.hash,
            generation: generation,
            stash: stash,
            notificationBatch: notificationBatch,
            notificationIdentityScreen: notificationIdentityScreen,
            fallbackReason: fallbackReason
        )
        let trace = if let previousCapture {
            AccessibilityTrace(captures: [previousCapture, currentCapture])
        } else {
            AccessibilityTrace(capture: currentCapture)
        }
        return SettledSemanticObservationEvent(
            generation: generation,
            sequence: observation.sequence,
            scope: observation.scope,
            observation: observation,
            previous: previous?.observation,
            previousCursor: previous?.cursor,
            notificationSequence: notificationBatch.through.sequence,
            trace: trace
        )
    }

    @MainActor
    private static func semanticTraceCapture(
        for observation: SettledSemanticObservation,
        sequence: Int,
        parentHash: String?,
        generation: ObservationGeneration,
        stash: TheStash,
        notificationBatch: AccessibilityNotificationBatch,
        notificationIdentityScreen: InterfaceObservation?,
        fallbackReason: AccessibilityObservationFallbackReason?
    ) -> AccessibilityTrace.Capture {
        let screen = switch observation.scope {
        case .visible:
            observation.screen.viewportOnly
        case .discovery:
            observation.screen
        }
        let interface = stash.semanticInterfaceWithHash(for: screen).interface
        let accessibilityNotifications = stash.resolveAccessibilityNotificationEvidence(
            notificationBatch.events,
            identityScreen: notificationIdentityScreen ?? screen,
            referenceScreen: screen
        )
        let windows = observation.semanticSignal.windows.enumerated().map { index, window in
            AccessibilityTrace.WindowContext(
                index: index,
                level: window.level,
                isKeyWindow: window.isKeyWindow
            )
        }
        return AccessibilityTrace.Capture(
            sequence: sequence,
            interface: interface,
            parentHash: parentHash,
            context: AccessibilityTrace.Context(
                firstResponder: stash.firstResponderTarget(in: screen.tree),
                screenId: screen.id,
                observationGeneration: generation.rawValue,
                windowStack: windows
            ),
            transition: AccessibilityTrace.Transition(
                fallbackReason: fallbackReason,
                accessibilityNotifications: accessibilityNotifications,
                accessibilityNotificationGap: notificationBatch.gap
            )
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
