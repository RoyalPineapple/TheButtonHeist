import Foundation

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
    public let code: UInt32
    public let name: String
    public let timestamp: Date
    public let notificationData: AccessibilityNotificationPayload
    public let associatedElement: AccessibilityNotificationPayload

    public init(
        sequence: UInt64,
        code: UInt32,
        name: String,
        timestamp: Date,
        notificationData: AccessibilityNotificationPayload,
        associatedElement: AccessibilityNotificationPayload
    ) {
        self.sequence = sequence
        self.code = code
        self.name = name
        self.timestamp = timestamp
        self.notificationData = notificationData
        self.associatedElement = associatedElement
    }
}

/// Normalized spoken accessibility text observed from UIKit accessibility
/// notifications. The source notification may be `announcement`,
/// `layoutChanged`, or `screenChanged`; the text is exposed uniformly because
/// VoiceOver presents all three string payloads as spoken output.
public struct CapturedAnnouncement: Codable, Sendable, Equatable, Hashable {
    public let sequence: UInt64
    public let text: String
    public let timestamp: Date
    public let notificationCode: UInt32
    public let notificationName: String
    public let associatedElement: AccessibilityNotificationPayload

    public init(
        sequence: UInt64,
        text: String,
        timestamp: Date,
        notificationCode: UInt32,
        notificationName: String,
        associatedElement: AccessibilityNotificationPayload = .none
    ) {
        self.sequence = sequence
        self.text = text
        self.timestamp = timestamp
        self.notificationCode = notificationCode
        self.notificationName = notificationName
        self.associatedElement = associatedElement
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
            notificationCode: code,
            notificationName: name,
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
