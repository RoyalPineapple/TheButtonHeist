import ThePlans
import Foundation

/// Server identity and capabilities sent after a successful handshake.
///
/// `buttonHeistVersion` is carried by `ResponseEnvelope.buttonHeistVersion`;
/// it is not duplicated here.
public struct ServerInfo: Codable, Sendable {
    public let appName: String
    public let bundleIdentifier: BundleIdentifier
    public let deviceName: String
    public let systemVersion: String
    public let screenWidth: Double
    public let screenHeight: Double
    /// Per-launch session identifier
    public let instanceId: ServerLaunchID
    /// Human-readable instance identifier (from INSIDEJOB_ID env var, or generated shortId)
    public let instanceIdentifier: InsideJobInstanceID
    /// Port the server is listening on
    public let listeningPort: UInt16
    /// Simulator UDID when running on iOS Simulator (nil on physical devices)
    public let simulatorUDID: SimulatorUDID?
    /// Vendor identifier from UIDevice.identifierForVendor (stable per app install per device)
    public let vendorIdentifier: VendorIdentifier?
    /// Whether TLS transport encryption is active
    public let tlsActive: Bool

    public init(
        appName: String,
        bundleIdentifier: BundleIdentifier,
        deviceName: String,
        systemVersion: String,
        screenWidth: Double,
        screenHeight: Double,
        instanceId: ServerLaunchID,
        instanceIdentifier: InsideJobInstanceID,
        listeningPort: UInt16,
        simulatorUDID: SimulatorUDID? = nil,
        vendorIdentifier: VendorIdentifier? = nil,
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
