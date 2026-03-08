import XCTest
import Network
@testable import TheWheelman

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
        XCTAssertNil(device.tokenHash)
        XCTAssertNil(device.instanceId)
        XCTAssertNil(device.sessionActive)
    }

    func testAllTXTRecordFields() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(
            id: "test", name: "TestApp-iPhone#abc",
            endpoint: endpoint,
            simulatorUDID: "SIM-UUID",
            tokenHash: "deadbeef",
            instanceId: "my-instance",
            sessionActive: true
        )

        XCTAssertEqual(device.simulatorUDID, "SIM-UUID")
        XCTAssertEqual(device.tokenHash, "deadbeef")
        XCTAssertEqual(device.instanceId, "my-instance")
        XCTAssertEqual(device.sessionActive, true)
    }

    func testSessionActiveFalse() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(
            id: "test", name: "TestApp-iPhone",
            endpoint: endpoint,
            sessionActive: false
        )

        XCTAssertEqual(device.sessionActive, false)
    }

    // MARK: - Filter Matching

    func testMatchesByName() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp-iPhone 16 Pro#abc123", endpoint: endpoint)

        XCTAssertTrue(device.matches(filter: "TestApp"))
        XCTAssertTrue(device.matches(filter: "iPhone"))
        XCTAssertTrue(device.matches(filter: "testapp")) // case-insensitive
    }

    func testMatchesByAppName() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "MyApp-iPhone#abc", endpoint: endpoint)

        XCTAssertTrue(device.matches(filter: "MyApp"))
        XCTAssertTrue(device.matches(filter: "myapp"))
        XCTAssertFalse(device.matches(filter: "OtherApp"))
    }

    func testMatchesByDeviceName() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp-iPhone 16 Pro#abc", endpoint: endpoint)

        XCTAssertTrue(device.matches(filter: "iPhone 16"))
        XCTAssertTrue(device.matches(filter: "iphone 16 pro"))
    }

    func testMatchesByShortIdPrefix() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp-iPhone#abc123", endpoint: endpoint)

        XCTAssertTrue(device.matches(filter: "abc"))
        XCTAssertTrue(device.matches(filter: "abc123"))
        // "123" still matches via name.contains (full name includes "abc123")
        XCTAssertTrue(device.matches(filter: "123"))
    }

    func testMatchesByInstanceIdPrefix() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(
            id: "test", name: "TestApp-iPhone",
            endpoint: endpoint,
            instanceId: "my-instance-42"
        )

        XCTAssertTrue(device.matches(filter: "my-instance"))
        XCTAssertFalse(device.matches(filter: "instance-42"))
    }

    func testMatchesBySimulatorUDIDPrefix() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(
            id: "test", name: "TestApp-iPhone",
            endpoint: endpoint,
            simulatorUDID: "DEADBEEF-1234-5678-9ABC-DEF012345678"
        )

        XCTAssertTrue(device.matches(filter: "DEADBEEF"))
        XCTAssertTrue(device.matches(filter: "deadbeef"))
        XCTAssertFalse(device.matches(filter: "1234-5678"))
    }

    func testNoMatch() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp-iPhone#abc", endpoint: endpoint)

        XCTAssertFalse(device.matches(filter: "Android"))
        XCTAssertFalse(device.matches(filter: "zzzzz"))
    }

    // MARK: - Array first(matching:)

    func testArrayFirstMatchingNilFilter() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let devices = [
            DiscoveredDevice(id: "a", name: "First-iPhone", endpoint: endpoint),
            DiscoveredDevice(id: "b", name: "Second-iPad", endpoint: endpoint),
        ]

        XCTAssertEqual(devices.first(matching: nil)?.id, "a")
    }

    func testArrayFirstMatchingWithFilter() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let devices = [
            DiscoveredDevice(id: "a", name: "First-iPhone", endpoint: endpoint),
            DiscoveredDevice(id: "b", name: "Second-iPad", endpoint: endpoint),
        ]

        XCTAssertEqual(devices.first(matching: "iPad")?.id, "b")
        XCTAssertNil(devices.first(matching: "Mac"))
    }

    func testArrayFirstMatchingEmpty() {
        let devices: [DiscoveredDevice] = []

        XCTAssertNil(devices.first(matching: nil))
        XCTAssertNil(devices.first(matching: "anything"))
    }

    // MARK: - Host:Port Init

    func testHostPortInit() {
        let device = DiscoveredDevice(host: "127.0.0.1", port: 8080)

        XCTAssertEqual(device.id, "127.0.0.1:8080")
        XCTAssertEqual(device.name, "127.0.0.1:8080")
        XCTAssertNil(device.simulatorUDID)
        XCTAssertNil(device.sessionActive)
    }
}
