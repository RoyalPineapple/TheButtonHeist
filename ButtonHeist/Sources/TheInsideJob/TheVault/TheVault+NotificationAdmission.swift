#if canImport(UIKit)
#if DEBUG
import UIKit

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
                text: event.notificationData.text,
                element: event.notificationElement.flatMap(captureNotificationSemantics)
            )
        }
    }

    private func captureNotificationSemantics(
        _ object: NSObject
    ) -> HeistElement.Semantics? {
        let wasAccessibilityElement = object.isAccessibilityElement
        let accessibilityFrame = object.accessibilityFrame
        let requiresCaptureFrame = accessibilityFrame.width < 1
            && accessibilityFrame.height < 1
        if !wasAccessibilityElement {
            object.isAccessibilityElement = true
        }
        if requiresCaptureFrame {
            object.accessibilityFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        defer {
            if requiresCaptureFrame {
                object.accessibilityFrame = accessibilityFrame
            }
            if !wasAccessibilityElement {
                object.isAccessibilityElement = false
            }
        }
        return captureObject(object).map(WireConversion.semantics)
    }
}

private extension PendingAccessibilityNotificationEvent {
    var notificationElement: NSObject? {
        if let argument = notificationData.object {
            return argument
        }
        guard kind.admitsAssociatedElement else { return nil }
        return associatedElement.object
    }
}

private extension AccessibilityNotificationKind {
    var isAdmittedObservationKind: Bool {
        switch self {
        case .announcement, .screenChanged, .elementChanged, .elementUpdate:
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
