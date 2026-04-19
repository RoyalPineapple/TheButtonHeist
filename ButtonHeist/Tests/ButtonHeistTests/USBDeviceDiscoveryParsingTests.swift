#if os(macOS)
import XCTest
@testable import ButtonHeist

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
}
#endif
