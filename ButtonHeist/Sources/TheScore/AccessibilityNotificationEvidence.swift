import Foundation

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

public enum AccessibilityNotificationPayload: Codable, Sendable, Equatable, Hashable {
    case none
    case string(String)
    case element(AccessibilityNotificationElementReference)
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
            self = .none
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .element:
            self = .element(try container.decode(AccessibilityNotificationElementReference.self, forKey: .element))
        case .unresolvedObject:
            self = .unresolvedObject(try container.decode(AccessibilityNotificationObjectPayload.self, forKey: .object))
        case .unresolvedElement:
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

public struct AccessibilityNotificationObjectPayload: Codable, Sendable, Equatable, Hashable {
    public let className: String
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
