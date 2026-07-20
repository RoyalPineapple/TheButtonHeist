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

    package init(
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
        precondition(Self.admits(screenWidth: screenWidth, screenHeight: screenHeight, listeningPort: listeningPort))

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

    public init?(
        admitting appName: String,
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
        guard Self.admits(screenWidth: screenWidth, screenHeight: screenHeight, listeningPort: listeningPort) else {
            return nil
        }
        self.init(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            deviceName: deviceName,
            systemVersion: systemVersion,
            screenWidth: screenWidth,
            screenHeight: screenHeight,
            instanceId: instanceId,
            instanceIdentifier: instanceIdentifier,
            listeningPort: listeningPort,
            simulatorUDID: simulatorUDID,
            vendorIdentifier: vendorIdentifier,
            tlsActive: tlsActive
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case appName, bundleIdentifier, deviceName, systemVersion
        case screenWidth, screenHeight
        case instanceId, instanceIdentifier, listeningPort
        case simulatorUDID, vendorIdentifier, tlsActive
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "server info")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let admitted = Self(
            admitting: try container.decode(String.self, forKey: .appName),
            bundleIdentifier: try container.decode(BundleIdentifier.self, forKey: .bundleIdentifier),
            deviceName: try container.decode(String.self, forKey: .deviceName),
            systemVersion: try container.decode(String.self, forKey: .systemVersion),
            screenWidth: try container.decode(Double.self, forKey: .screenWidth),
            screenHeight: try container.decode(Double.self, forKey: .screenHeight),
            instanceId: try container.decode(ServerLaunchID.self, forKey: .instanceId),
            instanceIdentifier: try container.decode(InsideJobInstanceID.self, forKey: .instanceIdentifier),
            listeningPort: try container.decode(UInt16.self, forKey: .listeningPort),
            simulatorUDID: try container.decodeIfPresent(SimulatorUDID.self, forKey: .simulatorUDID),
            vendorIdentifier: try container.decodeIfPresent(VendorIdentifier.self, forKey: .vendorIdentifier),
            tlsActive: try container.decode(Bool.self, forKey: .tlsActive)
        ) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "server dimensions and listening port must be positive"
            ))
        }
        self = admitted
    }

    private static func admits(screenWidth: Double, screenHeight: Double, listeningPort: UInt16) -> Bool {
        screenWidth.isFinite && screenWidth > 0 && screenHeight.isFinite && screenHeight > 0 && listeningPort > 0
    }
}
