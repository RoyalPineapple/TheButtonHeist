import Foundation
import ThePlans

/// Canonical values produced while observing an accessibility interface.
public enum Observation {}

public extension Observation {
    /// Immutable semantic accessibility state admitted from one parse.
    struct Snapshot: Codable, Sendable, Equatable {
        public let interface: Interface
        public let context: Context

        public init(
            interface: Interface,
            context: Context
        ) {
            self.interface = interface
            self.context = context
        }

        public static func empty(timestamp: Date) -> Snapshot {
            Snapshot(
                interface: Interface(timestamp: timestamp, tree: []),
                context: .empty
            )
        }
    }

    /// Semantic context that affects the meaning of a parsed interface.
    struct Context: Codable, Sendable, Equatable {
        public static let empty = Context()

        public let firstResponder: AccessibilityTarget?
        public let keyboardVisible: Bool?
        public let screenId: String?
        public let windowStack: [WindowContext]

        public init(
            firstResponder: AccessibilityTarget? = nil,
            keyboardVisible: Bool? = nil,
            screenId: String? = nil,
            windowStack: [WindowContext] = []
        ) {
            self.firstResponder = firstResponder
            self.keyboardVisible = keyboardVisible
            self.screenId = screenId
            self.windowStack = windowStack
        }
    }

    struct WindowContext: Codable, Sendable, Equatable {
        public let index: Int
        public let level: Double
        public let isKeyWindow: Bool

        public init(index: Int, level: Double, isKeyWindow: Bool) {
            self.index = index
            self.level = level
            self.isKeyWindow = isKeyWindow
        }
    }

    /// Normalized content carried by one accessibility notification.
    ///
    /// Notification kind is consumed before this value is published. An
    /// attached element is parsed independently and carries current semantics
    /// only; it has no graph identity or geometry.
    struct Notification: Codable, Sendable, Equatable {
        public let text: String?
        public let element: HeistElement.Semantics?

        public init?(text: String?, element: HeistElement.Semantics?) {
            guard text != nil || element != nil else { return nil }
            self.text = text
            self.element = element
        }
    }

    /// One semantic event admitted by the Vault.
    enum Event: Codable, Sendable, Equatable {
        case elementsChanged(Snapshot)
        case screenChanged(ScreenFacts)
        case notification(Notification)
        case noChange

        public var snapshot: Snapshot? {
            switch self {
            case .elementsChanged(let snapshot):
                snapshot
            case .screenChanged, .notification, .noChange:
                nil
            }
        }
    }

    /// Immutable observation facts supporting one action or wait result.
    struct Evidence: Codable, Sendable, Equatable {
        public enum Completeness: String, Codable, Sendable, Equatable {
            case complete
            case incomplete
        }

        public let baseline: Snapshot?
        public let current: Snapshot?
        public let events: [Event]
        public let completeness: Completeness

        public init(
            baseline: Snapshot?,
            current: Snapshot?,
            events: [Event],
            completeness: Completeness
        ) {
            self.baseline = baseline
            self.current = current
            self.events = events
            self.completeness = completeness
        }

        public var notificationTexts: [String] {
            events.compactMap { event in
                guard case .notification(let notification) = event else {
                    return nil
                }
                return notification.text
            }
        }
    }
}
