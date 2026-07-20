#if os(macOS)
import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist

final class USBDeviceDiscoveryParsingTests: XCTestCase {

    func testParseConnectedDeviceNamesIgnoresDisconnectedRows() {
        let output = """
            Name                 Hostname                                Identifier                              State
            -------------------  --------------------------------------  --------------------------------------  -----------
            Alpha Phone          alpha-phone.coredevice.local            00008120-1111111111111111              connected
            Banana Phone         banana-phone.coredevice.local           00008120-2222222222222222              disconnected
            Carrot Tablet        carrot-tablet.coredevice.local          00008120-3333333333333333              connected
            """

        let names = USBDeviceDiscovery.parseConnectedDeviceNames(from: output)

        XCTAssertEqual(names, ["Alpha Phone", "Carrot Tablet"])
    }

    func testParseConnectedDeviceNamesPreservesSpacesInDeviceName() {
        let output = """
            Name                     Hostname                                  Identifier                              State
            -----------------------  ----------------------------------------  --------------------------------------  -----------
            Test Device 15 Pro Max   test-device-15-pro-max.coredevice.local   00008120-4444444444444444              connected
            """

        let names = USBDeviceDiscovery.parseConnectedDeviceNames(from: output)

        XCTAssertEqual(names, ["Test Device 15 Pro Max"])
    }

    func testParseConnectedUSBDevicesKeepsIdentifierSeparateFromName() {
        let output = """
            Name                 Hostname                                Identifier                              State
            -------------------  --------------------------------------  --------------------------------------  -----------
            Alpha Phone          alpha-phone.coredevice.local            00008120-1111111111111111              connected
            """

        let devices = USBDeviceDiscovery.parseConnectedUSBDevices(from: output)

        XCTAssertEqual(devices, [
            USBDeviceDiscovery.ConnectedUSBDevice(
                name: "Alpha Phone",
                identifier: "00008120-1111111111111111"
            ),
        ])
    }

    func testRunProcessTimeoutReturnsForProcessIgnoringTerminate() async {
        let output = await USBDeviceDiscovery.runProcess(
            "/bin/sh",
            arguments: ["-c", "trap '' TERM; while :; do :; done"],
            timeout: .milliseconds(100)
        )

        XCTAssertNil(output)
    }

    @ButtonHeistActor
    func testStartIsIdempotentWhilePollSessionIsActive() async {
        let pollGate = USBDiscoveryPollGate()
        let discovery = USBDeviceDiscovery(
            port: 1234,
            discoverConnectedDevices: { await pollGate.connectedDevices() },
            findTunnelAddress: { await pollGate.tunnelAddress() }
        )
        defer { discovery.stop() }
        var readyStates: [Bool] = []
        discovery.onEvent = { event in
            if case .stateChanged(let isReady) = event {
                readyStates.append(isReady)
            }
        }

        discovery.start()
        discovery.start()
        await pollGate.waitForPollRequest()
        await pollGate.resume(devices: [], tunnelAddress: nil)

        XCTAssertEqual(readyStates, [true])
    }

    @ButtonHeistActor
    func testStopIgnoresStalePollResultsFromCancelledSession() async {
        let pollGate = USBDiscoveryPollGate()
        let discovery = USBDeviceDiscovery(
            port: 1234,
            discoverConnectedDevices: { await pollGate.connectedDevices() },
            findTunnelAddress: { await pollGate.tunnelAddress() }
        )
        let device = USBDeviceDiscovery.ConnectedUSBDevice(
            name: "Stale Phone",
            identifier: "00008120-5555555555555555"
        )
        var foundDevices: [DiscoveredDevice] = []
        discovery.onEvent = { event in
            if case .found(let device) = event {
                foundDevices.append(device)
            }
        }

        discovery.start()
        await pollGate.waitForPollRequest()
        discovery.stop()
        await pollGate.resume(devices: [device], tunnelAddress: "fd12:3456::1")
        await Task.yield()

        XCTAssertTrue(discovery.discoveredDevices.isEmpty)
        XCTAssertTrue(foundDevices.isEmpty)
    }
}

private actor USBDiscoveryPollGate {
    private var devicesContinuation: CheckedContinuation<[USBDeviceDiscovery.ConnectedUSBDevice], Never>?
    private var tunnelContinuation: CheckedContinuation<String?, Never>?
    private var pollRequestCount = 0

    func connectedDevices() async -> [USBDeviceDiscovery.ConnectedUSBDevice] {
        pollRequestCount += 1
        return await withCheckedContinuation { continuation in
            devicesContinuation = continuation
        }
    }

    func tunnelAddress() async -> String? {
        pollRequestCount += 1
        return await withCheckedContinuation { continuation in
            tunnelContinuation = continuation
        }
    }

    func waitForPollRequest() async {
        while pollRequestCount < 2 {
            await Task.yield()
        }
    }

    func resume(devices: [USBDeviceDiscovery.ConnectedUSBDevice], tunnelAddress: String?) {
        devicesContinuation?.resume(returning: devices)
        devicesContinuation = nil
        tunnelContinuation?.resume(returning: tunnelAddress)
        tunnelContinuation = nil
    }
}
#endif
