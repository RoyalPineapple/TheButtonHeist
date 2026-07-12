import Foundation

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
        switch kind {
        case .screenChanged:
            try Self.rejectIfPresent(.notification, in: container, kind: kind)
            try Self.rejectIfPresent(.rawCode, in: container, kind: kind)
            self = .screenChanged
        case .elementChanged:
            try Self.rejectIfPresent(.rawCode, in: container, kind: kind)
            self = .elementChanged(try container.decode(ElementChangeNotification.self, forKey: .notification))
        case .announcement:
            try Self.rejectIfPresent(.notification, in: container, kind: kind)
            try Self.rejectIfPresent(.rawCode, in: container, kind: kind)
            self = .announcement
        case .unknown:
            try Self.rejectIfPresent(.notification, in: container, kind: kind)
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

    private static func rejectIfPresent(
        _ key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>,
        kind: Kind
    ) throws {
        guard container.contains(key) else { return }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "\(kind.rawValue) accessibility notification kind must not include \(key.stringValue)"
        )
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
/// app content and are intentionally Codable so receipts can preserve the same
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

public struct AnnouncementListPayload: Codable, Sendable, Equatable {
    public let announcements: [CapturedAnnouncement]

    public init(announcements: [CapturedAnnouncement]) {
        self.announcements = announcements
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
        switch type {
        case .none:
            try Self.rejectIfPresent(.value, in: container, type: type)
            try Self.rejectIfPresent(.element, in: container, type: type)
            try Self.rejectIfPresent(.object, in: container, type: type)
            self = .none
        case .string:
            try Self.rejectIfPresent(.element, in: container, type: type)
            try Self.rejectIfPresent(.object, in: container, type: type)
            self = .string(try container.decode(String.self, forKey: .value))
        case .element:
            try Self.rejectIfPresent(.value, in: container, type: type)
            try Self.rejectIfPresent(.object, in: container, type: type)
            self = .element(try container.decode(AccessibilityNotificationElementReference.self, forKey: .element))
        case .unresolvedObject:
            try Self.rejectIfPresent(.value, in: container, type: type)
            try Self.rejectIfPresent(.element, in: container, type: type)
            self = .unresolvedObject(try container.decode(AccessibilityNotificationObjectPayload.self, forKey: .object))
        case .unresolvedElement:
            try Self.rejectIfPresent(.value, in: container, type: type)
            try Self.rejectIfPresent(.element, in: container, type: type)
            try Self.rejectIfPresent(.object, in: container, type: type)
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

    private static func rejectIfPresent(
        _ key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>,
        type: PayloadType
    ) throws {
        guard container.contains(key) else { return }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "\(type.rawValue) accessibility notification payload must not include \(key.stringValue)"
        )
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
