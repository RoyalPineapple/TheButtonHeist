import XCTest
import TheScore

final class ServerInfoTests: XCTestCase {

    private func makeServerInfo(
        appName: String = "TestApp",
        bundleIdentifier: BundleIdentifier = "com.test.app",
        deviceName: String = "iPhone 15",
        systemVersion: String = "17.2",
        screenWidth: Double = 393,
        screenHeight: Double = 852,
        instanceId: ServerLaunchID = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
        instanceIdentifier: InsideJobInstanceID = "test-instance",
        listeningPort: UInt16 = 49152,
        simulatorUDID: SimulatorUDID? = nil,
        vendorIdentifier: VendorIdentifier? = nil,
        tlsActive: Bool = true
    ) -> ServerInfo {
        ServerInfo(
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

    func testEncodingRoundTrip() throws {
        let info = makeServerInfo()

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ServerInfo.self, from: data)

        XCTAssertEqual(info.appName, decoded.appName)
        XCTAssertEqual(info.bundleIdentifier, decoded.bundleIdentifier)
        XCTAssertEqual(info.deviceName, decoded.deviceName)
        XCTAssertEqual(info.systemVersion, decoded.systemVersion)
        XCTAssertEqual(info.screenWidth, decoded.screenWidth)
        XCTAssertEqual(info.screenHeight, decoded.screenHeight)
    }

    func testEncodingRoundTripWithCurrentIdentity() throws {
        let info = makeServerInfo(deviceName: "iPhone 16 Pro", systemVersion: "18.0")

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ServerInfo.self, from: data)

        XCTAssertEqual(decoded.instanceId, "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
        XCTAssertEqual(decoded.instanceIdentifier, "test-instance")
        XCTAssertEqual(decoded.listeningPort, 49152)
        XCTAssertEqual(decoded.tlsActive, true)
    }

    func testDecodingWithoutCurrentIdentityFails() throws {
        let json = """
        {
            "appName": "MissingIdentity",
            "bundleIdentifier": "com.missing",
            "deviceName": "iPhone 15",
            "systemVersion": "17.0",
            "screenWidth": 390,
            "screenHeight": 844
        }
        """
        let data = Data(json.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ServerInfo.self, from: data))
    }

    func testEncodingRequiresIdentity() throws {
        let info = makeServerInfo(bundleIdentifier: "com.test", deviceName: "iPhone", systemVersion: "18.0")

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ServerInfo.self, from: data)

        XCTAssertEqual(decoded.instanceId, info.instanceId)
        XCTAssertEqual(decoded.listeningPort, info.listeningPort)
    }

    func testEncodingRoundTripWithDeviceIdentifiers() throws {
        let info = makeServerInfo(
            deviceName: "iPhone 16 Pro",
            systemVersion: "18.0",
            simulatorUDID: "DEADBEEF-1234-5678-9ABC-DEF012345678",
            vendorIdentifier: "CAFE0000-BABE-FACE-DEAD-BEEF12345678"
        )

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ServerInfo.self, from: data)

        XCTAssertEqual(decoded.simulatorUDID, "DEADBEEF-1234-5678-9ABC-DEF012345678")
        XCTAssertEqual(decoded.vendorIdentifier, "CAFE0000-BABE-FACE-DEAD-BEEF12345678")
    }

    func testDecodingWithoutDeviceIdentifiers() throws {
        let json = """
        {
            "appName": "CurrentApp",
            "bundleIdentifier": "com.current",
            "deviceName": "iPhone 15",
            "systemVersion": "17.0",
            "screenWidth": 390,
            "screenHeight": 844,
            "instanceId": "12345",
            "instanceIdentifier": "current",
            "listeningPort": 49152,
            "tlsActive": true
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ServerInfo.self, from: data)

        XCTAssertEqual(decoded.instanceId, "12345")
        XCTAssertEqual(decoded.instanceIdentifier, "current")
        XCTAssertEqual(decoded.listeningPort, 49152)
        XCTAssertNil(decoded.simulatorUDID)
        XCTAssertNil(decoded.vendorIdentifier)
    }

    func testDifferentDevices() throws {
        let devices = [
            ("iPhone 15 Pro", "17.0", 393.0, 852.0),
            ("iPad Pro", "17.0", 1024.0, 1366.0),
            ("iPhone SE", "17.0", 375.0, 667.0),
        ]

        for (name, version, width, height) in devices {
            let info = makeServerInfo(
                bundleIdentifier: "com.test",
                deviceName: name,
                systemVersion: version,
                screenWidth: width,
                screenHeight: height
            )

            let data = try JSONEncoder().encode(info)
            let decoded = try JSONDecoder().decode(ServerInfo.self, from: data)

            XCTAssertEqual(decoded.deviceName, name)
            XCTAssertEqual(decoded.screenWidth, width)
            XCTAssertEqual(decoded.screenHeight, height)
        }
    }
}
