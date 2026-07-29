#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

extension TheVault.State {
    /// Read projection of the Vault's current snapshot and navigation admission.
    ///
    /// The State owns the snapshot and interface tree. This projection carries
    /// neither a second tree nor capture identity.
    internal struct Current: Sendable, Equatable {
        internal let snapshot: Observation.Snapshot
        internal let scope: SemanticObservationScope
        internal let continuity: ScreenContinuity

        internal var screenHeading: String? {
            InterfaceSummary.screenName(for: snapshot.interface)
        }
        internal var summary: String { snapshot.summary }
    }
}

extension Observation {
    internal enum CaptureFailure: Error, Sendable, Equatable {
        case runtimeUnavailable
        case cancelled
        case sourceTreeUnavailable
        case hierarchyChangedDuringCapture

        internal var diagnostic: String {
            switch self {
            case .runtimeUnavailable:
                "the Button Heist runtime became unavailable during capture"
            case .cancelled:
                "the accessibility capture was cancelled"
            case .sourceTreeUnavailable:
                "the accessibility tree could not be read"
            case .hierarchyChangedDuringCapture:
                "the view hierarchy moved while the reading was taken"
            }
        }
    }

    /// One admitted observation's exact retained range and authored events.
    internal struct Publication: Sendable {
        internal let current: TheVault.State.Current
        internal let historyRange: Range<Int>
        internal let events: [Event]

        internal func events(after historyIndex: Int) -> ArraySlice<Event> {
            events.dropFirst(Swift.max(0, historyIndex - historyRange.lowerBound))
        }
    }

    internal struct Admission: Sendable {
        internal let tree: InterfaceTree
        internal let tripwireSignal: TheTripwire.TripwireSignal
        internal let discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy
        internal let lineage: ScreenLineage
        internal let scope: SemanticObservationScope
        internal let notificationAdmission: NotificationAdmission
        internal let keyboardVisible: Bool?
        internal let timestamp: Date
        /// Where the read tree's visible elements sat. Only the viewport has
        /// live geometry, so only the viewport is asked.
        internal let viewportFrames: [HeistId: CGRect]
        /// The device's touch-target size, captured eagerly because the
        /// comparison that uses it runs off the main actor.
        internal let geometryTolerance: CGFloat
    }

    internal enum NotificationAdmission: Sendable {
        case passive(NotificationSnapshot)
        case action(NotificationSnapshot)
    }

    internal struct NotificationSnapshot: Sendable {
        internal let admittedNotifications: [AdmittedNotification]
        internal let through: AccessibilityNotificationCursor
        internal let scopedScreenChangedThrough: UInt64

        internal func notifications(
            after cursor: AccessibilityNotificationCursor,
            scopedScreenChangedCursor: UInt64
        ) -> Notifications {
            let selectedNotifications = admittedNotifications.filter {
                $0.sequence > cursor.sequence
            }
            return Notifications(
                admittedNotifications: selectedNotifications,
                through: AccessibilityNotificationCursor(
                    sequence: max(cursor.sequence, through.sequence)
                ),
                scopedScreenChangedThrough: max(
                    scopedScreenChangedCursor,
                    scopedScreenChangedThrough
                )
            )
        }
    }

    internal struct Notifications: Sendable {
        internal let admittedNotifications: [AdmittedNotification]
        internal let through: AccessibilityNotificationCursor
        internal let scopedScreenChangedThrough: UInt64
    }

    internal struct AdmittedNotification: Sendable, Equatable {
        internal let sequence: UInt64
        internal let kind: AccessibilityNotificationKind
        internal let text: String?
        internal let element: HeistElement.Semantics?
    }
}

internal struct CommittableInterfaceObservation {
    internal let observation: InterfaceObservation
    internal let tripwireSignal: TheTripwire.TripwireSignal
    internal let discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy
    internal let lineage: ScreenLineage

    private init(
        observation: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface,
        lineage: ScreenLineage
    ) {
        self.observation = observation
        self.tripwireSignal = tripwireSignal
        self.discoveryCommitPolicy = discoveryCommitPolicy
        self.lineage = lineage
    }

    internal static func admitCaptured(
        _ observation: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface,
        lineage: ScreenLineage
    ) -> Self {
        Self(
            observation: observation,
            tripwireSignal: tripwireSignal,
            discoveryCommitPolicy: discoveryCommitPolicy,
            lineage: lineage
        )
    }

}

@MainActor
internal enum VisibleObservationOutcome: Equatable {
    case committed(TheVault.State.Current)
    case unavailable(Observation.CaptureFailure)
}

#endif // DEBUG
#endif // canImport(UIKit)
