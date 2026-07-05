import ThePlans
import Foundation

public enum ScreenCaptureMode: String, Codable, Sendable, Equatable, CaseIterable {
    case raw
    case accessibility
}

public struct ScreenRequestPayload: Codable, Sendable, Equatable {
    public let mode: ScreenCaptureMode

    public init(mode: ScreenCaptureMode = .raw) {
        self.mode = mode
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case mode
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "screen request payload")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(ScreenCaptureMode.self, forKey: .mode) ?? .raw
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
    }
}

/// Payload containing screen capture data and optional interface evidence.
public struct ScreenPayload: Codable, Sendable, Equatable {
    public let pngData: String
    public let width: Double
    public let height: Double
    public let timestamp: Date
    public let interface: Interface?

    public init(
        pngData: String,
        width: Double,
        height: Double,
        timestamp: Date = Date(),
        interface: Interface? = nil
    ) {
        self.pngData = pngData
        self.width = width
        self.height = height
        self.timestamp = timestamp
        self.interface = interface
    }
}
