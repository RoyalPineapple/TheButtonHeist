import Foundation

public struct WarnStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case message
    }

    public let message: HeistWarningMessage

    public init(message: HeistWarningMessage) {
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "warn step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(message: try container.decode(HeistWarningMessage.self, forKey: .message))
    }
}

public struct FailStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case message
    }

    public let message: HeistFailureMessage

    public init(message: HeistFailureMessage) {
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "fail step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(message: try container.decode(HeistFailureMessage.self, forKey: .message))
    }
}
