#if canImport(UIKit)
#if DEBUG

import TheScore

enum SemanticObservationEventFactory {
    @MainActor
    static func makeEvent(
        observation: SettledSemanticObservation,
        previous: SettledSemanticObservationEvent?,
        stash: TheStash,
        pendingAccessibilityNotifications: [PendingAccessibilityNotificationEvent] = []
    ) -> SettledSemanticObservationEvent {
        let previousCapture = previous?.trace.captures.last
        let currentCapture = semanticTraceCapture(
            for: observation,
            sequence: previousCapture == nil ? 1 : 2,
            parentHash: previousCapture?.hash,
            stash: stash,
            pendingAccessibilityNotifications: pendingAccessibilityNotifications
        )
        let trace = if let previousCapture {
            AccessibilityTrace(captures: [previousCapture, currentCapture])
        } else {
            AccessibilityTrace(capture: currentCapture)
        }
        return SettledSemanticObservationEvent(
            sequence: observation.sequence,
            scope: observation.scope,
            observation: observation,
            previous: previous?.observation,
            trace: trace,
            delta: trace.endpointDelta
        )
    }

    @MainActor
    private static func semanticTraceCapture(
        for observation: SettledSemanticObservation,
        sequence: Int,
        parentHash: String?,
        stash: TheStash,
        pendingAccessibilityNotifications: [PendingAccessibilityNotificationEvent]
    ) -> AccessibilityTrace.Capture {
        let screen = switch observation.scope {
        case .visible:
            observation.screen.visibleOnly
        case .discovery:
            observation.screen
        }
        let interface = stash.semanticInterfaceWithHash(for: screen).interface
        let accessibilityNotifications = stash.resolveAccessibilityNotificationEvidence(
            pendingAccessibilityNotifications,
            in: screen
        )
        let windows = observation.tripwireSignal.windowStack.windows.enumerated().map { index, window in
            AccessibilityTrace.WindowContext(
                index: index,
                level: Double(window.level),
                isKeyWindow: window.isKeyWindow
            )
        }
        return AccessibilityTrace.Capture(
            sequence: sequence,
            interface: interface,
            parentHash: parentHash,
            context: AccessibilityTrace.Context(
                screenId: screen.id,
                windowStack: windows
            ),
            transition: AccessibilityTrace.Transition(
                accessibilityNotifications: accessibilityNotifications
            )
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
