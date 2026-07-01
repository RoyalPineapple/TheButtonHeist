#if canImport(UIKit)
#if DEBUG
import Foundation
import os.log

import AccessibilitySnapshotParser
import TheScore

private let accessibilityNotificationResolutionLogger = ButtonHeistLog.logger(.insideJob(.accessibility))

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
                        field: "notificationData",
                        in: screen
                    ),
                    associatedElement: resolveAccessibilityNotificationPayload(
                        event.associatedElement,
                        field: "associatedElement",
                        in: screen
                    )
                )
            }
        }
    }

    private func resolveAccessibilityNotificationPayload(
        _ payload: PendingAccessibilityNotificationPayload,
        field: String,
        in screen: Screen
    ) -> AccessibilityNotificationPayload {
        switch payload {
        case .none:
            return .none
        case .string(let value):
            return .string(value)
        case .object(let ref):
            guard let object = ref.object as? NSObject else {
                accessibilityNotificationResolutionLogger.info(
                    """
                    AX notification \(field, privacy: .public) unresolved: \
                    objectIdentity=\(String(describing: ref.objectIdentifier), privacy: .public) \
                    class=\(ref.className, privacy: .public) weak payload is gone
                    """
                )
                return unresolvedObjectPayload(ref)
            }
            if let heistId = currentLiveCapture.heistId(matching: object),
               let elementReference = traceElementReference(for: heistId, in: screen, resolution: .identity) {
                accessibilityNotificationResolutionLogger.info(
                    """
                    AX notification \(field, privacy: .public) resolved by object identity \
                    heistId=\(heistId.rawValue, privacy: .public) \
                    traversalIndex=\(elementReference.traversalIndex, privacy: .public)
                    """
                )
                return .element(elementReference)
            }
            if let parsedElement = burglar.parseObject(object),
               let elementReference = uniqueTraceElementReference(
                matching: parsedElement,
                in: screen,
                resolution: .singleElement
               ) {
                accessibilityNotificationResolutionLogger.info(
                    """
                    AX notification \(field, privacy: .public) resolved by single-element parse \
                    traversalIndex=\(elementReference.traversalIndex, privacy: .public)
                    """
                )
                return .element(elementReference)
            }
            accessibilityNotificationResolutionLogger.info(
                """
                AX notification \(field, privacy: .public) unresolved: \
                objectIdentity=\(String(describing: ref.objectIdentifier), privacy: .public) \
                class=\(ref.className, privacy: .public) identity and single-element parse did not match current hierarchy
                """
            )
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
