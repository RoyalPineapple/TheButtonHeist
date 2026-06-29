import XCTest
import Network
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

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
        let device = DiscoveredDevice(id: "device-123", name: "TestApp", endpoint: endpoint)

        XCTAssertEqual(device.id, "device-123")
        XCTAssertEqual(device.name, "TestApp")
    }

    // MARK: - Typed Discovery Identifiers

    func testDiscoveryServiceNameIsHashableByRawValue() {
        let serviceName = DiscoveryServiceName("DemoApp#abc123")
        let sameServiceName = DiscoveryServiceName("DemoApp#abc123")
        let otherServiceName = DiscoveryServiceName("DemoApp#def456")

        XCTAssertEqual(serviceName, sameServiceName)
        XCTAssertNotEqual(serviceName, otherServiceName)
        XCTAssertEqual(Set([serviceName, sameServiceName, otherServiceName]).count, 2)
        XCTAssertEqual(serviceName.rawValue, "DemoApp#abc123")
    }

    func testDiscoveryIdentityPreservesRawAndPrintedValue() {
        let serviceName = DiscoveryServiceName("DemoApp#abc123")
        let serviceIdentity = DiscoveryIdentity.serviceName(serviceName)
        let installIdentity = DiscoveryIdentity.installation(
            appName: " DemoApp ",
            installationId: "install-1"
        )

        XCTAssertEqual(serviceIdentity.rawValue, "service|DemoApp#abc123")
        XCTAssertEqual(String(describing: serviceIdentity), "service|DemoApp#abc123")
        XCTAssertEqual(installIdentity.rawValue, "install|demoapp|install-1")
        XCTAssertEqual(String(describing: installIdentity), "install|demoapp|install-1")
    }

    func testDiscoveryWrappersEncodeAsSingleJSONStringValues() throws {
        let encoder = JSONEncoder()
        let serviceName = DiscoveryServiceName("DemoApp#abc123")
        let identity = DiscoveryIdentity.serviceName(serviceName)

        XCTAssertEqual(String(data: try encoder.encode(serviceName), encoding: .utf8), #""DemoApp#abc123""#)
        XCTAssertEqual(String(data: try encoder.encode(identity), encoding: .utf8), #""service|DemoApp#abc123""#)
    }

    // MARK: - Short ID Parsing

    func testShortIdParsing() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp#a1b2c3d4", endpoint: endpoint)

        XCTAssertEqual(device.shortId, "a1b2c3d4")
    }

    func testShortIdNilWithoutHash() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp", endpoint: endpoint)

        XCTAssertNil(device.shortId)
    }

    func testShortIdNilWithEmptyHash() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp#", endpoint: endpoint)

        XCTAssertNil(device.shortId)
    }

    // MARK: - Service Name Identity

    func testAppNameUsesServiceNameWithoutInstanceId() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp#a1b2c3d4", endpoint: endpoint)

        XCTAssertEqual(device.appName, "TestApp")
        XCTAssertEqual(device.deviceName, "")
        XCTAssertEqual(device.shortId, "a1b2c3d4")
    }

    func testAppNameWithoutShortIdUsesServiceName() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp", endpoint: endpoint)

        XCTAssertEqual(device.appName, "TestApp")
        XCTAssertEqual(device.deviceName, "")
        XCTAssertNil(device.shortId)
    }

    func testAppNameStripsInstanceIdSuffix() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "NoDashName#abc123", endpoint: endpoint)

        XCTAssertEqual(device.appName, "NoDashName")
        XCTAssertEqual(device.deviceName, "")
        XCTAssertEqual(device.shortId, "abc123")
    }

    func testAppNameMayContainDashes() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "My-App#ff00ff00", endpoint: endpoint)

        XCTAssertEqual(device.appName, "My-App")
        XCTAssertEqual(device.deviceName, "")
        XCTAssertEqual(device.shortId, "ff00ff00")
    }

    // MARK: - Device Identifiers

    func testSimulatorUDID() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(
            id: "test", name: "TestApp#abc",
            endpoint: endpoint,
            simulatorUDID: "DEADBEEF-1234-5678-9ABC-DEF012345678"
        )

        XCTAssertEqual(device.simulatorUDID, "DEADBEEF-1234-5678-9ABC-DEF012345678")
    }

    func testDefaultIdentifiersNil() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp", endpoint: endpoint)

        XCTAssertNil(device.simulatorUDID)
        XCTAssertNil(device.installationId)
        XCTAssertNil(device.instanceId)
    }

    func testAllStoredTXTRecordFields() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(
            id: "test", name: "TestApp#abc",
            endpoint: endpoint,
            simulatorUDID: "SIM-UUID",
            installationId: "install-1",
            displayDeviceName: "Chris's iPhone",
            instanceId: "my-instance"
        )

        XCTAssertEqual(device.simulatorUDID, "SIM-UUID")
        XCTAssertEqual(device.installationId, "install-1")
        XCTAssertEqual(device.deviceName, "Chris's iPhone")
        XCTAssertEqual(device.instanceId, "my-instance")
    }

    func testDeviceNamePrefersBroadcastDeviceName() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(
            id: "test",
            name: "AccessibilityTestApp#abc123",
            endpoint: endpoint,
            displayDeviceName: "Office iPhone"
        )

        XCTAssertEqual(device.appName, "AccessibilityTestApp")
        XCTAssertEqual(device.deviceName, "Office iPhone")
    }

    func testExplicitConnectionTypeDoesNotDependOnIdPrefix() {
        let endpoint = NWEndpoint.hostPort(host: .ipv6(.loopback), port: 1234)
        let device = DiscoveredDevice(
            id: "00008120-1111111111111111",
            name: "Alpha Phone (USB)",
            endpoint: endpoint,
            displayDeviceName: "Alpha Phone",
            connectionType: .usb
        )

        XCTAssertEqual(device.connectionType, .usb)
        XCTAssertEqual(device.deviceName, "Alpha Phone")
    }

    func testDisplayNameDisambiguatesWithoutChangingResolutionIdentity() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let first = DiscoveredDevice(
            id: "first",
            name: "DemoApp#abc123",
            endpoint: endpoint,
            displayDeviceName: "Office iPhone"
        )
        let second = DiscoveredDevice(
            id: "second",
            name: "DemoApp#def456",
            endpoint: endpoint,
            displayDeviceName: "Office iPhone"
        )

        XCTAssertEqual(first.displayName(among: [first, second]), "DemoApp (Office iPhone) [abc123]")
        XCTAssertTrue(first.matches(resolutionQuery: "DemoApp"))
        XCTAssertTrue(first.matches(resolutionQuery: "Office iPhone"))
        XCTAssertTrue(first.matches(resolutionQuery: "abc"))
    }

    // MARK: - Filter Matching

    func testMatchesByName() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp#abc123", endpoint: endpoint)

        XCTAssertTrue(device.matches(resolutionQuery: "TestApp"))
        XCTAssertTrue(device.matches(resolutionQuery: "testapp")) // case-insensitive
        XCTAssertTrue(device.matches(resolutionQuery: " TestApp "))
        XCTAssertFalse(device.matches(resolutionQuery: "   "))
    }

    func testMatchesByAppName() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "MyApp#abc", endpoint: endpoint)

        XCTAssertTrue(device.matches(resolutionQuery: "MyApp"))
        XCTAssertTrue(device.matches(resolutionQuery: "myapp"))
        XCTAssertFalse(device.matches(resolutionQuery: "OtherApp"))
    }

    func testMatchesByDeviceName() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(
            id: "test",
            name: "TestApp#abc",
            endpoint: endpoint,
            displayDeviceName: "iPhone 16 Pro"
        )

        XCTAssertTrue(device.matches(resolutionQuery: "iPhone 16"))
        XCTAssertTrue(device.matches(resolutionQuery: "iphone 16 pro"))
    }

    func testMatchesByShortIdPrefix() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp#abc123", endpoint: endpoint)

        XCTAssertTrue(device.matches(resolutionQuery: "abc"))
        XCTAssertTrue(device.matches(resolutionQuery: "abc123"))
        // "123" still matches via name.contains (full name includes "abc123")
        XCTAssertTrue(device.matches(resolutionQuery: "123"))
    }

    func testMatchesByInstanceIdPrefix() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(
            id: "test", name: "TestApp",
            endpoint: endpoint,
            instanceId: "my-instance-42"
        )

        XCTAssertTrue(device.matches(resolutionQuery: "my-instance"))
        XCTAssertFalse(device.matches(resolutionQuery: "instance-42"))
    }

    func testMatchesBySimulatorUDIDPrefix() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(
            id: "test", name: "TestApp",
            endpoint: endpoint,
            simulatorUDID: "DEADBEEF-1234-5678-9ABC-DEF012345678"
        )

        XCTAssertTrue(device.matches(resolutionQuery: "DEADBEEF"))
        XCTAssertTrue(device.matches(resolutionQuery: "deadbeef"))
        XCTAssertFalse(device.matches(resolutionQuery: "1234-5678"))
    }

    func testMatchesByDiscoveryDeviceIDPrefix() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(
            id: "network-device-42",
            name: "TestApp",
            endpoint: endpoint
        )

        XCTAssertTrue(device.matches(resolutionQuery: "network-device"))
        XCTAssertTrue(device.matches(resolutionQuery: "network-device-42"))
        XCTAssertFalse(device.matches(resolutionQuery: "device-42"))
    }

    func testNoMatch() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(id: "test", name: "TestApp#abc", endpoint: endpoint)

        XCTAssertFalse(device.matches(resolutionQuery: "Android"))
        XCTAssertFalse(device.matches(resolutionQuery: "zzzzz"))
    }

    func testDiscoveryIdentityPrefersInstallationId() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let oldDevice = DiscoveredDevice(
            id: "old",
            name: "AccessibilityTestApp#a18032ae",
            endpoint: endpoint,

            installationId: "install-1",
            instanceId: "a18032ae"
        )
        let newDevice = DiscoveredDevice(
            id: "new",
            name: "AccessibilityTestApp#841803ea",
            endpoint: endpoint,

            installationId: "install-1",
            instanceId: "841803ea"
        )

        XCTAssertEqual(oldDevice.discoveryIdentity, newDevice.discoveryIdentity)
        XCTAssertEqual(oldDevice.discoveryIdentity.rawValue, "install|accessibilitytestapp|install-1")
    }

    func testDiscoveryIdentityFallsBackToServiceIdWithoutInstallationId() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let firstDevice = DiscoveredDevice(
            id: "first",
            name: "AccessibilityTestApp#a18032ae",
            endpoint: endpoint,
            instanceId: "a18032ae"
        )
        let secondDevice = DiscoveredDevice(
            id: "second",
            name: "AccessibilityTestApp#841803ea",
            endpoint: endpoint,
            instanceId: "841803ea"
        )

        // Without installationId, each device gets a unique service-based identity
        XCTAssertNotEqual(firstDevice.discoveryIdentity, secondDevice.discoveryIdentity)
        XCTAssertEqual(firstDevice.discoveryIdentity.rawValue, "service|first")
    }

    func testDiscoveryRegistryUpdatesSameServiceWithoutMutation() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let firstDevice = DiscoveredDevice(
            id: "AccessibilityTestApp#a18032ae",
            name: "AccessibilityTestApp#a18032ae",
            endpoint: endpoint,
            displayDeviceName: "Before"
        )
        let updatedDevice = DiscoveredDevice(
            id: "AccessibilityTestApp#a18032ae",
            name: "AccessibilityTestApp#a18032ae",
            endpoint: endpoint,
            displayDeviceName: "After"
        )

        var registry = DiscoveryRegistry()

        XCTAssertEqual(registry.recordFound(firstDevice), [.found(firstDevice)])
        XCTAssertTrue(registry.recordFound(updatedDevice).isEmpty)
        XCTAssertEqual(registry.devices.first?.deviceName, "After")
    }

    func testDiscoveryRegistryIgnoresUnknownServiceLoss() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(
            id: "AccessibilityTestApp#a18032ae",
            name: "AccessibilityTestApp#a18032ae",
            endpoint: endpoint
        )

        var registry = DiscoveryRegistry()

        XCTAssertEqual(registry.recordFound(device), [.found(device)])
        XCTAssertTrue(registry.recordLost(serviceName: "missing-service").isEmpty)
        XCTAssertEqual(registry.devices, [device])
    }

    func testDiscoveryRegistryDedupesSimulatorRelaunches() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let oldDevice = DiscoveredDevice(
            id: "AccessibilityTestApp#a18032ae",
            name: "AccessibilityTestApp#a18032ae",
            endpoint: endpoint,

            installationId: "install-1",
            instanceId: "a18032ae"
        )
        let newDevice = DiscoveredDevice(
            id: "AccessibilityTestApp#841803ea",
            name: "AccessibilityTestApp#841803ea",
            endpoint: endpoint,

            installationId: "install-1",
            instanceId: "841803ea"
        )

        var registry = DiscoveryRegistry()

        XCTAssertEqual(registry.recordFound(oldDevice), [.found(oldDevice)])
        XCTAssertEqual(registry.devices, [oldDevice])
        XCTAssertEqual(
            registry.recordFound(newDevice),
            [.lost(oldDevice), .found(newDevice)]
        )
        XCTAssertEqual(registry.devices, [newDevice])
    }

    func testDiscoveryRegistryPromotesNewestSiblingWhenCurrentAdDisappears() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let oldDevice = DiscoveredDevice(
            id: "AccessibilityTestApp#a18032ae",
            name: "AccessibilityTestApp#a18032ae",
            endpoint: endpoint,

            installationId: "install-1",
            instanceId: "a18032ae"
        )
        let newDevice = DiscoveredDevice(
            id: "AccessibilityTestApp#841803ea",
            name: "AccessibilityTestApp#841803ea",
            endpoint: endpoint,

            installationId: "install-1",
            instanceId: "841803ea"
        )

        var registry = DiscoveryRegistry()
        _ = registry.recordFound(oldDevice)
        _ = registry.recordFound(newDevice)

        XCTAssertEqual(
            registry.recordLost(serviceName: newDevice.id),
            [.lost(newDevice), .found(oldDevice)]
        )
        XCTAssertEqual(registry.devices, [oldDevice])
    }

    func testDiscoveryRegistryIgnoresHiddenSiblingRemoval() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let oldDevice = DiscoveredDevice(
            id: "AccessibilityTestApp#a18032ae",
            name: "AccessibilityTestApp#a18032ae",
            endpoint: endpoint,

            installationId: "install-1",
            instanceId: "a18032ae"
        )
        let newDevice = DiscoveredDevice(
            id: "AccessibilityTestApp#841803ea",
            name: "AccessibilityTestApp#841803ea",
            endpoint: endpoint,

            installationId: "install-1",
            instanceId: "841803ea"
        )

        var registry = DiscoveryRegistry()
        _ = registry.recordFound(oldDevice)
        _ = registry.recordFound(newDevice)

        XCTAssertTrue(registry.recordLost(serviceName: oldDevice.id).isEmpty)
        XCTAssertEqual(registry.devices, [newDevice])
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
    }

    func testDirectConnectTargetParsesLoopbackFilters() {
        let ipv4 = DiscoveredDevice.directConnectTarget(from: "127.0.0.1:8080")
        XCTAssertEqual(ipv4?.id, "127.0.0.1:8080")

        let ipv6 = DiscoveredDevice.directConnectTarget(from: "[::1]:9090")
        XCTAssertEqual(ipv6?.id, "::1:9090")
    }

    func testDirectConnectTargetRejectsNonLoopbackHostFilters() {
        XCTAssertNil(DiscoveredDevice.directConnectTarget(from: "example.com:8080"))
        XCTAssertNil(DiscoveredDevice.directConnectTarget(from: "QA:1"))
    }

    func testAllDiscoveryFields() {
        let endpoint = NWEndpoint.service(name: "test", type: "_test._tcp", domain: "local.", interface: nil)
        let device = DiscoveredDevice(
            id: "test", name: "TestApp#abc",
            endpoint: endpoint,
            simulatorUDID: "SIM-UUID",
            installationId: "install-1",
            displayDeviceName: "Chris's iPhone",
            instanceId: "my-instance"
        )

        XCTAssertEqual(device.simulatorUDID, "SIM-UUID")
        XCTAssertEqual(device.installationId, "install-1")
        XCTAssertEqual(device.deviceName, "Chris's iPhone")
        XCTAssertEqual(device.instanceId, "my-instance")
    }

    @ButtonHeistActor
    func testReachableCompletesOnTransportReadyWithoutStatusProbe() async {
        let device = DiscoveredDevice(
            id: "test",
            name: "ReachableApp#abc123",
            endpoint: NWEndpoint.hostPort(host: .ipv6(.loopback), port: 1)
        )
        let mockConnection = MockConnection()
        mockConnection.emitTransportReadyOnConnect = true

        let previousFactory = makeReachabilityConnection
        makeReachabilityConnection = { _ in mockConnection }
        defer { makeReachabilityConnection = previousFactory }

        let reachable = await [device].reachable(timeout: 0.2)

        XCTAssertEqual(reachable, [device])
        XCTAssertTrue(mockConnection.sent.isEmpty, "Reachability must not enter the pre-auth message lifecycle")
    }

    @ButtonHeistActor
    func testReachableReleasesProbeConnectionAfterCompletion() async {
        let device = DiscoveredDevice(
            id: "test",
            name: "ReachableApp#abc123",
            endpoint: NWEndpoint.hostPort(host: .ipv6(.loopback), port: 1)
        )

        let previousFactory = makeReachabilityConnection
        defer { makeReachabilityConnection = previousFactory }

        weak var weakProbe: ReachabilityProbeConnection?
        do {
            let probe = ReachabilityProbeConnection()
            weakProbe = probe
            makeReachabilityConnection = { _ in probe }

            let reachable = await [device].reachable(timeout: 0.2)
            XCTAssertEqual(reachable, [device])
        }

        makeReachabilityConnection = previousFactory
        for _ in 0..<10 {
            if weakProbe == nil { break }
            await Task.yield()
        }
        XCTAssertNil(weakProbe, "Reachability probe connection should deallocate after completion")
    }
}

@ButtonHeistActor
private final class ReachabilityProbeConnection: TransportReachabilityConnecting {
    var onEvent: (@ButtonHeistActor (ConnectionEvent) -> Void)?
    var onTransportReady: (@ButtonHeistActor () -> Void)?

    func connect() {
        onTransportReady?()
    }

    func disconnect() {}
}
