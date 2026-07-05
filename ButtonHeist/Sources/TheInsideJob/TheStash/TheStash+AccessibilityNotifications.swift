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
        resolveAccessibilityNotificationEvidence(
            pendingEvents,
            identityScreen: screen,
            referenceScreen: screen
        )
    }

    func resolveAccessibilityNotificationEvidence(
        _ pendingEvents: [PendingAccessibilityNotificationEvent],
        identityScreen: Screen,
        referenceScreen: Screen
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
        identityScreen: Screen,
        referenceScreen: Screen
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
