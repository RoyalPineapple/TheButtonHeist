import Foundation

/// A typed reason used only when the notification stream did not identify a
/// screen transition and the settled snapshots require a heuristic fallback.
public enum AccessibilityObservationFallbackReason: String, Codable, Sendable, Equatable, Hashable {
    case modalBoundaryChanged
    case selectedTabChanged
    case navigationMarkerChanged
    case primaryHeaderChanged
    case semanticIdentityDisjoint
    case rootShapeChanged
}

enum AccessibilityObservationChange: Equatable, Sendable {
    case elementChanged
    case screenChanged
}

enum AccessibilityObservationChangeReducer {
    static func reduce(
        between before: AccessibilityTrace.Capture,
        and after: AccessibilityTrace.Capture
    ) -> AccessibilityObservationChange {
        if let beforeGeneration = before.context.observationGeneration,
           let afterGeneration = after.context.observationGeneration,
           beforeGeneration != afterGeneration {
            return .screenChanged
        }
        let hasScreenChangedNotification = after.transition.accessibilityNotifications.contains { notification in
            switch notification.kind {
            case .screenChanged:
                true
            case .elementChanged, .announcement, .unknown:
                false
            }
        }
        if hasScreenChangedNotification {
            return .screenChanged
        }
        if after.transition.fallbackReason != nil {
            return .screenChanged
        }
        let hasUsableSameScreenNotification = after.transition.accessibilityNotifications.contains { notification in
            switch notification.kind {
            case .elementChanged, .announcement:
                true
            case .screenChanged, .unknown:
                false
            }
        }
        if hasUsableSameScreenNotification {
            return .elementChanged
        }
        return .elementChanged
    }
}
