import Foundation

/// Payload containing screen capture data and the current visible accessibility tree.
public struct ScreenPayload: Codable, Sendable {
    public let pngData: String
    public let width: Double
    public let height: Double
    public let timestamp: Date
    public let interface: Interface

    public init(
        pngData: String,
        width: Double,
        height: Double,
        timestamp: Date = Date(),
        interface: Interface
    ) {
        self.pngData = pngData
        self.width = width
        self.height = height
        self.timestamp = timestamp
        self.interface = interface
    }
}
