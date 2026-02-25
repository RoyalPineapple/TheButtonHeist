import XCTest
 import TheScore

final class ServerInfoTests: XCTestCase {

    func testScreenSizeComputed() {
        let info = ServerInfo(
            protocolVersion: "1.0",
            appName: "Test",
            bundleIdentifier: "com.test",
            deviceName: "iPhone",
            systemVersion: "17.0",
            screenWidth: 390,
            screenHeight: 844
        )

        let size = info.screenSize
        XCTAssertEqual(size.width, 390)
        XCTAssertEqual(size.height, 844)
    }

    func testEncodingRoundTrip() throws {
        let info = ServerInfo(
            protocolVersion: "1.0",
            appName: "TestApp",
            bundleIdentifier: "com.test.app",
            deviceName: "iPhone 15",
            systemVersion: "17.2",
            screenWidth: 393,
            screenHeight: 852
        )

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ServerInfo.self, from: data)

        XCTAssertEqual(info.protocolVersion, decoded.protocolVersion)
        XCTAssertEqual(info.appName, decoded.appName)
        XCTAssertEqual(info.bundleIdentifier, decoded.bundleIdentifier)
        XCTAssertEqual(info.deviceName, decoded.deviceName)
        XCTAssertEqual(info.systemVersion, decoded.systemVersion)
        XCTAssertEqual(info.screenWidth, decoded.screenWidth)
        XCTAssertEqual(info.screenHeight, decoded.screenHeight)
    }

    func testEncodingRoundTripWithInstanceId() throws {
        let info = ServerInfo(
            protocolVersion: "2.0",
            appName: "TestApp",
            bundleIdentifier: "com.test.app",
            deviceName: "iPhone 16 Pro",
            systemVersion: "18.0",
            screenWidth: 393,
            screenHeight: 852,
            instanceId: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
            listeningPort: 49152
        )

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ServerInfo.self, from: data)

        XCTAssertEqual(decoded.instanceId, "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
        XCTAssertEqual(decoded.listeningPort, 49152)
    }

    func testDecodingWithoutInstanceId() throws {
        // Simulate old server that doesn't include instanceId/listeningPort
        let json = """
        {
            "protocolVersion": "2.0",
            "appName": "OldApp",
            "bundleIdentifier": "com.old",
            "deviceName": "iPhone 15",
            "systemVersion": "17.0",
            "screenWidth": 390,
            "screenHeight": 844
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ServerInfo.self, from: data)

        XCTAssertEqual(decoded.appName, "OldApp")
        XCTAssertNil(decoded.instanceId)
        XCTAssertNil(decoded.listeningPort)
    }

    func testEncodingWithNilInstanceId() throws {
        let info = ServerInfo(
            protocolVersion: "2.0",
            appName: "TestApp",
            bundleIdentifier: "com.test",
            deviceName: "iPhone",
            systemVersion: "18.0",
            screenWidth: 393,
            screenHeight: 852
        )

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ServerInfo.self, from: data)

        XCTAssertNil(decoded.instanceId)
        XCTAssertNil(decoded.listeningPort)
    }

    func testEncodingRoundTripWithDeviceIdentifiers() throws {
        let info = ServerInfo(
            protocolVersion: "2.0",
            appName: "TestApp",
            bundleIdentifier: "com.test.app",
            deviceName: "iPhone 16 Pro",
            systemVersion: "18.0",
            screenWidth: 393,
            screenHeight: 852,
            instanceId: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
            listeningPort: 49152,
            simulatorUDID: "DEADBEEF-1234-5678-9ABC-DEF012345678",
            vendorIdentifier: "CAFE0000-BABE-FACE-DEAD-BEEF12345678"
        )

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ServerInfo.self, from: data)

        XCTAssertEqual(decoded.simulatorUDID, "DEADBEEF-1234-5678-9ABC-DEF012345678")
        XCTAssertEqual(decoded.vendorIdentifier, "CAFE0000-BABE-FACE-DEAD-BEEF12345678")
    }

    func testDecodingWithoutDeviceIdentifiers() throws {
        // Simulate server that doesn't include simulatorUDID/vendorIdentifier
        let json = """
        {
            "protocolVersion": "2.0",
            "appName": "OldApp",
            "bundleIdentifier": "com.old",
            "deviceName": "iPhone 15",
            "systemVersion": "17.0",
            "screenWidth": 390,
            "screenHeight": 844,
            "instanceId": "12345"
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ServerInfo.self, from: data)

        XCTAssertEqual(decoded.instanceId, "12345")
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
            let info = ServerInfo(
                protocolVersion: "1.0",
                appName: "TestApp",
                bundleIdentifier: "com.test",
                deviceName: name,
                systemVersion: version,
                screenWidth: width,
                screenHeight: height
            )

            let data = try JSONEncoder().encode(info)
            let decoded = try JSONDecoder().decode(ServerInfo.self, from: data)

            XCTAssertEqual(decoded.deviceName, name)
            XCTAssertEqual(decoded.screenSize.width, width)
            XCTAssertEqual(decoded.screenSize.height, height)
        }
    }
}
