import XCTest
@testable import ButtonHeist
import Network
import TheScore

final class DeviceResolverTests: XCTestCase {

    // MARK: - selectDevice

    @ButtonHeistActor
    func testSelectDeviceSingleDeviceNoFilter() async {
        let device = makeDevice(id: "dev1", name: "MyApp-iPhone#abc")
        let result = DeviceResolver.selectDevice(from: [device], filter: nil)
        XCTAssertEqual(result?.id, "dev1")
    }

    @ButtonHeistActor
    func testSelectDeviceMultipleDevicesNoFilterReturnsNil() async {
        let devices = [
            makeDevice(id: "dev1", name: "App1-Phone#a"),
            makeDevice(id: "dev2", name: "App2-Pad#b"),
        ]
        let result = DeviceResolver.selectDevice(from: devices, filter: nil)
        XCTAssertNil(result)
    }

    @ButtonHeistActor
    func testSelectDeviceEmptyArrayReturnsNil() async {
        let result = DeviceResolver.selectDevice(from: [], filter: nil)
        XCTAssertNil(result)
    }

    @ButtonHeistActor
    func testSelectDeviceWithFilterMatchesFirst() async {
        let devices = [
            makeDevice(id: "dev1", name: "MyApp-iPhone#abc"),
            makeDevice(id: "dev2", name: "OtherApp-iPad#def"),
        ]
        let result = DeviceResolver.selectDevice(from: devices, filter: "MyApp")
        XCTAssertEqual(result?.id, "dev1")
    }

    @ButtonHeistActor
    func testSelectDeviceWithFilterNoMatch() async {
        let devices = [
            makeDevice(id: "dev1", name: "MyApp-iPhone#abc"),
        ]
        let result = DeviceResolver.selectDevice(from: devices, filter: "Nonexistent")
        XCTAssertNil(result)
    }

    // MARK: - discoverySignature

    @ButtonHeistActor
    func testDiscoverySignatureEmpty() async {
        let signature = DeviceResolver.discoverySignature(for: [])
        XCTAssertEqual(signature, "")
    }

    @ButtonHeistActor
    func testDiscoverySignatureSorted() async {
        let devices = [
            makeDevice(id: "bravo", name: "B"),
            makeDevice(id: "alpha", name: "A"),
        ]
        let signature = DeviceResolver.discoverySignature(for: devices)
        XCTAssertEqual(signature, "alpha|bravo")
    }

    @ButtonHeistActor
    func testDiscoverySignatureSingleDevice() async {
        let devices = [makeDevice(id: "only", name: "Single")]
        let signature = DeviceResolver.discoverySignature(for: devices)
        XCTAssertEqual(signature, "only")
    }

    // MARK: - directConnectTarget fast path

    @ButtonHeistActor
    func testResolveDirectConnectSkipsDiscovery() async throws {
        var discoveryCallCount = 0
        let resolver = DeviceResolver(
            filter: "127.0.0.1:5555",
            discoveryTimeout: 1_000_000_000,
            getDiscoveredDevices: {
                discoveryCallCount += 1
                return []
            }
        )

        let device = try await resolver.resolve()
        XCTAssertEqual(discoveryCallCount, 0)
        XCTAssertEqual(device.id, "127.0.0.1:5555")
    }

    @ButtonHeistActor
    func testResolveNonLoopbackFilterDoesNotShortCircuit() async {
        let resolver = DeviceResolver(
            filter: "192.168.1.100:5555",
            discoveryTimeout: 100_000_000,
            getDiscoveredDevices: { [] }
        )

        do {
            _ = try await resolver.resolve()
            XCTFail("Expected error for no devices found")
        } catch {
            // Expected: no matching device or no device found
        }
    }

    // MARK: - Helpers

    private func makeDevice(id: String, name: String) -> DiscoveredDevice {
        DiscoveredDevice(
            id: id, name: name,
            endpoint: .hostPort(host: "127.0.0.1", port: 9999)
        )
    }
}
