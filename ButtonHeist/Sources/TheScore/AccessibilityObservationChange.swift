import Foundation

/// A typed reason used only when the notification stream did not identify a
/// screen transition and the settled snapshots require a heuristic fallback.
public enum AccessibilityObservationFallbackReason: String, Codable, Sendable, Equatable, Hashable {
    case modalBoundaryChanged
    case selectedTabChanged
    case navigationMarkerChanged
    case primaryHeaderChanged
    case rootShapeChanged
    case screenIdentifierChanged
}

enum AccessibilityObservationChangeSource: Equatable, Sendable {
    case screenChangedNotification
    case elementChangedNotification
    case settledSnapshot
    case fallback(AccessibilityObservationFallbackReason)
}

enum AccessibilityObservationChange: Equatable, Sendable {
    case unchanged
    case elementChanged(source: AccessibilityObservationChangeSource)
    case screenChanged(source: AccessibilityObservationChangeSource)

    var isScreenChange: Bool {
        if case .screenChanged = self { return true }
        return false
    }

    var isChange: Bool {
        if case .unchanged = self { return false }
        return true
    }

    var isElementNotification: Bool {
        guard case .elementChanged(source: .elementChangedNotification) = self else { return false }
        return true
    }
}

enum AccessibilityObservationChangeReducer {
    static func reduce(
        before: AccessibilityTrace.Capture,
        after: AccessibilityTrace.Capture,
        projection: AccessibilityTrace.DeltaProjection
    ) -> AccessibilityObservationChange {
        let notificationKinds = after.transition.accessibilityNotifications.map(\.kind)
        if notificationKinds.contains(.screenChanged) {
            return .screenChanged(source: .screenChangedNotification)
        }
        if let fallbackReason = after.transition.fallbackReason {
            return .screenChanged(source: .fallback(fallbackReason))
        }
        if notificationKinds.contains(.elementChanged) {
            return .elementChanged(source: .elementChangedNotification)
        }
        if before.context.screenId != after.context.screenId {
            return .screenChanged(source: .fallback(.screenIdentifierChanged))
        }
        if !projection.includesGeometry, before.hash == after.hash {
            return .unchanged
        }
        return .elementChanged(source: .settledSnapshot)
    }
}
