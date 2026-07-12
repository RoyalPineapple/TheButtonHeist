import Foundation

public enum AccessibilityNotificationKind: RawRepresentable, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case screenChanged
    case layoutChanged
    case valueChanged
    case announcement
    case unknown(rawCode: UInt32)

    public static let allCases: [AccessibilityNotificationKind] = [
        .screenChanged,
        .layoutChanged,
        .valueChanged,
        .announcement,
    ]

    public var rawValue: String {
        switch self {
        case .screenChanged:
            return "screenChanged"
        case .layoutChanged:
            return "elementChanged"
        case .valueChanged:
            return "valueChanged"
        case .announcement:
            return "announcement"
        case .unknown:
            return "unknown"
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "screenChanged":
            self = .screenChanged
        case "elementChanged":
            self = .layoutChanged
        case "valueChanged":
            self = .valueChanged
        case "announcement":
            self = .announcement
        default:
            return nil
        }
    }

    public var rawCode: UInt32? {
        guard case .unknown(let rawCode) = self else { return nil }
        return rawCode
    }

    var isElementChangeEvidence: Bool {
        self != .screenChanged
    }

    public init(rawCode code: UInt32) {
        switch code {
        case 1000:
            self = .screenChanged
        case 1001:
            self = .layoutChanged
        case 1005:
            self = .valueChanged
        case 1008:
            self = .announcement
        default:
            self = .unknown(rawCode: code)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let wireValue = try container.decode(String.self)
        guard let kind = Self(rawValue: wireValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown accessibility notification kind \(wireValue)"
            )
        }
        self = kind
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    fileprivate static func decodeEvidenceKind<K: CodingKey>(
        wireValue: String,
        rawCode: UInt32?,
        forKey key: K,
        in container: KeyedDecodingContainer<K>
    ) throws -> AccessibilityNotificationKind {
        switch wireValue {
        case "screenChanged":
            try rejectRawCode(rawCode, forKey: key, in: container)
            return .screenChanged
        case "elementChanged":
            try rejectRawCode(rawCode, forKey: key, in: container)
            return .layoutChanged
        case "valueChanged":
            try rejectRawCode(rawCode, forKey: key, in: container)
            return .valueChanged
        case "announcement":
            try rejectRawCode(rawCode, forKey: key, in: container)
            return .announcement
        case "unknown":
            guard let rawCode else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: container,
                    debugDescription: "unknown accessibility notification evidence requires rawCode"
                )
            }
            return .unknown(rawCode: rawCode)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Unknown accessibility notification kind \(wireValue)"
            )
        }
    }

    private static func rejectRawCode<K: CodingKey>(
        _ rawCode: UInt32?,
        forKey key: K,
        in container: KeyedDecodingContainer<K>
    ) throws {
        guard rawCode == nil else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "rawCode is only valid for unknown accessibility notification evidence"
            )
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
    public var rawCode: UInt32? { kind.rawCode }
    public let timestamp: Date
    public let notificationData: AccessibilityNotificationPayload
    public let associatedElement: AccessibilityNotificationPayload

    public init(
        sequence: UInt64,
        kind: AccessibilityNotificationKind,
        rawCode: UInt32? = nil,
        timestamp: Date,
        notificationData: AccessibilityNotificationPayload,
        associatedElement: AccessibilityNotificationPayload
    ) {
        self.sequence = sequence
        self.kind = rawCode.map { AccessibilityNotificationKind(rawCode: $0) } ?? kind
        self.timestamp = timestamp
        self.notificationData = notificationData
        self.associatedElement = associatedElement
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sequence
        case kind
        case rawCode
        case timestamp
        case notificationData
        case associatedElement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let wireKind = try container.decode(String.self, forKey: .kind)
        let rawCode = try container.decodeIfPresent(UInt32.self, forKey: .rawCode)
        let kind = try AccessibilityNotificationKind.decodeEvidenceKind(
            wireValue: wireKind,
            rawCode: rawCode,
            forKey: CodingKeys.rawCode,
            in: container
        )
        self.init(
            sequence: try container.decode(UInt64.self, forKey: .sequence),
            kind: kind,
            timestamp: try container.decode(Date.self, forKey: .timestamp),
            notificationData: try container.decode(AccessibilityNotificationPayload.self, forKey: .notificationData),
            associatedElement: try container.decode(AccessibilityNotificationPayload.self, forKey: .associatedElement)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(kind.rawValue, forKey: .kind)
        if let rawCode {
            try container.encode(rawCode, forKey: .rawCode)
        }
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(notificationData, forKey: .notificationData)
        try container.encode(associatedElement, forKey: .associatedElement)
    }
}

/// Normalized spoken accessibility text observed from UIKit accessibility
/// notifications. The source notification may be `announcement`,
/// `layoutChanged`, `valueChanged`, or `screenChanged`; the text is exposed
/// uniformly because VoiceOver presents these string payloads as spoken output.
public struct CapturedAnnouncement: Codable, Sendable, Equatable, Hashable {
    public let sequence: UInt64
    public let text: String
    public let timestamp: Date
    public let kind: AccessibilityNotificationKind
    public var rawCode: UInt32? { kind.rawCode }
    public let associatedElement: AccessibilityNotificationPayload

    public init(
        sequence: UInt64,
        text: String,
        timestamp: Date,
        kind: AccessibilityNotificationKind,
        rawCode: UInt32? = nil,
        associatedElement: AccessibilityNotificationPayload = .none
    ) {
        self.sequence = sequence
        self.text = text
        self.timestamp = timestamp
        self.kind = rawCode.map { AccessibilityNotificationKind(rawCode: $0) } ?? kind
        self.associatedElement = associatedElement
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sequence
        case text
        case timestamp
        case kind
        case rawCode
        case associatedElement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let wireKind = try container.decode(String.self, forKey: .kind)
        let rawCode = try container.decodeIfPresent(UInt32.self, forKey: .rawCode)
        self.init(
            sequence: try container.decode(UInt64.self, forKey: .sequence),
            text: try container.decode(String.self, forKey: .text),
            timestamp: try container.decode(Date.self, forKey: .timestamp),
            kind: try AccessibilityNotificationKind.decodeEvidenceKind(
                wireValue: wireKind,
                rawCode: rawCode,
                forKey: CodingKeys.rawCode,
                in: container
            ),
            associatedElement: try container.decode(
                AccessibilityNotificationPayload.self,
                forKey: .associatedElement
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(text, forKey: .text)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(kind.rawValue, forKey: .kind)
        if let rawCode {
            try container.encode(rawCode, forKey: .rawCode)
        }
        try container.encode(associatedElement, forKey: .associatedElement)
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
            rawCode: rawCode,
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
