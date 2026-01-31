import Foundation
import CoreGraphics

/// Bonjour service type for discovery
public let accraServiceType = "_a11ybridge._tcp"

/// Protocol version for compatibility checking
public let protocolVersion = "1.0"

// MARK: - Client -> Server Messages

public enum ClientMessage: Codable {
    /// Request current accessibility hierarchy
    case requestHierarchy

    /// Subscribe to automatic updates
    case subscribe

    /// Unsubscribe from automatic updates
    case unsubscribe

    /// Ping for keepalive
    case ping
}

// MARK: - Server -> Client Messages

public enum ServerMessage: Codable {
    /// Server info on connection
    case info(ServerInfo)

    /// Accessibility hierarchy response/update
    case hierarchy(HierarchyPayload)

    /// Pong response
    case pong

    /// Error message
    case error(String)
}

public struct ServerInfo: Codable, Sendable {
    public let protocolVersion: String
    public let appName: String
    public let bundleIdentifier: String
    public let deviceName: String
    public let systemVersion: String
    public let screenWidth: Double
    public let screenHeight: Double

    public init(
        protocolVersion: String,
        appName: String,
        bundleIdentifier: String,
        deviceName: String,
        systemVersion: String,
        screenWidth: Double,
        screenHeight: Double
    ) {
        self.protocolVersion = protocolVersion
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.deviceName = deviceName
        self.systemVersion = systemVersion
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
    }
}

public struct HierarchyPayload: Codable, Sendable {
    public let timestamp: Date
    public let elements: [AccessibilityElementData]

    public init(timestamp: Date, elements: [AccessibilityElementData]) {
        self.timestamp = timestamp
        self.elements = elements
    }
}

// MARK: - Cross-Platform Element Type

/// Platform-agnostic element data - represents an accessibility element in VoiceOver traversal order
public struct AccessibilityElementData: Codable, Equatable, Hashable, Sendable {
    /// VoiceOver traversal index (0-based)
    public var traversalIndex: Int
    /// The description that VoiceOver will read
    public var description: String
    public var label: String?
    public var value: String?
    public var traits: [String]  // Human-readable trait names
    public var identifier: String?
    public var hint: String?
    public var frameX: Double
    public var frameY: Double
    public var frameWidth: Double
    public var frameHeight: Double
    public var activationPointX: Double
    public var activationPointY: Double
    public var customActions: [String]  // Action names

    public init(
        traversalIndex: Int,
        description: String,
        label: String?,
        value: String?,
        traits: [String],
        identifier: String?,
        hint: String?,
        frameX: Double,
        frameY: Double,
        frameWidth: Double,
        frameHeight: Double,
        activationPointX: Double,
        activationPointY: Double,
        customActions: [String]
    ) {
        self.traversalIndex = traversalIndex
        self.description = description
        self.label = label
        self.value = value
        self.traits = traits
        self.identifier = identifier
        self.hint = hint
        self.frameX = frameX
        self.frameY = frameY
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.activationPointX = activationPointX
        self.activationPointY = activationPointY
        self.customActions = customActions
    }
}

// MARK: - Convenience Extensions

extension AccessibilityElementData {
    /// Computed frame as CGRect (available on both platforms)
    public var frame: CGRect {
        CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
    }

    /// Computed activation point as CGPoint
    public var activationPoint: CGPoint {
        CGPoint(x: activationPointX, y: activationPointY)
    }
}

extension ServerInfo {
    /// Computed screen size as CGSize
    public var screenSize: CGSize {
        CGSize(width: screenWidth, height: screenHeight)
    }
}
