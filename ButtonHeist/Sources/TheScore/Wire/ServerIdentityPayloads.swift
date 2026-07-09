import ThePlans
import Foundation

/// Server identity and capabilities sent after a successful handshake.
///
/// `buttonHeistVersion` is carried by `ResponseEnvelope.buttonHeistVersion`;
/// it is not duplicated here.
public struct ServerInfo: Codable, Sendable {
    public let appName: String
    public let bundleIdentifier: String
    public let deviceName: String
    public let systemVersion: String
    public let screenWidth: Double
    public let screenHeight: Double
    /// Per-launch session identifier
    public let instanceId: String
    /// Human-readable instance identifier (from INSIDEJOB_ID env var, or generated shortId)
    public let instanceIdentifier: String
    /// Port the server is listening on
    public let listeningPort: UInt16
    /// Simulator UDID when running on iOS Simulator (nil on physical devices)
    public let simulatorUDID: String?
    /// Vendor identifier from UIDevice.identifierForVendor (stable per app install per device)
    public let vendorIdentifier: String?
    /// Whether TLS transport encryption is active
    public let tlsActive: Bool

    public init(
        appName: String,
        bundleIdentifier: String,
        deviceName: String,
        systemVersion: String,
        screenWidth: Double,
        screenHeight: Double,
        instanceId: String,
        instanceIdentifier: String,
        listeningPort: UInt16,
        simulatorUDID: String? = nil,
        vendorIdentifier: String? = nil,
        tlsActive: Bool
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.deviceName = deviceName
        self.systemVersion = systemVersion
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.instanceId = instanceId
        self.instanceIdentifier = instanceIdentifier
        self.listeningPort = listeningPort
        self.simulatorUDID = simulatorUDID
        self.vendorIdentifier = vendorIdentifier
        self.tlsActive = tlsActive
    }
}
