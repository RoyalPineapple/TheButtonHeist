#if canImport(UIKit)
#if DEBUG
import Foundation

import AccessibilitySnapshotParser
import TheScore

extension TheStash {
    func resolveAccessibilityNotificationEvidence(
        _ pendingEvents: [PendingAccessibilityNotificationEvent],
        in screen: InterfaceObservation
    ) -> [AccessibilityNotificationEvidence] {
        resolveAccessibilityNotificationEvidence(
            pendingEvents,
            identityScreen: screen,
            referenceScreen: screen
        )
    }

    func resolveAccessibilityNotificationEvidence(
        _ pendingEvents: [PendingAccessibilityNotificationEvent],
        identityScreen: InterfaceObservation,
        referenceScreen: InterfaceObservation
    ) -> [AccessibilityNotificationEvidence] {
        pendingEvents.map { event in
            autoreleasepool {
                AccessibilityNotificationEvidence(
                    sequence: event.sequence,
                    kind: event.kind,
                    timestamp: event.timestamp,
                    notificationData: resolveAccessibilityNotificationPayload(
                        event.notificationData,
                        identityScreen: identityScreen,
                        referenceScreen: referenceScreen
                    ),
                    associatedElement: resolveAccessibilityNotificationPayload(
                        event.associatedElement,
                        identityScreen: identityScreen,
                        referenceScreen: referenceScreen
                    )
                )
            }
        }
    }

    private func resolveAccessibilityNotificationPayload(
        _ payload: PendingAccessibilityNotificationPayload,
        identityScreen: InterfaceObservation,
        referenceScreen: InterfaceObservation
    ) -> AccessibilityNotificationPayload {
        switch payload {
        case .none:
            return .none
        case .string(let value):
            return .string(value)
        case .object(let ref):
            guard let object = ref.object as? NSObject else {
                return unresolvedObjectPayload(ref)
            }
            if let heistId = identityScreen.liveCapture.heistId(matching: object),
               let elementReference = traceElementReference(for: heistId, in: referenceScreen, resolution: .identity) {
                return .element(elementReference)
            }
            if let parsedElement = burglar.parseObject(object),
               let elementReference = uniqueTraceElementReference(
                matching: parsedElement,
                in: referenceScreen,
                resolution: .singleElement
               ) {
                return .element(elementReference)
            }
            return unresolvedObjectPayload(ref)
        }
    }

    private func unresolvedObjectPayload(
        _ ref: AccessibilityNotificationObjectIdentity
    ) -> AccessibilityNotificationPayload {
        .unresolvedObject(AccessibilityNotificationObjectPayload(
            className: ref.className,
            summary: ref.summary
        ))
    }

    private func traceElementReference(
        for heistId: HeistId,
        in screen: InterfaceObservation,
        resolution: AccessibilityNotificationElementResolution
    ) -> AccessibilityNotificationElementReference? {
        WireConversion.semanticInterfaceProjection(from: screen.tree)
            .accessibilityNotificationElementReference(for: heistId, resolution: resolution)
    }

    private func uniqueTraceElementReference(
        matching parsedElement: AccessibilityElement,
        in screen: InterfaceObservation,
        resolution: AccessibilityNotificationElementResolution
    ) -> AccessibilityNotificationElementReference? {
        WireConversion.semanticInterfaceProjection(from: screen.tree)
            .accessibilityNotificationElementReference(matching: parsedElement, resolution: resolution)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
