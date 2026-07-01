#if canImport(UIKit)
#if DEBUG
import Foundation

import AccessibilitySnapshotParser
import TheScore

extension TheStash {
    func resolveAccessibilityNotificationEvidence(
        _ pendingEvents: [PendingAccessibilityNotificationEvent],
        in screen: Screen
    ) -> [AccessibilityNotificationEvidence] {
        pendingEvents.map { event in
            autoreleasepool {
                AccessibilityNotificationEvidence(
                    sequence: event.sequence,
                    code: event.code,
                    name: event.name,
                    timestamp: event.timestamp,
                    notificationData: resolveAccessibilityNotificationPayload(
                        event.notificationData,
                        in: screen
                    ),
                    associatedElement: resolveAccessibilityNotificationPayload(
                        event.associatedElement,
                        in: screen
                    )
                )
            }
        }
    }

    private func resolveAccessibilityNotificationPayload(
        _ payload: PendingAccessibilityNotificationPayload,
        in screen: Screen
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
            if let heistId = currentLiveCapture.heistId(matching: object),
               let elementReference = traceElementReference(for: heistId, in: screen, resolution: .identity) {
                return .element(elementReference)
            }
            if let parsedElement = burglar.parseObject(object),
               let elementReference = uniqueTraceElementReference(
                matching: parsedElement,
                in: screen,
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
        in screen: Screen,
        resolution: AccessibilityNotificationElementResolution
    ) -> AccessibilityNotificationElementReference? {
        for (index, element) in screen.orderedElements.enumerated() where element.heistId == heistId {
            return AccessibilityNotificationElementReference(
                path: TreePath([index]),
                traversalIndex: index,
                resolution: resolution
            )
        }
        return nil
    }

    private func uniqueTraceElementReference(
        matching parsedElement: AccessibilityElement,
        in screen: Screen,
        resolution: AccessibilityNotificationElementResolution
    ) -> AccessibilityNotificationElementReference? {
        var match: AccessibilityNotificationElementReference?
        for (index, element) in screen.orderedElements.enumerated() where element.element == parsedElement {
            guard match == nil else { return nil }
            match = AccessibilityNotificationElementReference(
                path: TreePath([index]),
                traversalIndex: index,
                resolution: resolution
            )
        }
        return match
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
