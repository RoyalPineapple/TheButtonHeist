#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

enum AccessibilityNotificationProbe {
    static func description(
        rawCode: UInt32,
        notificationData: CapturedAccessibilityNotificationPayload,
        associatedElement: CapturedAccessibilityNotificationPayload
    ) -> String? {
        let kind = AccessibilityNotificationKind(rawCode: rawCode)
        guard kind == .elementUpdate else { return nil }
        return """
        accessibility notification probe code=\(rawCode)(\(kind)) \
        notificationData.class=\(notificationData.className) \
        notificationData.payload=\(notificationData.summary ?? "nil") \
        associatedElement.class=\(associatedElement.className) \
        associatedElement.payload=\(associatedElement.summary ?? "nil")
        """
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
