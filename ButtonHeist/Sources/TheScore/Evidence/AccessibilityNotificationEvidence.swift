import Foundation
import ThePlans

public enum ElementChangeNotification: String, Codable, Sendable, Equatable, Hashable {
    case layout
    case value
}

public enum AccessibilityNotificationKind: Codable, Sendable, Equatable, Hashable {
    case screenChanged
    case elementChanged(ElementChangeNotification)
    case announcement
    case unknown(UInt32)

    public init(rawCode: UInt32) {
        self = switch rawCode {
        case 1000: .screenChanged
        case 1001: .elementChanged(.layout)
        case 1005: .elementChanged(.value)
        case 1008: .announcement
        default: .unknown(rawCode)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case notification
        case rawCode
    }

    private enum Kind: String, Codable {
        case screenChanged
        case elementChanged
        case announcement
        case unknown
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "accessibility notification kind")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        let typeName = "\(kind.rawValue) accessibility notification kind"
        switch kind {
        case .screenChanged:
            try container.rejectIncompatibleFields(allowing: [.type], typeName: typeName)
            self = .screenChanged
        case .elementChanged:
            try container.rejectIncompatibleFields(allowing: [.type, .notification], typeName: typeName)
            self = .elementChanged(try container.decode(ElementChangeNotification.self, forKey: .notification))
        case .announcement:
            try container.rejectIncompatibleFields(allowing: [.type], typeName: typeName)
            self = .announcement
        case .unknown:
            try container.rejectIncompatibleFields(allowing: [.type, .rawCode], typeName: typeName)
            self = .unknown(try container.decode(UInt32.self, forKey: .rawCode))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .screenChanged:
            try container.encode(Kind.screenChanged, forKey: .type)
        case .elementChanged(let notification):
            try container.encode(Kind.elementChanged, forKey: .type)
            try container.encode(notification, forKey: .notification)
        case .announcement:
            try container.encode(Kind.announcement, forKey: .type)
        case .unknown(let rawCode):
            try container.encode(Kind.unknown, forKey: .type)
            try container.encode(rawCode, forKey: .rawCode)
        }
    }

}

extension AccessibilityNotificationKind: CustomStringConvertible {
    public var description: String {
        switch self {
        case .screenChanged:
            return "screenChanged"
        case .elementChanged(let notification):
            return "elementChanged(\(notification.rawValue))"
        case .announcement:
            return "announcement"
        case .unknown(let rawCode):
            return "unknown(\(rawCode))"
        }
    }
}

/// Ordered accessibility-notification evidence observed while moving between
/// two accessibility snapshots.
///
/// Notifications are transition-edge product data: snapshots remain the state
/// truth, while this stream explains what UIKit/SwiftUI announced between
/// those states. Payload strings and unresolved-object summaries may contain
/// app content and are intentionally Codable so results can preserve the same
/// evidence an accessibility user or runtime notification exposed. Do not mirror
/// these payloads into logs.
public struct AccessibilityNotificationEvidence: Codable, Sendable, Equatable, Hashable {
    public let sequence: UInt64
    public let kind: AccessibilityNotificationKind
    public let timestamp: Date
    public let notificationData: AccessibilityNotificationPayload
    public let associatedElement: AccessibilityNotificationPayload

    public init(
        sequence: UInt64,
        kind: AccessibilityNotificationKind,
        timestamp: Date,
        notificationData: AccessibilityNotificationPayload,
        associatedElement: AccessibilityNotificationPayload
    ) {
        self.sequence = sequence
        self.kind = kind
        self.timestamp = timestamp
        self.notificationData = notificationData
        self.associatedElement = associatedElement
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sequence
        case kind
        case timestamp
        case notificationData
        case associatedElement
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "accessibility notification evidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sequence: try container.decode(UInt64.self, forKey: .sequence),
            kind: try container.decode(AccessibilityNotificationKind.self, forKey: .kind),
            timestamp: try container.decode(Date.self, forKey: .timestamp),
            notificationData: try container.decode(
                AccessibilityNotificationPayload.self,
                forKey: .notificationData
            ),
            associatedElement: try container.decode(
                AccessibilityNotificationPayload.self,
                forKey: .associatedElement
            )
        )
    }
}

public struct AccessibilityNotificationGap: Codable, Sendable, Equatable, Hashable {
    public let droppedThroughSequence: UInt64

