import XCTest
import Network
@testable import Wheelman

final class DiscoveredDeviceTests: XCTestCase {

    func testEquality() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device1 = DiscoveredDevice(id: "test-1", name: "Device 1", endpoint: endpoint)
        let device2 = DiscoveredDevice(id: "test-1", name: "Device 1", endpoint: endpoint)
        let device3 = DiscoveredDevice(id: "test-2", name: "Device 2", endpoint: endpoint)

        XCTAssertEqual(device1, device2)
        XCTAssertNotEqual(device1, device3)
    }

    func testEqualityById() {
        // Devices with same ID but different names should be equal (ID is the identity)
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device1 = DiscoveredDevice(id: "same-id", name: "Device A", endpoint: endpoint)
        let device2 = DiscoveredDevice(id: "same-id", name: "Device B", endpoint: endpoint)

        XCTAssertEqual(device1, device2)
    }

    func testHashable() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device1 = DiscoveredDevice(id: "test-1", name: "Device", endpoint: endpoint)
        let device2 = DiscoveredDevice(id: "test-1", name: "Device", endpoint: endpoint)

        var set = Set<DiscoveredDevice>()
        set.insert(device1)
        set.insert(device2)

        XCTAssertEqual(set.count, 1)
    }

    func testIdentifiable() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "unique-id", name: "Test Device", endpoint: endpoint)

        XCTAssertEqual(device.id, "unique-id")
    }

    func testDeviceProperties() {
        let endpoint = NWEndpoint.service(name: "my-service", type: "_buttonheist._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "device-123", name: "TestApp-iPhone", endpoint: endpoint)

        XCTAssertEqual(device.id, "device-123")
        XCTAssertEqual(device.name, "TestApp-iPhone")
    }

    // MARK: - Short ID Parsing

    func testShortIdParsing() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp-iPhone 16 Pro#a1b2c3d4", endpoint: endpoint)

        XCTAssertEqual(device.shortId, "a1b2c3d4")
    }

    func testShortIdNilWithoutHash() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp-iPhone 16 Pro", endpoint: endpoint)

        XCTAssertNil(device.shortId)
    }

    func testShortIdNilWithEmptyHash() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp-iPhone#", endpoint: endpoint)

        XCTAssertNil(device.shortId)
    }

    // MARK: - Name Parsing with Short ID

    func testParsedNameWithShortId() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp-iPhone 16 Pro#a1b2c3d4", endpoint: endpoint)

        XCTAssertEqual(device.appName, "TestApp")
        XCTAssertEqual(device.deviceName, "iPhone 16 Pro")
        XCTAssertEqual(device.shortId, "a1b2c3d4")
    }

    func testParsedNameWithoutShortId() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp-iPhone 16 Pro", endpoint: endpoint)

        XCTAssertEqual(device.appName, "TestApp")
        XCTAssertEqual(device.deviceName, "iPhone 16 Pro")
        XCTAssertNil(device.shortId)
    }

    func testAppNameFallbackNoDash() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "NoDashName#abc123", endpoint: endpoint)

        XCTAssertEqual(device.appName, "NoDashName")
        XCTAssertEqual(device.deviceName, "")
        XCTAssertEqual(device.shortId, "abc123")
    }

    func testAppNameWithDashesInDeviceName() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "My-App-iPhone#ff00ff00", endpoint: endpoint)

        // Last dash splits: "My-App" and "iPhone"
        XCTAssertEqual(device.appName, "My-App")
        XCTAssertEqual(device.deviceName, "iPhone")
        XCTAssertEqual(device.shortId, "ff00ff00")
    }

    // MARK: - Device Identifiers

    func testSimulatorUDID() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(
            id: "test", name: "TestApp-iPhone#abc",
            endpoint: endpoint,
            simulatorUDID: "DEADBEEF-1234-5678-9ABC-DEF012345678"
        )

        XCTAssertEqual(device.simulatorUDID, "DEADBEEF-1234-5678-9ABC-DEF012345678")
    }

    func testDefaultIdentifiersNil() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp-iPhone", endpoint: endpoint)

        XCTAssertNil(device.simulatorUDID)
    }
}
