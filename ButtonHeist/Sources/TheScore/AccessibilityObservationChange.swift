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
    case observationGeneration
    case settledSnapshot
    case fallback(AccessibilityObservationFallbackReason)
}

enum AccessibilityObservationChange: Equatable, Sendable {
    case elementChanged(source: AccessibilityObservationChangeSource)
    case screenChanged(source: AccessibilityObservationChangeSource)
}

enum AccessibilityObservationChangeReducer {
    static func reduce(
        before: AccessibilityTrace.Capture,
        after: AccessibilityTrace.Capture
    ) -> AccessibilityObservationChange {
        let notificationKinds = after.transition.accessibilityNotifications.map(\.kind)
        if notificationKinds.contains(.screenChanged) {
            return .screenChanged(source: .screenChangedNotification)
        }
        if let beforeGeneration = before.context.observationGeneration,
           let afterGeneration = after.context.observationGeneration,
           beforeGeneration != afterGeneration {
            return .screenChanged(source: .observationGeneration)
        }
        if let fallbackReason = after.transition.fallbackReason {
            return .screenChanged(source: .fallback(fallbackReason))
        }
        if before.context.screenId != after.context.screenId {
            return .screenChanged(source: .fallback(.screenIdentifierChanged))
        }
        if notificationKinds.contains(where: \.isElementChangeEvidence) {
            return .elementChanged(source: .settledSnapshot)
        }
        if !after.transition.transient.isEmpty {
            return .elementChanged(source: .settledSnapshot)
        }
        return .elementChanged(source: .settledSnapshot)
    }
}