    public init(droppedThroughSequence: UInt64) {
        self.droppedThroughSequence = droppedThroughSequence
    }
}

/// Normalized spoken accessibility text observed from UIKit accessibility
/// notifications. The source notification may be `elementChanged`,
/// `announcement`, or `screenChanged`; the text is exposed
/// uniformly because VoiceOver presents these string payloads as spoken output.
public struct CapturedAnnouncement: Codable, Sendable, Equatable, Hashable {
    public let sequence: UInt64
    public let text: String
    public let timestamp: Date
    public let kind: AccessibilityNotificationKind
    public let associatedElement: AccessibilityNotificationPayload

    public init(
        sequence: UInt64,
        text: String,
        timestamp: Date,
        kind: AccessibilityNotificationKind,
        associatedElement: AccessibilityNotificationPayload = .none
    ) {
        self.sequence = sequence
        self.text = text
        self.timestamp = timestamp
        self.kind = kind
        self.associatedElement = associatedElement
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sequence
        case text
        case timestamp
        case kind
        case associatedElement
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "captured accessibility announcement")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sequence: try container.decode(UInt64.self, forKey: .sequence),
            text: try container.decode(String.self, forKey: .text),
            timestamp: try container.decode(Date.self, forKey: .timestamp),
            kind: try container.decode(AccessibilityNotificationKind.self, forKey: .kind),
            associatedElement: try container.decode(
                AccessibilityNotificationPayload.self,
                forKey: .associatedElement
            )
        )
    }
}

/// Health of the accessibility-notification capture pipeline at the moment a
/// notification window was read.
///
/// An empty announcement list means nothing without this: no notifications
/// posted, the private capture SPI failed to install, and nothing being
/// subscribed all produce the same empty list. `capturing(armed:)` additionally
/// reports whether the private unit-test-mode SPI armed the runtime — an
/// unarmed capture is installed but the runtime may never post to it.
public enum AccessibilityNotificationCaptureState: Codable, Sendable, Equatable, Hashable {
    /// Callback installed. `armed` reports whether unit-test mode was enabled.
    case capturing(armed: Bool)
    /// The private notification-callback SPI could not be installed.
    case installationUnavailable
    /// Nothing is subscribed to the notification stream.
    case unsubscribed

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case armed
    }

    private enum Kind: String, Codable {
        case capturing
        case installationUnavailable
        case unsubscribed
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: CodingKeys.self,
            typeName: "accessibility notification capture state"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        let typeName = "\(kind.rawValue) accessibility notification capture state"
        switch kind {
        case .capturing:
            try container.rejectIncompatibleFields(allowing: [.type, .armed], typeName: typeName)
            self = .capturing(armed: try container.decode(Bool.self, forKey: .armed))
        case .installationUnavailable:
            try container.rejectIncompatibleFields(allowing: [.type], typeName: typeName)
            self = .installationUnavailable
        case .unsubscribed:
            try container.rejectIncompatibleFields(allowing: [.type], typeName: typeName)
            self = .unsubscribed
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .capturing(let armed):
            try container.encode(Kind.capturing, forKey: .type)
            try container.encode(armed, forKey: .armed)
        case .installationUnavailable:
            try container.encode(Kind.installationUnavailable, forKey: .type)
        case .unsubscribed:
            try container.encode(Kind.unsubscribed, forKey: .type)
        }
    }
}

extension AccessibilityNotificationCaptureState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .capturing(let armed):
            return armed ? "capturing" : "capturing(unarmed)"
        case .installationUnavailable:
            return "installationUnavailable"
        case .unsubscribed:
            return "unsubscribed"
        }
    }
}

/// One window onto the accessibility-notification stream.
///
/// `announcements` is the spoken-text projection: only notifications carrying a
/// string payload. `notifications` is the full retained event stream, including
/// the `layoutChanged` / `screenChanged` events posted with a `nil` or element
/// argument that carry no spoken text. `captureState` distinguishes an empty
/// window from a dead capture pipeline.
public struct AnnouncementListPayload: Codable, Sendable, Equatable {
    public let announcements: [CapturedAnnouncement]
    public let notifications: [AccessibilityNotificationEvidence]
    public let captureState: AccessibilityNotificationCaptureState

