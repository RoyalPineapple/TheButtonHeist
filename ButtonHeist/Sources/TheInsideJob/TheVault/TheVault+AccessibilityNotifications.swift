#if canImport(UIKit)
#if DEBUG
import Foundation

import AccessibilitySnapshotParser
import TheScore

extension TheVault {
    func resolveAccessibilityNotificationEvidence(
        _ pendingEvents: [PendingAccessibilityNotificationEvent],
        in observation: InterfaceObservation
    ) -> [AccessibilityNotificationEvidence] {
        resolveAccessibilityNotificationEvidence(
            pendingEvents,
            identityObservation: observation,
            referenceObservation: observation
        )
    }

    func resolveAccessibilityNotificationEvidence(
        _ pendingEvents: [PendingAccessibilityNotificationEvent],
        identityObservation: InterfaceObservation,
        referenceObservation: InterfaceObservation
    ) -> [AccessibilityNotificationEvidence] {
        pendingEvents.map { event in
            autoreleasepool {
                AccessibilityNotificationEvidence(
                    sequence: event.sequence,
                    kind: event.kind,
                    timestamp: event.timestamp,
                    notificationData: resolveAccessibilityNotificationPayload(
                        event.notificationData,
                        identityObservation: identityObservation,
                        referenceObservation: referenceObservation
                    ),
                    associatedElement: resolveAccessibilityNotificationPayload(
                        event.associatedElement,
                        identityObservation: identityObservation,
                        referenceObservation: referenceObservation
                    )
                )
            }
        }
    }

    private func resolveAccessibilityNotificationPayload(
        _ payload: PendingAccessibilityNotificationPayload,
        identityObservation: InterfaceObservation,
        referenceObservation: InterfaceObservation
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
            if let heistId = identityObservation.liveCapture.heistId(matching: object),
               let elementReference = traceElementReference(for: heistId, in: referenceObservation, resolution: .identity) {
                return .element(elementReference)
            }
            if let parsedElement = captureObject(object),
               let elementReference = uniqueTraceElementReference(
                matching: parsedElement,
                in: referenceObservation,
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
        in observation: InterfaceObservation,
        resolution: AccessibilityNotificationElementResolution
    ) -> AccessibilityNotificationElementReference? {
        let interface = WireConversion.toSemanticInterface(from: observation.tree)
        guard let record = interface.graph.elementsInTraversalOrder.first(where: {
            $0.traceIdentity == heistId.traceElementIdentity
        }) else { return nil }
        return AccessibilityNotificationElementReference(
            path: record.path,
            traversalIndex: record.traversalIndex,
            resolution: resolution
        )
    }

    private func uniqueTraceElementReference(
        matching parsedElement: AccessibilityElement,
        in observation: InterfaceObservation,
        resolution: AccessibilityNotificationElementResolution
    ) -> AccessibilityNotificationElementReference? {
        let matches = observation.tree.elements.values.filter { $0.element == parsedElement }
        guard matches.count == 1, let match = matches.first else { return nil }
        return traceElementReference(for: match.heistId, in: observation, resolution: resolution)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
