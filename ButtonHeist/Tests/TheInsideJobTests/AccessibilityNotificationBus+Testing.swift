#if canImport(UIKit)
import Foundation
@testable import TheInsideJob

extension AccessibilityNotificationBus {
    func recordForTesting(
        code: UInt32,
        timestamp: Date = Date(),
        notificationData: CapturedAccessibilityNotificationPayload,
        associatedElement: CapturedAccessibilityNotificationPayload
    ) {
        record(
            sequence: latestSequence + 1,
            rawCode: code,
            timestamp: timestamp,
            notificationData: notificationData.pendingPayload,
            associatedElement: associatedElement.pendingPayload
        )
    }
}
#endif
