package enum ElementChangeNotification: String, Sendable, Equatable, Hashable {
    case layout
}

package enum AccessibilityNotificationKind: Sendable, Equatable, Hashable, CustomStringConvertible {
    case screenChanged
    case elementChanged(ElementChangeNotification)
    case elementUpdate
    case announcement
    case unknown(UInt32)

    package init(rawCode: UInt32) {
        self = switch rawCode {
        case 1000: .screenChanged
        case 1001: .elementChanged(.layout)
        case 1005: .elementUpdate
        case 1008: .announcement
        default: .unknown(rawCode)
        }
    }

    package var description: String {
        switch self {
        case .screenChanged:
            "screenChanged"
        case .elementChanged(let notification):
            "elementChanged(\(notification.rawValue))"
        case .elementUpdate:
            "elementUpdate"
        case .announcement:
            "announcement"
        case .unknown(let rawCode):
            "unknown(\(rawCode))"
        }
    }

    package var admitsAssociatedElement: Bool {
        switch self {
        case .elementChanged, .elementUpdate:
            true
        case .screenChanged, .announcement, .unknown:
            false
        }
    }
}

package struct AccessibilityNotificationGap: Sendable, Equatable {
    package let droppedThroughSequence: UInt64

    package init(droppedThroughSequence: UInt64) {
        self.droppedThroughSequence = droppedThroughSequence
    }
}
