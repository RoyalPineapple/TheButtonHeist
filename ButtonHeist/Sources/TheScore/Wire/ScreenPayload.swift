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

    package init(
        pngData: String,
        width: Double,
        height: Double,
        timestamp: Date = Date(),
        interface: Interface? = nil
    ) {
        precondition(Self.admits(width: width, height: height))
        self.pngData = pngData
        self.width = width
        self.height = height
        self.timestamp = timestamp
        self.interface = interface
    }

    public static func admit(
        pngData: String,
        width: Double,
        height: Double,
        timestamp: Date = Date(),
        interface: Interface? = nil
    ) -> Self? {
        guard admits(width: width, height: height) else { return nil }
        return Self(
            pngData: pngData,
            width: width,
            height: height,
            timestamp: timestamp,
            interface: interface
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case pngData, width, height, timestamp, interface
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "screen payload")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let admitted = Self.admit(
            pngData: try container.decode(String.self, forKey: .pngData),
            width: try container.decode(Double.self, forKey: .width),
            height: try container.decode(Double.self, forKey: .height),
            timestamp: try container.decode(Date.self, forKey: .timestamp),
            interface: try container.decodeIfPresent(Interface.self, forKey: .interface)
        ) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "screen dimensions must be positive and finite"
            ))
        }
        self = admitted
    }

    private static func admits(width: Double, height: Double) -> Bool {
        width.isFinite && width > 0 && height.isFinite && height > 0
    }
}
