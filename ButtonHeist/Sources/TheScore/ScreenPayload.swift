import ThePlans
import Foundation

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
