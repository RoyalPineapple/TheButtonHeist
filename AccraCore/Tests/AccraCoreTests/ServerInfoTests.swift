import XCTest
@testable import AccraCore

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