    public init(
        announcements: [CapturedAnnouncement],
        notifications: [AccessibilityNotificationEvidence],
        captureState: AccessibilityNotificationCaptureState
    ) {
        self.announcements = announcements
        self.notifications = notifications
        self.captureState = captureState
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case announcements
        case notifications
        case captureState
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "announcement list payload")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            announcements: try container.decode([CapturedAnnouncement].self, forKey: .announcements),
            notifications: try container.decode([AccessibilityNotificationEvidence].self, forKey: .notifications),
            captureState: try container.decode(
                AccessibilityNotificationCaptureState.self,
                forKey: .captureState
            )
        )
    }
}

public enum AccessibilityNotificationPayload: Codable, Sendable, Equatable, Hashable {
    case none
    /// String payload posted by the app/runtime, for example announcements.
    case string(String)
    /// Reference to a node in the destination capture's interface tree.
    case element(AccessibilityNotificationElementReference)
    /// Object payload that could not be correlated to the destination snapshot.
    case unresolvedObject(AccessibilityNotificationObjectPayload)
    case unresolvedElement

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case value
        case element
        case object
    }

    private enum PayloadType: String, Codable {
        case none
        case string
        case element
        case unresolvedObject
        case unresolvedElement
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "accessibility notification payload")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PayloadType.self, forKey: .type)
        let typeName = "\(type.rawValue) accessibility notification payload"
        switch type {
        case .none:
            try container.rejectIncompatibleFields(allowing: [.type], typeName: typeName)
            self = .none
        case .string:
            try container.rejectIncompatibleFields(allowing: [.type, .value], typeName: typeName)
            self = .string(try container.decode(String.self, forKey: .value))
        case .element:
            try container.rejectIncompatibleFields(allowing: [.type, .element], typeName: typeName)
            self = .element(try container.decode(AccessibilityNotificationElementReference.self, forKey: .element))
        case .unresolvedObject:
            try container.rejectIncompatibleFields(allowing: [.type, .object], typeName: typeName)
            self = .unresolvedObject(try container.decode(AccessibilityNotificationObjectPayload.self, forKey: .object))
        case .unresolvedElement:
            try container.rejectIncompatibleFields(allowing: [.type], typeName: typeName)
            self = .unresolvedElement
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode(PayloadType.none, forKey: .type)
        case .string(let value):
            try container.encode(PayloadType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case .element(let element):
            try container.encode(PayloadType.element, forKey: .type)
            try container.encode(element, forKey: .element)
        case .unresolvedObject(let object):
            try container.encode(PayloadType.unresolvedObject, forKey: .type)
            try container.encode(object, forKey: .object)
        case .unresolvedElement:
            try container.encode(PayloadType.unresolvedElement, forKey: .type)
        }
    }

}

public extension AccessibilityNotificationEvidence {
    var capturedAnnouncement: CapturedAnnouncement? {
        guard case .string(let text) = notificationData else { return nil }
        return CapturedAnnouncement(
            sequence: sequence,
            text: text,
            timestamp: timestamp,
            kind: kind,
            associatedElement: associatedElement
        )
    }
}

public extension AccessibilityTrace {
    var capturedAnnouncements: [CapturedAnnouncement] {
        captures.flatMap { capture in
            capture.transition.accessibilityNotifications.compactMap(\.capturedAnnouncement)
        }
    }
}

public struct AccessibilityNotificationObjectPayload: Codable, Sendable, Equatable, Hashable {
    public let className: String
    /// Product evidence for an unresolved payload. May include app content from
    /// Objective-C descriptions; keep it in trace artifacts, not logs.
    public let summary: String?

    public init(className: String, summary: String?) {
        self.className = className
        self.summary = summary
    }
}

public struct AccessibilityNotificationElementReference: Codable, Sendable, Equatable, Hashable {
    /// Capture-local path into the trace capture's `Interface.tree`.
    public let path: TreePath
    /// Traversal index in the trace capture's projected element order.
    public let traversalIndex: Int
    /// How the notification payload was correlated with this capture node.
    public let resolution: AccessibilityNotificationElementResolution

    public init(
        path: TreePath,
        traversalIndex: Int,
        resolution: AccessibilityNotificationElementResolution = .identity
    ) {
        self.path = path
        self.traversalIndex = traversalIndex
        self.resolution = resolution
    }
}

public enum AccessibilityNotificationElementResolution: String, Codable, Sendable, Equatable, Hashable {
    case identity
    case singleElement
}
