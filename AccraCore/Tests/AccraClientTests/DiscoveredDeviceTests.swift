import XCTest
import Network
@testable import AccraClient

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
        let endpoint = NWEndpoint.service(name: "my-service", type: "_a11ybridge._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "device-123", name: "TestApp-iPhone", endpoint: endpoint)

        XCTAssertEqual(device.id, "device-123")
        XCTAssertEqual(device.name, "TestApp-iPhone")
    }
}
