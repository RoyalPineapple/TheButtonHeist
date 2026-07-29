#if canImport(UIKit)
#if DEBUG
import Foundation

enum AccessibilityNotificationProbe {
    enum Code: UInt32, CaseIterable, CustomStringConvertible {
        case elementUpdate = 1005
        case pageScrolled = 1009

        var description: String {
            switch self {
            case .elementUpdate:
                "elementUpdate"
            case .pageScrolled:
                "pageScrolled"
            }
        }
    }

    struct Payload: Equatable {
        let className: String
        let summary: String?

        init(_ payload: CapturedAccessibilityNotificationPayload) {
            self.className = payload.className
            self.summary = payload.summary
        }
    }

    struct Event: Equatable, CustomStringConvertible {
        let code: Code
        let notificationData: Payload
        let associatedElement: Payload

        var description: String {
            """
            accessibility notification probe code=\(code.rawValue)(\(code)) \
            notificationData.class=\(notificationData.className) \
            notificationData.payload=\(notificationData.summary ?? "nil") \
            associatedElement.class=\(associatedElement.className) \
            associatedElement.payload=\(associatedElement.summary ?? "nil")
            """
        }
    }

    static func observe(
        rawCode: UInt32,
        notificationData: CapturedAccessibilityNotificationPayload,
        associatedElement: CapturedAccessibilityNotificationPayload
    ) -> Event? {
        guard let code = Code(rawValue: rawCode) else { return nil }
        return Event(
            code: code,
            notificationData: Payload(notificationData),
            associatedElement: Payload(associatedElement)
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
