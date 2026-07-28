#if canImport(UIKit)
#if DEBUG
import Foundation

import AccessibilitySnapshotParser
import TheScore

extension TheVault {
    func admitNotifications(
        _ pendingEvents: [PendingAccessibilityNotificationEvent]
    ) -> [Observation.AdmittedNotification] {
        pendingEvents.sorted { $0.sequence < $1.sequence }.compactMap { event in
            guard event.kind.isAdmittedObservationKind else { return nil }
            return Observation.AdmittedNotification(
                sequence: event.sequence,
                kind: event.kind,
                text: event.notificationData.text ?? event.associatedElement.text,
                element: (
                    event.associatedElement.object
                        ?? event.notificationData.object
                )
                .flatMap(captureObject)
                .map(WireConversion.semantics)
            )
        }
    }

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
               let elementReference = notificationElementReference(for: heistId, in: referenceObservation, resolution: .identity) {
                return .element(elementReference)
            }
            if let parsedElement = captureObject(object),
               let elementReference = uniqueNotificationElementReference(
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

    private func notificationElementReference(
        for heistId: HeistId,
        in observation: InterfaceObservation,
        resolution: AccessibilityNotificationElementResolution
    ) -> AccessibilityNotificationElementReference? {
        let interface = WireConversion.toSemanticInterface(from: observation.tree)
        guard let record = interface.graph.elementsInTraversalOrder.first(where: {
            $0.observationIdentity == heistId.observationElementIdentity
        }) else { return nil }
        return AccessibilityNotificationElementReference(
            path: record.path,
            traversalIndex: record.traversalIndex,
            resolution: resolution
        )
    }

    private func uniqueNotificationElementReference(
        matching parsedElement: AccessibilityElement,
        in observation: InterfaceObservation,
        resolution: AccessibilityNotificationElementResolution
    ) -> AccessibilityNotificationElementReference? {
        let matches = observation.tree.elements.values.filter { $0.element == parsedElement }
        guard matches.count == 1, let match = matches.first else { return nil }
        return notificationElementReference(for: match.heistId, in: observation, resolution: resolution)
    }
}

private extension AccessibilityNotificationKind {
    var isAdmittedObservationKind: Bool {
        switch self {
        case .announcement, .screenChanged, .elementChanged:
            true
        case .unknown:
            false
        }
    }
}

private extension PendingAccessibilityNotificationPayload {
    var text: String? {
        guard case .string(let text) = self else { return nil }
        return text
    }

    var object: NSObject? {
        guard case .object(let identity) = self else { return nil }
        return identity.object as? NSObject
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
